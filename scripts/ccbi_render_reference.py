#!/usr/bin/env python3
"""
Exact CocosBuilder (.ccbi) Reference Renderer + Node Bounding-Box Manifest Generator.
Uses Resources/AgarAssets/ccbi, atlases/*-ipadhd.{plist,png}, mcfs/*.plist, sprites/*,
en_text.json, and Resources/*.ttf to render iPhone (852x393 @2x) and iPad (1024x768 @2x)
reference PNGs and export a node-completeness bounding-box manifest.
"""
import json
import os
import plistlib
import re
import struct
import sys
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_DIR = os.path.join(REPO_ROOT, "Resources", "AgarAssets")
CCBI_DIR = os.path.join(ASSETS_DIR, "ccbi")
ATLAS_DIR = os.path.join(ASSETS_DIR, "atlases")
MCFS_DIR = os.path.join(ASSETS_DIR, "mcfs")
SPRITE_DIR = os.path.join(ASSETS_DIR, "sprites")
FONTS_DIR = os.path.join(REPO_ROOT, "Resources")
OUT_DIR = os.path.join(REPO_ROOT, "Tests", "AgarParityTests", "Fixtures", "ccbi_ref")


class CCBIReader:
    def __init__(self, data: bytes):
        self.d = data
        self.pos = 0
        self.ver = 0
        self.strs = []

    def u8(self) -> int:
        v = self.d[self.pos]
        self.pos += 1
        return v

    def elias(self) -> int:
        bp = self.pos
        bitp = 0
        zeros = -1
        while bp < len(self.d):
            b = (self.d[bp] >> bitp) & 1
            bitp += 1
            if bitp >= 8:
                bitp = 0
                bp += 1
            zeros += 1
            if b == 1:
                break
        val = 0
        rem = zeros + 1
        while rem > 1 and bp < len(self.d):
            b = (self.d[bp] >> bitp) & 1
            bitp += 1
            if bitp >= 8:
                bitp = 0
                bp += 1
            val |= b << (rem - 2)
            rem -= 1
        if bitp > 0:
            bp += 1
        self.pos = bp
        return ((1 << zeros) | val) - 1

    def read_int(self, signed=False) -> int:
        res = 0
        shift = 0
        while self.pos < len(self.d):
            b = self.d[self.pos]
            self.pos += 1
            res |= (b & 0x7F) << shift
            if (b & 0x80) == 0:
                break
            shift += 7
        if not signed:
            return res
        return -((res >> 1) + 1) if (res & 1) else (res >> 1)

    def read_utf8(self) -> str:
        ln = (self.d[self.pos] << 8) | self.d[self.pos + 1]
        self.pos += 2
        s = self.d[self.pos : self.pos + ln].decode("utf-8", errors="replace")
        self.pos += ln
        return s

    def read_str(self) -> str:
        idx = self.read_int(False)
        return self.strs[idx] if 0 <= idx < len(self.strs) else ""

    def read_float(self) -> float:
        t = self.u8()
        if t == 0: return 0.0
        if t == 1: return 1.0
        if t == 2: return -1.0
        if t == 3: return 0.5
        if t == 4: return float(self.read_int(True))
        v = struct.unpack_from("<f", self.d, self.pos)[0]
        self.pos += 4
        return v

    def read_prop_val(self, pt: int):
        if pt == 0:
            x, y = self.read_float(), self.read_float()
            t, a, b = self.u8(), self.u8(), self.u8()
            c = self.u8() if self.ver >= 14 else 0
            return ("pos", x, y, t, a, b, c)
        if pt == 1:
            w, h = self.read_float(), self.read_float()
            a, b = self.u8(), self.u8()
            c = self.u8() if self.ver >= 14 else 0
            return ("size", w, h, a, b, c)
        if pt in (2, 3, 27):
            return ("pt", self.read_float(), self.read_float())
        if pt == 4:
            return ("scale", self.read_float(), self.read_float(), self.u8())
        if pt in (5, 7):
            return self.read_float()
        if pt in (6, 20):
            return self.read_int(True)
        if pt == 8:
            self.read_float(); self.read_float()
            return "other8"
        if pt == 9:
            return self.u8() != 0
        if pt in (10, 11, 19, 23, 33, 34, 36, 37, 38, 39, 41):
            return self.read_str()
        if pt == 12:
            return self.u8()
        if pt in (13, 28, 42):
            return ("rgba", self.read_float(), self.read_float(), self.read_float(), self.read_float())
        if pt == 14:
            for _ in range(8): self.read_float()
            return "other14"
        if pt == 15:
            self.u8(); self.u8()
            return "other15"
        if pt == 16:
            self.read_int(False); self.read_int(False)
            return "other16"
        if pt in (18, 24):
            return (self.read_str(), self.u8() != 0)
        if pt == 21:
            return (self.read_str(), self.read_int(False))
        if pt == 22:
            return ("spriteFrame", self.read_str(), self.read_str())
        if pt == 25:
            return (self.read_str(), self.read_int(False), self.read_int(False))
        if pt == 26:
            return (self.read_float(), self.read_int(False))
        if pt == 30:
            return (self.read_float(), self.u8() != 0)
        if pt == 31:
            return self.read_int(False)
        if pt == 40:
            return [self.read_str() for _ in range(self.read_int(False))]
        if pt == 43:
            for _ in range(self.read_int(False)): self.read_prop_val(self.read_int(False))
            return "other43"
        if pt == 44:
            for _ in range(self.read_int(False)): self.read_str(); self.read_prop_val(self.read_int(False))
            return "other44"
        return None

    def read_kf(self, pt: int):
        t = self.read_float()
        e = self.read_int(False)
        opt = self.read_float() if (e <= 19 and ((1 << e) & 0xE00FC)) else 0
        if pt == 13:
            val = ("rgba", self.read_float(), self.read_float(), self.read_float(), self.read_float())
        elif pt == 12:
            val = self.u8()
        elif pt == 9:
            val = self.u8() != 0
        elif pt in (5, 7):
            val = self.read_float()
        elif pt in (0, 1, 4, 27):
            val = (self.read_float(), self.read_float())
        elif pt in (10, 18, 38):
            val = self.read_str()
        else:
            val = None
        return (t, e, opt, val)

    def skip_channel(self, has_three: bool):
        n = self.read_int(False)
        for _ in range(n):
            _ = self.read_float()
            _ = self.read_str()
            if has_three:
                _ = self.read_float()
                _ = self.read_float()
            else:
                _ = self.read_int(False)

    def read_node(self):
        cls = self.read_str()
        base = self.read_str() if self.ver >= 12 else ""
        at = self.read_int(False)
        var_name = self.read_str() if at != 0 else ""

        nsp = self.read_int(False)
        for _ in range(nsp):
            _ = self.read_int(False)
            np = self.read_int(False)
            for _ in range(np):
                _ = self.read_str()
                pt = self.read_int(False)
                nk = self.read_int(False)
                for _ in range(nk):
                    self.read_kf(pt)

        if self.ver >= 13:
            nc = self.read_int(False)
            for _ in range(nc):
                _ = self.read_str()
                nv = self.read_int(False) if self.ver >= 22 else 1
                if self.ver >= 22:
                    for _ in range(nv):
                        _ = self.read_str()

        _ = self.read_int(False)  # uuid
        np1 = self.read_int(False)
        np2 = self.read_int(False)
        props = {}
        for _ in range(np1):
            pt = self.read_int(False)
            pn = self.read_str()
            props[pn] = self.read_prop_val(pt)
        if cls == "CCBFile" or base == "CCBFile":
            n_ov = self.read_int(False)
            for _ in range(n_ov):
                target_prop = self.read_str()
                pt = self.read_int(False)
                var_target = self.read_str()
                props[f"override:{var_target}:{target_prop}"] = self.read_prop_val(pt)
                if self.ver >= 17:
                    _ = self.u8()
        for _ in range(np2):
            pt = self.read_int(False)
            pn = self.read_str()
            props[pn] = self.read_prop_val(pt)
        if self.ver <= 17:
            _ = self.u8()

        nch = self.read_int(False)
        children = [self.read_node() for _ in range(nch)]
        return {"cls": cls, "base": base, "varName": var_name, "props": props, "children": children}

    def parse(self):
        magic = self.d[:4]
        assert magic == b"ibcc", f"Bad magic: {magic}"
        self.pos = 4
        self.ver = self.elias()
        str_count = self.read_int(False)
        self.strs = [self.read_utf8() for _ in range(str_count)]
        n_seq = self.read_int(False)
        if self.ver <= 17:
            self.pos += 2
        for _ in range(n_seq):
            _ = self.read_float()
            _ = self.read_str()
            _ = self.read_int(False)
            _ = self.read_int(True)
            self.skip_channel(False)
            self.skip_channel(True)
        _ = self.read_int(True)
        if 11 <= self.ver <= 20:
            _ = self.read_int(False)
            _ = self.read_int(False)
        if self.ver >= 15:
            c1 = self.read_int(False)
            for _ in range(c1):
                _ = self.read_str(); _ = self.read_int(False)
            c2 = self.read_int(False)
            for _ in range(c2):
                _ = self.read_int(False)
                c3 = self.read_int(False)
                for _ in range(c3):
                    pt = self.read_int(False); _ = self.read_str(); _ = self.read_prop_val(pt)
        if self.ver >= 13:
            c4 = self.read_int(False)
            for _ in range(c4):
                _ = self.read_str()
                pt = self.read_int(False)
                _ = self.read_int(False)
                _ = self.read_prop_val(pt)
                if 16 <= self.ver <= 21 and self.u8() != 0:
                    _ = self.read_str()
        return self.read_node()


class AssetLibrary:
    def __init__(self):
        self.atlases = {}
        self.frames = {}
        self.mcfs = {}
        self.strings = {}
        self.fonts = {}
        self._load()

    def _load(self):
        en_path = os.path.join(ASSETS_DIR, "en_text.json")
        if os.path.exists(en_path):
            with open(en_path, "r", encoding="utf-8") as f:
                self.strings = json.load(f)

        for fn in os.listdir(ATLAS_DIR):
            if fn.endswith(".plist"):
                plist_path = os.path.join(ATLAS_DIR, fn)
                png_path = plist_path[:-6] + ".png"
                if not os.path.exists(png_path):
                    continue
                with open(plist_path, "rb") as f:
                    pl = plistlib.load(f)
                self.atlases[fn[:-6]] = png_path
                for frame_name, meta in pl.get("frames", {}).items():
                    self.frames[frame_name] = (png_path, meta)

        for fn in os.listdir(MCFS_DIR):
            if fn.endswith(".plist"):
                with open(os.path.join(MCFS_DIR, fn), "rb") as f:
                    self.mcfs[fn] = plistlib.load(f)

    def _get_atlas_img(self, png_path: str) -> Image.Image:
        if png_path not in self.atlases:
            self.atlases[png_path] = Image.open(png_path).convert("RGBA")
        return self.atlases[png_path]

    @staticmethod
    def _parse_rect(s: str):
        nums = [float(x) for x in re.findall(r"[-+]?\d*\.?\d+", s)]
        return (int(nums[0]), int(nums[1]), int(nums[2]), int(nums[3]))

    def get_sprite(self, name: str):
        if not name:
            return None
        candidates = [name, os.path.basename(name)]
        for c in candidates:
            if c in self.frames:
                png_path, meta = self.frames[c]
                sheet = self._get_atlas_img(png_path)
                rect_str = meta.get("textureRect") or meta.get("frame")
                x, y, w, h = self._parse_rect(rect_str)
                rotated = bool(meta.get("textureRotated") or meta.get("rotated", False))
                if rotated:
                    crop = sheet.crop((x, y, x + h, y + w)).rotate(90, expand=True)
                else:
                    crop = sheet.crop((x, y, x + w, y + h))
                return crop
        # Fallback to sprites/
        for cand in [os.path.join(SPRITE_DIR, name), os.path.join(SPRITE_DIR, os.path.basename(name))]:
            if os.path.exists(cand):
                return Image.open(cand).convert("RGBA")
        return None

    def get_font(self, font_name: str, px_size: int):
        key = (font_name, px_size)
        if key in self.fonts:
            return self.fonts[key]
        low = (font_name or "").lower()
        ttf = "Ubuntu-Bold.ttf"
        if "lato" in low:
            ttf = "lato-heavy.ttf" if "heavy" in low else "Lato-Regular.ttf"
        elif "opensans" in low:
            ttf = "OpenSans-SemiboldItalic.ttf" if "italic" in low else "OpenSans-Bold.ttf"
        elif "medium" in low:
            ttf = "Ubuntu-Medium.ttf"
        elif "semibold" in low:
            ttf = "Ubuntu-Semibold.ttf"
        path = os.path.join(FONTS_DIR, ttf)
        if not os.path.exists(path):
            path = os.path.join(FONTS_DIR, "Ubuntu-Bold.ttf")
        font = ImageFont.truetype(path, max(8, px_size))
        self.fonts[key] = font
        return font


def ui_scale_for(w: float, h: float, is_ipad: bool) -> float:
    if is_ipad:
        return max(0.5, w / 768.0)
    return max(0.5, min(h / 320.0, w / 480.0))


def resource_scale_for(is_ipad: bool) -> float:
    return 1.0 if is_ipad else 0.46875


def eval_dim(val: float, unit: int, parent: float, ui_scale: float) -> float:
    if unit == 0:   # points
        return val * ui_scale
    if unit == 1:   # UIPoints
        return val * ui_scale
    if unit == 2:   # normalized (0..1)
        return val * parent
    return val * ui_scale


def render_ccbi(ccbi_name: str, w_pt: float, h_pt: float, is_ipad: bool, lib: AssetLibrary, out_scale: float = 2.0):
    path = os.path.join(CCBI_DIR, ccbi_name if ccbi_name.endswith(".ccbi") else ccbi_name + ".ccbi")
    with open(path, "rb") as f:
        root = CCBIReader(f.read()).parse()

    s = ui_scale_for(w_pt, h_pt, is_ipad)
    rs = resource_scale_for(is_ipad)
    canvas = Image.new("RGBA", (int(round(w_pt * out_scale)), int(round(h_pt * out_scale))), (0, 0, 0, 0))
    manifest_nodes = []

    def draw_node(node, parent_rect_pt):
        px, py, pw, ph = parent_rect_pt
        props = node["props"]
        if props.get("visible", True) is False:
            return

        cls = node["cls"]
        base = node["base"]

        # Content size
        cs_prop = props.get("contentSize")
        if cs_prop and cs_prop[0] == "size":
            nw = eval_dim(cs_prop[1], cs_prop[3], pw, s)
            nh = eval_dim(cs_prop[2], cs_prop[4], ph, s)
        elif cls in ("CCSprite", "MCFramedSprite") or base in ("CCSprite", "MCFramedSprite"):
            sf = props.get("spriteFrame")
            spr_name = sf[2] if (isinstance(sf, tuple) and sf[0] == "spriteFrame") else ""
            img = lib.get_sprite(spr_name)
            if img is not None:
                nw = img.width * 0.5 * rs * s
                nh = img.height * 0.5 * rs * s
            else:
                nw, nh = 0.0, 0.0
        else:
            nw, nh = pw, ph

        # Scale
        sc_prop = props.get("scale")
        sx, sy = (sc_prop[1], sc_prop[2]) if (isinstance(sc_prop, tuple) and sc_prop[0] == "scale") else (1.0, 1.0)
        nw_s, nh_s = nw * abs(sx), nh * abs(sy)

        # Position (Cocos2d bottom-left origin -> UIKit top-left origin)
        pos_prop = props.get("position")
        if isinstance(pos_prop, tuple) and pos_prop[0] == "pos":
            rx, ry, ref_corner, xu, yu, _ = pos_prop[1:]
            dx = eval_dim(rx, xu, pw, s)
            dy = eval_dim(ry, yu, ph, s)
            if ref_corner == 0:   # bottom-left
                cx, cy_cc = dx, dy
            elif ref_corner == 1: # top-left
                cx, cy_cc = dx, ph - dy
            elif ref_corner == 2: # top-right
                cx, cy_cc = pw - dx, ph - dy
            else:                 # bottom-right
                cx, cy_cc = pw - dx, dy
        else:
            cx, cy_cc = 0.0, 0.0

        # Anchor point
        ap_prop = props.get("anchorPoint")
        ax, ay = (ap_prop[1], ap_prop[2]) if (isinstance(ap_prop, tuple) and ap_prop[0] == "pt") else (0.5, 0.5)
        if props.get("ignoreAnchorPointForPosition", False):
            ax, ay = 0.0, 0.0

        left_pt = px + cx - ax * nw_s
        bottom_cc = cy_cc - ay * nh_s
        top_pt = py + (ph - (bottom_cc + nh_s))

        if nw_s > 0.5 and nh_s > 0.5:
            manifest_nodes.append({
                "cls": cls,
                "varName": node["varName"],
                "x": round(left_pt, 2),
                "y": round(top_pt, 2),
                "w": round(nw_s, 2),
                "h": round(nh_s, 2),
            })

        # Render visual
        opacity = float(props.get("opacity", 255)) / 255.0
        if cls == "CCLayerColor" or base == "CCLayerColor":
            col = props.get("color")
            if isinstance(col, tuple) and col[0] == "rgba":
                rgba = (int(col[1] * 255), int(col[2] * 255), int(col[3] * 255), int(col[4] * 255 * opacity))
                box = Image.new("RGBA", (max(1, int(round(nw_s * out_scale))), max(1, int(round(nh_s * out_scale)))), rgba)
                canvas.alpha_composite(box, (int(round(left_pt * out_scale)), int(round(top_pt * out_scale))))
        elif cls in ("CCSprite", "MCFramedSprite", "CCScale9Sprite") or base in ("CCSprite", "MCFramedSprite", "CCScale9Sprite"):
            sf = props.get("spriteFrame")
            spr_name = sf[2] if (isinstance(sf, tuple) and sf[0] == "spriteFrame") else ""
            img = lib.get_sprite(spr_name)
            if img is not None and nw_s > 1 and nh_s > 1:
                resized = img.resize((max(1, int(round(nw_s * out_scale))), max(1, int(round(nh_s * out_scale)))), Image.Resampling.LANCZOS)
                if opacity < 0.99:
                    r, g, b, a = resized.split()
                    a = a.point(lambda p: int(p * opacity))
                    resized = Image.merge("RGBA", (r, g, b, a))
                canvas.alpha_composite(resized, (int(round(left_pt * out_scale)), int(round(top_pt * out_scale))))
        elif cls in ("CCLabelTTF", "MCLabelTTF") or base in ("CCLabelTTF", "MCLabelTTF"):
            txt = props.get("string", "")
            if isinstance(txt, tuple):
                txt = txt[0]
            if txt in lib.strings:
                txt = lib.strings[txt]
            fsize_prop = props.get("fontSize")
            fsize = fsize_prop[0] if isinstance(fsize_prop, tuple) else float(fsize_prop or 14.0)
            fname = props.get("fontName", "Ubuntu-Bold")
            font = lib.get_font(fname, int(round(fsize * s * out_scale)))
            draw = ImageDraw.Draw(canvas)
            tx = int(round((left_pt + nw_s * 0.5) * out_scale))
            ty = int(round((top_pt + nh_s * 0.5) * out_scale))
            draw.text((tx, ty), str(txt), font=font, fill=(255, 255, 255, int(255 * opacity)), anchor="mm")

        for ch in node["children"]:
            draw_node(ch, (left_pt, top_pt, nw_s, nh_s))

    draw_node(root, (0.0, 0.0, w_pt, h_pt))
    return canvas, manifest_nodes


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    lib = AssetLibrary()
    targets = [
        "MenuMain", "MenuSettings", "MenuShopSkins", "PotionSlot",
        "Controls-Sides", "Score", "EmojiWidget", "PauseButton",
        "LeaderboardWidget", "MenuBattleResultPopup"
    ]
    manifest = {"iPhone": {}, "iPad": {}}
    for name in targets:
        for dev, (w, h, is_ipad) in [("iPhone", (852.0, 393.0, False)), ("iPad", (1024.0, 768.0, True))]:
            img, nodes = render_ccbi(name, w, h, is_ipad, lib)
            out_png = os.path.join(OUT_DIR, f"{dev}_{name}.png")
            img.save(out_png)
            manifest[dev][name] = nodes
    manifest_path = os.path.join(REPO_ROOT, "Tests", "AgarParityTests", "Fixtures", "ccbi_node_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"Rendered {len(targets)*2} CCBI reference PNGs to {OUT_DIR} and wrote {manifest_path}")


if __name__ == "__main__":
    main()
