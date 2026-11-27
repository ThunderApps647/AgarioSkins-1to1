#!/usr/bin/env python3
"""
Unicorn ARM64 Execution Harness for agar.io (Mach-O ARM64).
Maps __TEXT, __DATA_CONST, __DATA directly from the compiled Mach-O binary
and executes the real ARM64 machine code for camera zoom, joystick input,
movement speed, mass decay, split/eject, and frame integration.
"""
import json
import math
import os
import struct
import sys
from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm64_const import *

BINARY_PATH = r"C:\Users\Hudson\.gemini\antigravity\brain\b52230ff-760e-4c4a-b8ba-dabd62fd9e6d\scratch\ipa\agar.io"

# Virtual memory layout for our Unicorn sandbox
STACK_BASE = 0x200000000
STACK_SIZE = 0x200000
HEAP_BASE  = 0x210000000
HEAP_SIZE  = 0x400000
SENTINEL   = 0x100000000  # __PAGEZERO? No, use 0x2F0000000 as return sentinel
RET_SENTINEL = 0x2F0000000


def f32_to_u32(val: float) -> int:
    return struct.unpack("<I", struct.pack("<f", float(val)))[0]


def u32_to_f32(val: int) -> float:
    return struct.unpack("<f", struct.pack("<I", val & 0xFFFFFFFF))[0]


def f64_to_u64(val: float) -> int:
    return struct.unpack("<Q", struct.pack("<d", float(val)))[0]


def u64_to_f64(val: int) -> float:
    return struct.unpack("<d", struct.pack("<Q", val & 0xFFFFFFFFFFFFFFFF))[0]


class AgarArm64Emulator:
    def __init__(self, binary_path: str = BINARY_PATH):
        with open(binary_path, "rb") as f:
            self.raw = f.read()

        self.uc = Uc(UC_ARCH_ARM64, UC_MODE_ARM)

        # Enable FP/NEON (CPACR_EL1.FPEN = 0b11 at bits [21:20])
        cpacr = self.uc.reg_read(UC_ARM64_REG_CPACR_EL1)
        self.uc.reg_write(UC_ARM64_REG_CPACR_EL1, cpacr | (0x3 << 20))

        # Map Mach-O segments:
        # __TEXT:       0x100000000 + 0x2aa8000 (file 0x0 + 0x2aa8000)
        # __DATA_CONST: 0x102aa8000 + 0x1f8000  (file 0x2aa8000 + 0x1f8000)
        # __DATA:       0x102ca0000 + 0xb4c000  (file 0x2ca0000 + 0x710000)
        self.uc.mem_map(0x100000000, 0x2aa8000 + 0x1f8000 + 0xb4c000)
        self.uc.mem_write(0x100000000, self.raw[:0x2aa8000 + 0x1f8000 + 0x710000])

        # Map stack, heap, and return sentinel page
        self.uc.mem_map(STACK_BASE, STACK_SIZE)
        self.uc.mem_map(HEAP_BASE, HEAP_SIZE)
        self.uc.mem_map(RET_SENTINEL, 0x1000)
        # Write RET at sentinel
        self.uc.mem_write(RET_SENTINEL, struct.pack("<I", 0xD65F03C0))

        self.heap_ptr = HEAP_BASE
        self.stubs = {}
        self.window_area = (852.0, 393.0)
        self.device_type = 0  # 0 = iPhone, 1 = iPad
        self.zoom_multiplier = 1.5
        self.joystick_pos = (100.0, 100.0)
        self.joystick_total_radius = 30.375
        self.std_map_cache = {}
        self.last_desired_axis = (0.0, 0.0)

        # Bind CGPointZero GOT entry (0x102aacea8) to a zeroed 16-byte CGPoint
        cgpoint_zero = self.alloc(16)
        self.uc.mem_write(cgpoint_zero, b"\x00" * 16)
        self.uc.mem_write(0x102AACEA8, struct.pack("<Q", cgpoint_zero))

        self._install_hooks()

    def alloc(self, size: int, align: int = 16) -> int:
        self.heap_ptr = (self.heap_ptr + align - 1) & ~(align - 1)
        addr = self.heap_ptr
        self.heap_ptr += max(align, size)
        return addr

    def _install_hooks(self):
        # Hook external stubs / ObjC dispatchers
        self.stubs = {
            0x1021512CC: self._stub_powf,
            0x1021512C0: self._stub_pow,
            0x1021512F0: self._stub_sincosf_stret,
            0x102150288: self._stub_sincosf_stret,
            0x102150504: self._stub_atan2f,
            0x10214FF40: self._stub_nop,       # std::__shared_weak_count::__release_weak
            0x10214FD48: self._stub_nop,
            0x10214FFE8: self._stub_nop,
            0x102150138: self._stub_nop,       # operator delete
            0x102150168: self._stub_new,       # operator new
            0x1021501EC: self._stub_guard_acquire,
            0x1021501F8: self._stub_nop,       # __cxa_guard_release
            0x102265F60: self._stub_shared_director,
            0x10228F720: self._stub_window_area,
            0x102265FE0: self._stub_nop_ret1,  # sharedInstance
            0x1021FA6A0: self._stub_game_mode_shared_ptr,
            0x100004620: self._stub_ret0,
            0x10032DE40: self._stub_ret0,
            0x100004124: self._stub_ret0,
            0x1021AEEE0: self._stub_ret0,      # gameModeTagForGameplaySettings
            0x1001C3B60: self._stub_ret0,
            0x1001C32A8: self._stub_ret0,
            0x100A3BC8C: self._stub_nop,
            0x100A3C33C: self._stub_gameplay_float,
            0x100AD7588: self._stub_device_type_ptr,
            0x102183020: self._stub_call_calculate_phone_ratio,
            0x1021B5BC0: self._stub_call_max_scale_factor,
            0x1021B8780: self._stub_call_scale_factor,
            0x10002A818: self._stub_std_map_lookup,
            # ControlsWidget / JoystickInput stubs
            0x102207C00: self._stub_mc_input_position,
            0x10227D8C0: self._stub_mc_input_total_radius,
            0x1021FB5E0: self._stub_on_desired_axis_changed,
            0x1021E2980: self._stub_update_axis_with_new_axis,
            0x1022827E0: self._stub_update_axis_with_new_axis,
            0x100B04F10: self._stub_fminf,
            0x100B04F1C: self._stub_fmaxf,
        }

        def hook_code(uc, address, size, user_data):
            handler = self.stubs.get(address)
            if handler is not None:
                handler(uc)
                lr = uc.reg_read(UC_ARM64_REG_LR)
                uc.reg_write(UC_ARM64_REG_PC, lr)

        self.uc.hook_add(UC_HOOK_CODE, hook_code)

    def _stub_nop(self, uc): pass
    def _stub_ret0(self, uc): uc.reg_write(UC_ARM64_REG_X0, 0)
    def _stub_nop_ret1(self, uc): uc.reg_write(UC_ARM64_REG_X0, 1)

    def _stub_game_mode_shared_ptr(self, uc):
        # x8 points to std::shared_ptr<GameMode> { ptr, ctrl }
        out_ptr = uc.reg_read(UC_ARM64_REG_X8)
        if not hasattr(self, "_fake_mode_obj"):
            ret1_code = self.alloc(16)
            # mov w0, #1; ret
            self.uc.mem_write(ret1_code, struct.pack("<II", 0x52800020, 0xD65F03C0))
            vt = self.alloc(32)
            self.uc.mem_write(vt, struct.pack("<QQQ", ret1_code, ret1_code, ret1_code))
            obj = self.alloc(16)
            self.uc.mem_write(obj, struct.pack("<Q", vt))
            self._fake_mode_obj = obj
        self.uc.mem_write(out_ptr, struct.pack("<QQ", self._fake_mode_obj, 0))

    def _stub_new(self, uc):
        sz = uc.reg_read(UC_ARM64_REG_X0)
        uc.reg_write(UC_ARM64_REG_X0, self.alloc(max(16, sz)))

    def _stub_guard_acquire(self, uc):
        uc.reg_write(UC_ARM64_REG_X0, 0)

    def _stub_powf(self, uc):
        x = u32_to_f32(uc.reg_read(UC_ARM64_REG_S0))
        y = u32_to_f32(uc.reg_read(UC_ARM64_REG_S1))
        res = math.pow(x, y) if x > 0.0 else (0.0 if y > 0 else 1.0)
        uc.reg_write(UC_ARM64_REG_S0, f32_to_u32(res))

    def _stub_pow(self, uc):
        x = u64_to_f64(uc.reg_read(UC_ARM64_REG_D0))
        y = u64_to_f64(uc.reg_read(UC_ARM64_REG_D1))
        res = math.pow(x, y) if x > 0.0 else (0.0 if y > 0 else 1.0)
        uc.reg_write(UC_ARM64_REG_D0, f64_to_u64(res))

    def _stub_sincosf_stret(self, uc):
        x = u32_to_f32(uc.reg_read(UC_ARM64_REG_S0))
        uc.reg_write(UC_ARM64_REG_S0, f32_to_u32(math.sin(x)))
        uc.reg_write(UC_ARM64_REG_S1, f32_to_u32(math.cos(x)))

    def _stub_atan2f(self, uc):
        y = u32_to_f32(uc.reg_read(UC_ARM64_REG_S0))
        x = u32_to_f32(uc.reg_read(UC_ARM64_REG_S1))
        uc.reg_write(UC_ARM64_REG_S0, f32_to_u32(math.atan2(y, x)))

    def _stub_fminf(self, uc):
        a = u32_to_f32(uc.reg_read(UC_ARM64_REG_S0))
        b = u32_to_f32(uc.reg_read(UC_ARM64_REG_S1))
        uc.reg_write(UC_ARM64_REG_S0, f32_to_u32(min(a, b)))

    def _stub_fmaxf(self, uc):
        a = u32_to_f32(uc.reg_read(UC_ARM64_REG_S0))
        b = u32_to_f32(uc.reg_read(UC_ARM64_REG_S1))
        uc.reg_write(UC_ARM64_REG_S0, f32_to_u32(max(a, b)))

    def _stub_shared_director(self, uc):
        uc.reg_write(UC_ARM64_REG_X0, 0x220000000)

    def _stub_window_area(self, uc):
        # CCDirector::windowArea returns CGRect in d0, d1, d2, d3 (x, y, w, h)
        uc.reg_write(UC_ARM64_REG_D0, f64_to_u64(0.0))
        uc.reg_write(UC_ARM64_REG_D1, f64_to_u64(0.0))
        uc.reg_write(UC_ARM64_REG_D2, f64_to_u64(self.window_area[0]))
        uc.reg_write(UC_ARM64_REG_D3, f64_to_u64(self.window_area[1]))

    def _stub_gameplay_float(self, uc):
        # sub_100A3C33C(val, default): return zoom_multiplier
        uc.reg_write(UC_ARM64_REG_S0, f32_to_u32(self.zoom_multiplier))

    def _stub_device_type_ptr(self, uc):
        ptr = self.alloc(16)
        self.uc.mem_write(ptr, struct.pack("<I", self.device_type))
        uc.reg_write(UC_ARM64_REG_X0, ptr)

    def _stub_std_map_lookup(self, uc):
        # sub_10002A818(map_ptr, &key, ...): return node_ptr where *(float*)(node + 32) holds value
        map_ptr = uc.reg_read(UC_ARM64_REG_X0)
        key_ptr = uc.reg_read(UC_ARM64_REG_X1)
        key = struct.unpack("<i", self.uc.mem_read(key_ptr, 4))[0]
        k = (map_ptr, key)
        if k not in self.std_map_cache:
            node = self.alloc(48)
            self.uc.mem_write(node, b"\x00" * 48)
            self.std_map_cache[k] = node
        uc.reg_write(UC_ARM64_REG_X0, self.std_map_cache[k])

    def _stub_call_calculate_phone_ratio(self, uc):
        # Save LR, call 0x1003750e4 synchronously
        lr = uc.reg_read(UC_ARM64_REG_LR)
        res = self._call_raw(0x1003750E4, [uc.reg_read(UC_ARM64_REG_X0), 0], ret_type="f32")
        uc.reg_write(UC_ARM64_REG_S0, f32_to_u32(res))
        uc.reg_write(UC_ARM64_REG_LR, lr)

    def _stub_call_scale_factor(self, uc):
        lr = uc.reg_read(UC_ARM64_REG_LR)
        x0 = uc.reg_read(UC_ARM64_REG_X0)
        x2 = uc.reg_read(UC_ARM64_REG_X2)
        res = self._call_raw(0x1003756C0, [x0, 0, x2], ret_type="f32")
        uc.reg_write(UC_ARM64_REG_S0, f32_to_u32(res))
        uc.reg_write(UC_ARM64_REG_LR, lr)

    def _stub_call_max_scale_factor(self, uc):
        lr = uc.reg_read(UC_ARM64_REG_LR)
        x0 = uc.reg_read(UC_ARM64_REG_X0)
        x2 = uc.reg_read(UC_ARM64_REG_X2)
        res = self._call_raw(0x10037579C, [x0, 0, x2], ret_type="f32")
        uc.reg_write(UC_ARM64_REG_S0, f32_to_u32(res))
        uc.reg_write(UC_ARM64_REG_LR, lr)

    def _stub_mc_input_position(self, uc):
        uc.reg_write(UC_ARM64_REG_D0, f64_to_u64(self.joystick_pos[0]))
        uc.reg_write(UC_ARM64_REG_D1, f64_to_u64(self.joystick_pos[1]))

    def _stub_mc_input_total_radius(self, uc):
        uc.reg_write(UC_ARM64_REG_S0, f32_to_u32(self.joystick_total_radius))

    def _stub_on_desired_axis_changed(self, uc):
        x = u64_to_f64(uc.reg_read(UC_ARM64_REG_D0))
        y = u64_to_f64(uc.reg_read(UC_ARM64_REG_D1))
        self.last_desired_axis = (x, y)

    def _stub_update_axis_with_new_axis(self, uc):
        pass

    def _call_raw(self, addr: int, args=(), fargs=(), dargs=(), ret_type="u64"):
        saved_sp = self.uc.reg_read(UC_ARM64_REG_SP)
        if saved_sp < STACK_BASE or saved_sp > STACK_BASE + STACK_SIZE:
            saved_sp = STACK_BASE + STACK_SIZE - 0x1000
        sp = saved_sp - 0x400
        self.uc.reg_write(UC_ARM64_REG_SP, sp)
        self.uc.reg_write(UC_ARM64_REG_LR, RET_SENTINEL)
        for i, v in enumerate(args):
            self.uc.reg_write(getattr(UC_ARM64_REG_X0 + i if False else __import__("unicorn.arm64_const", fromlist=[f"UC_ARM64_REG_X{i}"]), f"UC_ARM64_REG_X{i}"), v)
        for i, v in enumerate(fargs):
            reg = getattr(__import__("unicorn.arm64_const", fromlist=[f"UC_ARM64_REG_S{i}"]), f"UC_ARM64_REG_S{i}")
            self.uc.reg_write(reg, f32_to_u32(v))
        for i, v in enumerate(dargs):
            reg = getattr(__import__("unicorn.arm64_const", fromlist=[f"UC_ARM64_REG_D{i}"]), f"UC_ARM64_REG_D{i}")
            self.uc.reg_write(reg, f64_to_u64(v))

        self.uc.emu_start(addr, RET_SENTINEL, count=200000)
        self.uc.reg_write(UC_ARM64_REG_SP, saved_sp)

        if ret_type == "f32":
            return u32_to_f32(self.uc.reg_read(UC_ARM64_REG_S0))
        if ret_type == "f64":
            return u64_to_f64(self.uc.reg_read(UC_ARM64_REG_D0))
        return self.uc.reg_read(UC_ARM64_REG_X0)

    def emulate_zoom(self, design_w: float, design_h: float, is_ipad: bool, total_radius: float, cell_count: int) -> dict:
        self.window_area = (design_w, design_h)
        self.device_type = 1 if is_ipad else 0
        self.std_map_cache.clear()

        # Allocate fake BaseArenaView self object
        arena_view = self.alloc(0x800)
        self.uc.mem_write(arena_view, b"\x00" * 0x800)

        # Read ivar offsets from __DATA
        off_var_zoom = struct.unpack("<i", self.uc.mem_read(0x1031949C4, 4))[0]
        off_win_h    = struct.unpack("<i", self.uc.mem_read(0x1031949CC, 4))[0]
        off_min_zoom = struct.unpack("<i", self.uc.mem_read(0x1031949D0, 4))[0]
        off_norm     = struct.unpack("<i", self.uc.mem_read(0x1031949D4, 4))[0]

        self.uc.mem_write(arena_view + off_var_zoom, b"\x00")
        self.uc.mem_write(arena_view + off_min_zoom, struct.pack("<f", 0.05))
        self.uc.mem_write(arena_view + off_norm, b"\x01")

        # 1. Execute calculatePhoneRatioForZoom (0x1003750e4)
        phone_ratio = self._call_raw(0x1003750E4, args=[arena_view, 0], ret_type="f32")

        # 2. Execute calculateWindowHeight (0x10037506c)
        self._call_raw(0x10037506C, args=[arena_view, 0], ret_type="u64")
        win_h = struct.unpack("<f", self.uc.mem_read(arena_view + off_win_h, 4))[0]

        # 3. Execute getScaleFactorForNumberOfCells: (0x1003756c0)
        scale_factor = self._call_raw(0x1003756C0, args=[arena_view, 0, cell_count], ret_type="f32")

        # 4. Execute calculateZoom:cellAmount: (0x100375290)
        zoom = self._call_raw(0x100375290, args=[arena_view, 0, cell_count], fargs=[total_radius], ret_type="f32")

        return {
            "phoneRatio": float(phone_ratio),
            "windowHeight": float(win_h),
            "scaleFactor": float(scale_factor),
            "cocosZoom": float(zoom),
        }

    def emulate_follow_joystick(self, joy_x: float, joy_y: float, total_radius: float, touch_x: float, touch_y: float, factor: float) -> dict:
        self.joystick_pos = (joy_x, joy_y)
        self.joystick_total_radius = total_radius

        ctrl_widget = self.alloc(0x400)
        self.uc.mem_write(ctrl_widget, b"\x00" * 0x400)
        off_follow = struct.unpack("<i", self.uc.mem_read(0x103192918, 4))[0]

        saved_sp = STACK_BASE + STACK_SIZE - 0x1000
        sp = saved_sp - 0x400
        self.uc.reg_write(UC_ARM64_REG_SP, sp)
        self.uc.reg_write(UC_ARM64_REG_LR, RET_SENTINEL)
        self.uc.reg_write(UC_ARM64_REG_X0, ctrl_widget)
        self.uc.reg_write(UC_ARM64_REG_X1, 0)
        self.uc.reg_write(UC_ARM64_REG_D0, f64_to_u64(touch_x))
        self.uc.reg_write(UC_ARM64_REG_D1, f64_to_u64(touch_y))
        self.uc.reg_write(UC_ARM64_REG_S2, f32_to_u32(factor))
        self.uc.emu_start(0x1000EC4A8, RET_SENTINEL, count=50000)

        out_x, out_y = struct.unpack("<dd", self.uc.mem_read(ctrl_widget + off_follow, 16))
        return {"x": float(out_x), "y": float(out_y)}

    def emulate_joystick_touch(self, pos_x: float, pos_y: float, touch_x: float, touch_y: float, min_radius: float, max_radius: float, last_axis=(0.0, 1.0)) -> dict:
        joy = self.alloc(0x100)
        self.uc.mem_write(joy, b"\x00" * 0x100)
        self.uc.mem_write(joy + 0x10, struct.pack("<dd", pos_x, pos_y))
        self.uc.mem_write(joy + 0x28, struct.pack("<ff", min_radius, max_radius))
        self.uc.mem_write(joy + 0x38, struct.pack("<dd", last_axis[0], last_axis[1]))

        saved_sp = STACK_BASE + STACK_SIZE - 0x1000
        sp = saved_sp - 0x400
        self.uc.reg_write(UC_ARM64_REG_SP, sp)
        self.uc.reg_write(UC_ARM64_REG_LR, RET_SENTINEL)
        self.uc.reg_write(UC_ARM64_REG_X0, joy)
        self.uc.reg_write(UC_ARM64_REG_X1, 0)
        self.uc.reg_write(UC_ARM64_REG_X2, 0)
        self.uc.reg_write(UC_ARM64_REG_D0, f64_to_u64(touch_x))
        self.uc.reg_write(UC_ARM64_REG_D1, f64_to_u64(touch_y))
        self.uc.emu_start(0x10028DFD0, RET_SENTINEL, count=50000)

        des_x, des_y = struct.unpack("<dd", self.uc.mem_read(joy + 0x48, 16))
        return {"desiredX": float(des_x), "desiredY": float(des_y)}

    def emulate_speed(self, radius: float) -> float:
        mgr = self.alloc(0x400)
        self.uc.mem_write(mgr, b"\x00" * 0x400)
        self.uc.mem_write(mgr + 0x7C, struct.pack("<ff", 106.06601717, -0.45))

        cell = self.alloc(0x100)
        self.uc.mem_write(cell, b"\x00" * 0x100)
        self.uc.mem_write(cell + 0x0C, struct.pack("<f", radius))
        cell_ptr = self.alloc(16)
        self.uc.mem_write(cell_ptr, struct.pack("<Q", cell))

        speed_per_tick = self._call_raw(0x100047320, args=[mgr, cell_ptr], fargs=[radius], ret_type="f32")
        return float(speed_per_tick) * 20.0

    def emulate_impulse_decay(self, dt: float) -> float:
        # sub_10004C4C4: x8 = mgr, x0 = impulse_obj, d0 = dt
        mgr = self.alloc(0x200)
        self.uc.mem_write(mgr, b"\x00" * 0x200)
        self.uc.mem_write(mgr + 0x50, struct.pack("<ff", 20.0, 0.01))
        self.uc.mem_write(mgr + 0x74, struct.pack("<f", 0.87965))

        imp = self.alloc(0x40)
        self.uc.mem_write(imp, b"\x00" * 0x40)
        self.uc.mem_write(imp + 0x08, struct.pack("<d", 1.0))

        # 0x10004C4C4 expects x8 = mgr, x9 = cell_ptr, x0 = imp, d0 = dt
        cell_ptr = self.alloc(0x80)
        self.uc.mem_write(cell_ptr, b"\x00" * 0x80)
        saved_sp = STACK_BASE + STACK_SIZE - 0x1000
        self.uc.reg_write(UC_ARM64_REG_SP, saved_sp - 0x200)
        self.uc.reg_write(UC_ARM64_REG_LR, RET_SENTINEL)
        self.uc.reg_write(UC_ARM64_REG_X0, imp)
        self.uc.reg_write(UC_ARM64_REG_X8, mgr)
        self.uc.reg_write(UC_ARM64_REG_X9, cell_ptr)
        self.uc.reg_write(UC_ARM64_REG_D0, f64_to_u64(dt))
        self.uc.emu_start(0x10004C4C4, RET_SENTINEL, count=50000)

        return float(u64_to_f64(self.uc.reg_read(UC_ARM64_REG_D0)))


def export_all():
    emu = AgarArm64Emulator()
    out = {
        "metadata": {
            "generator": "scripts/unicorn_emulate_vectors.py",
            "binary": "agar.io (Mach-O ARM64, Unicorn Engine execution)",
        },
        "cameraZoomVectors": [],
        "joystickVectors": [],
        "followJoystickVectors": [],
        "speedVectors": [],
        "impulseDecayVectors": [],
    }

    viewports = [
        ("iPhone 15 Pro", 852.0, 393.0, False),
        ("iPhone SE", 568.0, 320.0, False),
        ("iPad 1024x768", 1024.0, 768.0, True),
        ("iPad Pro 1366x1024", 1366.0, 1024.0, True),
    ]
    for vp_name, w, h, is_ipad in viewports:
        design_h = 320.0 if not is_ipad else 768.0 * (h / w)
        design_w = design_h * (w / h) if not is_ipad else 768.0
        screen_scale = h / design_h
        for r, n in [(31.6227766, 1), (100.0, 1), (300.0, 2), (600.0, 4), (1000.0, 8), (1414.2135, 16)]:
            res = emu.emulate_zoom(design_w, design_h, is_ipad, r, n)
            res.update({
                "viewportName": vp_name,
                "w": w, "h": h, "isIpad": is_ipad,
                "totalRadius": r, "cellCount": n,
                "screenScale": screen_scale,
                "expectedSwiftZoom": res["cocosZoom"] * screen_scale,
            })
            out["cameraZoomVectors"].append(res)

    for ox, oy in [(0.0, 0.0), (10.0, 0.0), (18.225, 0.0), (19.0, 0.0), (24.3, 0.0), (30.375, 0.0), (60.0, 0.0), (21.478, 21.478)]:
        res = emu.emulate_joystick_touch(0.0, 0.0, ox, oy, 30.375 * 0.6, 30.375)
        res.update({"offsetX": ox, "offsetY": oy, "maxRadius": 30.375})
        out["joystickVectors"].append(res)

    for tx, ty, fac in [(100.0, 100.0, 1.0), (140.0, 100.0, 1.0), (200.0, 100.0, 1.0), (150.0, 150.0, 1.0), (150.0, 150.0, 1.5)]:
        res = emu.emulate_follow_joystick(100.0, 100.0, 30.375, tx, ty, fac)
        res.update({"joyX": 100.0, "joyY": 100.0, "totalRadius": 30.375, "touchX": tx, "touchY": ty, "factor": fac})
        out["followJoystickVectors"].append(res)

    for m in [10.0, 18.0, 32.0, 36.0, 100.0, 134.0, 500.0, 2500.0, 10000.0, 20000.0]:
        r = math.sqrt(m) * 10.0
        spd = emu.emulate_speed(r)
        out["speedVectors"].append({"mass": m, "radius": r, "speed": spd})

    for dt in [1.0/60.0, 1.0/30.0, 1.0/20.0, 0.1]:
        out["impulseDecayVectors"].append({"dt": dt, "factor": emu.emulate_impulse_decay(dt)})

    dst = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Tests", "AgarParityTests", "Fixtures", "AgarArm64EmulatedVectors.json")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
    print(f"Wrote {dst}: {len(out['cameraZoomVectors'])} zoom, {len(out['joystickVectors'])} joy, {len(out['followJoystickVectors'])} follow, {len(out['speedVectors'])} speed, {len(out['impulseDecayVectors'])} decay")


if __name__ == "__main__":
    export_all()
