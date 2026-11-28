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
                raw_en = json.load(f)
                texts = raw_en.get("texts", raw_en) if isinstance(raw_en, dict) else raw_en
                if isinstance(texts, list):
                    self.strings = {e["k"]: e["v"] for e in texts if isinstance(e, dict) and "k" in e and "v" in e}
                elif isinstance(texts, dict):
                    self.strings = texts

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
        # Also strip GeneratedAssets/... prefix if present
        if "GeneratedAssets/" in name:
            candidates.append(name.split("/")[-1])
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

    def get_mcfs_image(self, desc_name: str):
        if not desc_name:
            return None
        key = os.path.basename(desc_name)
        if not key.endswith(".plist"):
            key += ".plist"
        pl = self.mcfs.get(key)
        if not pl:
            return None
        img_name = pl.get("Source_Frame") or pl.get("spriteFrame") or pl.get("texture") or pl.get("image") or ""
        return self.get_sprite(img_name)

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
    return max(0.5, min(h / 320.0, w / 480.0))


def resource_scale_for(is_ipad: bool) -> float:
    return 1.0 if is_ipad else 0.46875


def eval_dim(val: float, unit: int, parent: float) -> float:
    if unit == 2:   # normalized (0..1)
        return val * parent
    if unit == 3:
        return max(0.0, parent - val)
    return val


# Controller state captured from the live CCBISceneView bindings.  The raw .ccbi
# contains every legacy/A-B layer; the controllers only show the active variant.
VISIBILITY_OVERRIDES = {
    "MenuMain": {
        "_background": False, "_promoMenu": False, "_featureMenu": False,
        "_matchStatsView": False, "_classicMatchStats": True, "_rushMatchStats": False,
        "_googleFbMenuItemStatic": False, "_twitterMenuItemStatic": False,
        "_playerReportButton": False, "_adventureEntryPoint": False,
        "_seasonEntryPoint": False, "_vipSubscriptionButton": False,
        "_extraButtonsLayer": False, "_speechButtonsLayer": False,
        "_shopRedBadge": False, "_newsfeedBadge": False, "_giftCenterBadge": False,
        "_xpAnim": False, "_timeFrame": False, "_timeLabel": False,
        "_top2xSprite": False, "_top3xSprite": False, "_bottom2xSprite": False,
        "_bottom3xSprite": False, "_activeBackgroundSprite": False,
        "_inventoryBackgroundSprite": False, "_inventoryLabel": False,
        "_freeCoinsButtonNode._badgeNode": False, "_leaguesButton._badgeNode": False,
        "_dailyQuestButtonNode._badgeNode": False, "_topSlot5": False, "_topSlot6": False,
        "_playButtonsScrollNode": False,
        # Bound slot views replace these CCBI placeholders at runtime.
        "_inputBox": False, "_rewardSprite": False, "_buttonIcon": False,
    },
    "MenuSettings": {"_menuHelp": False, "_scrollbarNode": False},
    "MenuShopSkins": {"_scrollbarNode": False, "_tabsNode": False, "_tableNode": False},
}
_ACTIVE_HIDDEN = {}


def render_ccbi(ccbi_name: str, w_pt: float, h_pt: float, is_ipad: bool, lib: AssetLibrary, out_scale: float = 2.0):
    path = os.path.join(CCBI_DIR, ccbi_name if ccbi_name.endswith(".ccbi") else ccbi_name + ".ccbi")
    with open(path, "rb") as f:
        root = CCBIReader(f.read()).parse()

    s = ui_scale_for(w_pt, h_pt, is_ipad)
    rs = resource_scale_for(is_ipad)
    dw, dh = w_pt / s, h_pt / s
    px_scale = s * out_scale
    canvas = Image.new("RGBA", (int(round(w_pt * out_scale)), int(round(h_pt * out_scale))), (0, 0, 0, 0))
    manifest_nodes = []

    def draw_node(node, parent_rect_dp):
        px, py, pw, ph = parent_rect_dp
        props = node["props"]
        if props.get("visible", True) is False:
            return
        if node["varName"] in _ACTIVE_HIDDEN and not _ACTIVE_HIDDEN[node["varName"]]:
            return

        cls = node["cls"]
        base = node["base"]

        # Content size in design points
        def _extract_sf(p):
            sf = p.get("spriteFrame") or p.get("displayFrame") or p.get("normalSpriteFrame")
            if isinstance(sf, tuple) and sf[0] == "spriteFrame":
                return sf[2]
            if isinstance(sf, str):
                return sf
            return ""

        cs_prop = props.get("contentSize")
        if cs_prop and cs_prop[0] == "size":
            nw = eval_dim(cs_prop[1], cs_prop[3], pw)
            nh = eval_dim(cs_prop[2], cs_prop[4], ph)
        elif cls in ("CCSprite", "MCFramedSprite") or base in ("CCSprite", "MCFramedSprite"):
            spr_name = _extract_sf(props)
            if node["varName"] == "_background" and "background" in spr_name.lower():
                nw, nh = dw, dh
            else:
                img = lib.get_sprite(spr_name) or lib.get_mcfs_image(props.get("descriptionName", ""))
                if img is not None:
                    nw = img.width * 0.5 * rs
                    nh = img.height * 0.5 * rs
                else:
                    nw, nh = 0.0, 0.0
        else:
            nw, nh = pw, ph

        # Scale
        sc_prop = props.get("scale")
        sx, sy = (sc_prop[1], sc_prop[2]) if (isinstance(sc_prop, tuple) and sc_prop[0] == "scale") else (1.0, 1.0)
        nw_s, nh_s = nw * abs(sx), nh * abs(sy)

        # Position (matching CCBIRuntime.resolvePosition in design points, top-left origin)
        pos_prop = props.get("position")
        if isinstance(pos_prop, tuple) and pos_prop[0] == "pos":
            rx, ry, ref_corner, xu, yu, _ = pos_prop[1:]
            dx = eval_dim(rx, xu, pw)
            dy = eval_dim(ry, yu, ph)
            if ref_corner == 0:   # bottom-left
                cx, cy_top = dx, ph - dy
            elif ref_corner == 1: # top-left
                cx, cy_top = dx, dy
            elif ref_corner == 2: # top-right
                cx, cy_top = pw - dx, dy
            else:                 # bottom-right
                cx, cy_top = pw - dx, ph - dy
        else:
            cx, cy_top = 0.0, ph

        # Anchor point (mirrors CCBIRuntime.effectiveAnchorPoint / resolveAnchorPoint):
        # layers and generic nodes are bottom-left anchored, sprites/labels/menus are centered,
        # and ignoreAnchorPointForPosition always wins.
        ap_prop = props.get("anchorPoint")
        ax, ay = (ap_prop[1], ap_prop[2]) if (isinstance(ap_prop, tuple) and ap_prop[0] == "pt") else (None, None)
        if props.get("ignoreAnchorPointForPosition", False):
            ax, ay = 0.0, 0.0
        elif ax is None:
            if cls in ("CCLayer", "CCNodeColor", "CCLayerColor") or base in ("CCLayer", "CCNodeColor", "CCLayerColor"):
                ax, ay = 0.0, 0.0
            elif (cls in ("CCSprite", "MCAutoScalableSprite", "MCFramedSprite", "MCLabelTTF", "CCLabelTTF",
                          "CCHybridMenu", "CCMenu", "MCAlignmentNode", "MCAlignmentNodeStatic", "MCSpineNode")
                  or base in ("CCSprite", "MCAutoScalableSprite", "MCFramedSprite", "MCLabelTTF", "CCLabelTTF",
                              "CCHybridMenu", "CCMenu", "MCAlignmentNode", "MCAlignmentNodeStatic", "MCSpineNode")
                  or "MenuItem" in cls or "MenuItem" in base):
                ax, ay = 0.5, 0.5
            else:
                ax, ay = 0.0, 0.0

        left_dp = px + cx - ax * nw_s
        top_dp = py + cy_top - (1.0 - ay) * nh_s

        if nw_s > 0.5 and nh_s > 0.5:
            manifest_nodes.append({
                "cls": cls,
                "varName": node["varName"],
                "x": round(left_dp * s, 2),
                "y": round(top_dp * s, 2),
                "w": round(nw_s * s, 2),
                "h": round(nh_s * s, 2),
            })

        # Render visual
        raw_op = props.get("opacity", 1.0)
        opacity = float(raw_op) / 255.0 if float(raw_op) > 1.0 else float(raw_op)
        if cls == "CCBFile" or base == "CCBFile":
            sub_file = props.get("ccbFile", "")
            if isinstance(sub_file, str) and sub_file:
                bn = os.path.basename(sub_file)
                if bn.endswith(".ccb"):
                    bn = bn[:-4] + ".ccbi"
                elif not bn.endswith(".ccbi"):
                    bn += ".ccbi"
                sub_path = os.path.join(CCBI_DIR, bn)
                if os.path.exists(sub_path):
                    with open(sub_path, "rb") as sf_f:
                        sub_root = CCBIReader(sf_f.read()).parse()
                    draw_node(sub_root, (left_dp, top_dp, max(1.0, nw_s if nw_s > 0.5 else pw), max(1.0, nh_s if nh_s > 0.5 else ph)))
        elif cls in ("CCLayerColor", "CCNodeColor") or base in ("CCLayerColor", "CCNodeColor"):
            col = props.get("color")
            if isinstance(col, tuple) and col[0] == "rgba":
                rgba = (int(col[1] * 255), int(col[2] * 255), int(col[3] * 255), int(col[4] * 255 * opacity))
                box = Image.new("RGBA", (max(1, int(round(nw_s * px_scale))), max(1, int(round(nh_s * px_scale)))), rgba)
                canvas.alpha_composite(box, (int(round(left_dp * px_scale)), int(round(top_dp * px_scale))))
        elif cls in ("CCSprite", "MCFramedSprite", "CCScale9Sprite") or base in ("CCSprite", "MCFramedSprite", "CCScale9Sprite"):
            spr_name = _extract_sf(props)
            if node["varName"] == "_background" and "background" in spr_name.lower():
                aspect = dw / max(1.0, dh)
                if aspect <= 1.48:
                    spr_name = "background-ipadpro.png"
                elif aspect >= 1.95:
                    spr_name = "backgroundSuperWide.png"
                elif aspect >= 1.65:
                    spr_name = "backgroundWide.png"
            img = lib.get_sprite(spr_name) or lib.get_mcfs_image(props.get("descriptionName", ""))
            if img is not None and nw_s > 1 and nh_s > 1:
                tw, th = max(1, int(round(nw_s * px_scale))), max(1, int(round(nh_s * px_scale)))
                if node["varName"] == "_background" and "background" in spr_name.lower():
                    # Aspect-fill (scaledToFill) matching MenuMain SwiftUI background
                    scale_fill = max(tw / img.width, th / img.height)
                    fw, fh = max(tw, int(round(img.width * scale_fill))), max(th, int(round(img.height * scale_fill)))
                    scaled = img.resize((fw, fh), Image.Resampling.LANCZOS)
                    cx_off = (fw - tw) // 2
                    cy_off = (fh - th) // 2
                    resized = scaled.crop((cx_off, cy_off, cx_off + tw, cy_off + th))
                else:
                    resized = img.resize((tw, th), Image.Resampling.LANCZOS)
                col = props.get("color")
                if isinstance(col, tuple) and col[0] == "rgba" and (col[1] < 0.99 or col[2] < 0.99 or col[3] < 0.99):
                    r, g, b, a = resized.split()
                    r = r.point(lambda p: int(p * col[1]))
                    g = g.point(lambda p: int(p * col[2]))
                    b = b.point(lambda p: int(p * col[3]))
                    resized = Image.merge("RGBA", (r, g, b, a))
                if opacity < 0.99:
                    r, g, b, a = resized.split()
                    a = a.point(lambda p: int(p * opacity))
                    resized = Image.merge("RGBA", (r, g, b, a))
                canvas.alpha_composite(resized, (int(round(left_dp * px_scale)), int(round(top_dp * px_scale))))
        elif cls in ("CCLabelTTF", "MCLabelTTF") or base in ("CCLabelTTF", "MCLabelTTF"):
            txt = props.get("string", "")
            if isinstance(txt, tuple):
                txt = txt[0]
            if txt in lib.strings:
                txt = lib.strings[txt]
            fsize_prop = props.get("fontSize")
            fsize = fsize_prop[0] if isinstance(fsize_prop, tuple) else float(fsize_prop or 14.0)
            fname = props.get("fontName", "Ubuntu-Bold")
            font = lib.get_font(fname, int(round(fsize * px_scale)))
            draw = ImageDraw.Draw(canvas)
            tx = int(round((left_dp + nw_s * 0.5) * px_scale))
            ty = int(round((top_dp + nh_s * 0.5) * px_scale))
            lcol = props.get("fontColor") or props.get("color")
            if isinstance(lcol, tuple) and lcol[0] == "rgba":
                fill_rgba = (int(lcol[1] * 255), int(lcol[2] * 255), int(lcol[3] * 255), int(255 * opacity))
            else:
                fill_rgba = (255, 255, 255, int(255 * opacity))
            draw.text((tx, ty), str(txt), font=font, fill=fill_rgba, anchor="mm")

        child_w = nw_s if nw_s > 0.5 else pw
        child_h = nh_s if nh_s > 0.5 else ph
        for ch in node["children"]:
            draw_node(ch, (left_dp, top_dp, child_w, child_h))

    # Center modal roots (contentSize < viewport) to match CCBISceneView(centerRoot: true)
    cs_root = root["props"].get("contentSize")
    origin_x, origin_y = 0.0, 0.0
    if cs_root and cs_root[0] == "size" and cs_root[3] != 2 and cs_root[4] != 2:
        rw = eval_dim(cs_root[1], cs_root[3], dw)
        rh = eval_dim(cs_root[2], cs_root[4], dh)
        if 10.0 < rw < dw and 10.0 < rh < dh:
            origin_x = (dw - rw) * 0.5
            origin_y = (dh - rh) * 0.5

    global _ACTIVE_HIDDEN
    _ACTIVE_HIDDEN = VISIBILITY_OVERRIDES.get(ccbi_name, {})
    if "_background" in _ACTIVE_HIDDEN and not _ACTIVE_HIDDEN["_background"]:
        aspect = dw / max(1.0, dh)
        if aspect <= 1.48:
            bg_name = "background-ipadpro.png"
        elif aspect >= 1.95:
            bg_name = "backgroundSuperWide.png"
        elif aspect >= 1.65:
            bg_name = "backgroundWide.png"
        else:
            bg_name = "background.png"
        bg = lib.get_sprite(bg_name)
        if bg is not None:
            cw, ch = canvas.size
            fill = max(cw / bg.width, ch / bg.height)
            fw, fh = max(cw, int(round(bg.width * fill))), max(ch, int(round(bg.height * fill)))
            scaled = bg.resize((fw, fh), Image.Resampling.LANCZOS)
            canvas.alpha_composite(scaled.crop(((fw - cw) // 2, (fh - ch) // 2, (fw - cw) // 2 + cw, (fh - ch) // 2 + ch)), (0, 0))
    draw_node(root, (origin_x, origin_y, dw, dh))

    # Composite dynamic slot CCBIs that C++ controllers instantiate at runtime
    if ccbi_name == "MenuMain":
        # ClassicButton.ccbi at _staticPlayButtonsContainer left slot + Play Online green button
        cb_path = os.path.join(CCBI_DIR, "ClassicButton.ccbi")
        if os.path.exists(cb_path):
            with open(cb_path, "rb") as f:
                cb_root = CCBIReader(f.read()).parse()
            draw_node(cb_root, (dw * 0.5 - 126.0, dh * 0.5 - 10.0, 120.0, 80.0))
        gr_img = lib.get_mcfs_image("MCFS_green.plist")
        if gr_img is not None:
            bw, bh = int(round(120.0 * px_scale)), int(round(80.0 * px_scale))
            bx, by = int(round((dw * 0.5 + 6.0) * px_scale)), int(round((dh * 0.5 - 10.0) * px_scale))
            canvas.alpha_composite(gr_img.resize((bw, bh), Image.Resampling.LANCZOS), (bx, by))
    elif ccbi_name == "MenuMysteryPotions":
        ps_path = os.path.join(CCBI_DIR, "PotionSlot.ccbi")
        if os.path.exists(ps_path):
            with open(ps_path, "rb") as f:
                ps_root = CCBIReader(f.read()).parse()
            slot_w = (dw - 40.0) / 3.0
            for idx in range(3):
                draw_node(ps_root, (12.0 + idx * (slot_w + 8.0), 74.0, slot_w, 195.0))

    return canvas, manifest_nodes


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    lib = AssetLibrary()
    targets = [
        "MenuMain", "MenuSettings", "MenuShopSkins", "MenuMysteryPotions", "PotionSlot",
        "Controls-Sides", "Score", "EmojiWidget", "PauseButton",
        "LeaderboardWidget", "MenuPause", "ContinueGame", "MenuBattleResultPopup"
    ]
    manifest = {"iPhone": {}, "iPad": {}}
    bg_cache = {}
    for name in targets:
        for dev, (w, h, is_ipad, sc) in [("iPhone", (874.0, 402.0, False, 3.0)), ("iPad", (1376.0, 1032.0, True, 2.0))]:
            img, nodes = render_ccbi(name, w, h, is_ipad, lib, out_scale=sc)
            if name == "MenuMain":
                bg_cache[dev] = img
            elif name in ("MenuPause", "ContinueGame", "MenuBattleResultPopup") and dev in bg_cache:
                # Match SwiftUI modal backdrop: MenuMain underneath + Color.black.opacity(0.55)
                base = bg_cache[dev].copy()
                dim = Image.new("RGBA", base.size, (0, 0, 0, int(255 * 0.55)))
                base.alpha_composite(dim)
                base.alpha_composite(img)
                img = base
            out_png = os.path.join(OUT_DIR, f"{dev}_{name}.png")
            img.save(out_png)
            manifest[dev][name] = nodes
    manifest_path = os.path.join(REPO_ROOT, "Tests", "AgarParityTests", "Fixtures", "ccbi_node_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"Rendered {len(targets)*2} CCBI reference PNGs to {OUT_DIR} and wrote {manifest_path}")


if __name__ == "__main__":
    main()
