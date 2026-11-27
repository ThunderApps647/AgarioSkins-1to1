#!/usr/bin/env python3
"""
Automated SSIM + Pixel-Diff Heatmap Auditor.
Compares downloaded Simulator screenshots (iPhone_* / iPad_*) against
Python-rendered CCBI reference PNGs and outputs diff_heatmap.png per screen.
"""
import argparse
import glob
import os
import sys
import numpy as np
from PIL import Image


def compute_ssim(img1: np.ndarray, img2: np.ndarray) -> float:
    # 8x8 block-windowed luminance SSIM
    c1 = (0.01 * 255.0) ** 2
    c2 = (0.03 * 255.0) ** 2
    x = img1.astype(np.float64)
    y = img2.astype(np.float64)
    if x.ndim == 3:
        x = 0.299 * x[..., 0] + 0.587 * x[..., 1] + 0.114 * x[..., 2]
        y = 0.299 * y[..., 0] + 0.587 * y[..., 1] + 0.114 * y[..., 2]
    H, W = x.shape
    bh, bw = (H // 8) * 8, (W // 8) * 8
    xb = x[:bh, :bw].reshape(bh // 8, 8, bw // 8, 8).transpose(0, 2, 1, 3).reshape(-1, 64)
    yb = y[:bh, :bw].reshape(bh // 8, 8, bw // 8, 8).transpose(0, 2, 1, 3).reshape(-1, 64)
    mu_x = xb.mean(axis=1)
    mu_y = yb.mean(axis=1)
    sig_x = xb.var(axis=1)
    sig_y = yb.var(axis=1)
    sig_xy = ((xb - mu_x[:, None]) * (yb - mu_y[:, None])).mean(axis=1)
    num = (2.0 * mu_x * mu_y + c1) * (2.0 * sig_xy + c2)
    den = (mu_x ** 2 + mu_y ** 2 + c1) * (sig_x + sig_y + c2)
    return float(np.mean(num / np.maximum(den, 1e-12)))


def audit_pair(sim_path: str, ref_path: str, out_heatmap: str, ssim_threshold: float = 0.70):
    sim = Image.open(sim_path).convert("RGB")
    ref = Image.open(ref_path).convert("RGBA")
    # Composite ref over white background if transparent
    bg = Image.new("RGBA", ref.size, (255, 255, 255, 255))
    ref_rgb = Image.alpha_composite(bg, ref).convert("RGB")
    if sim.size != ref_rgb.size:
        sim = sim.resize(ref_rgb.size, Image.Resampling.BILINEAR)

    a = np.asarray(sim, dtype=np.float32)
    b = np.asarray(ref_rgb, dtype=np.float32)
    diff = np.abs(a - b).mean(axis=2)  # 0..255 per pixel
    ssim = compute_ssim(a, b)
    mae = float(diff.mean())

    # Build red-yellow heatmap overlay
    heat = np.zeros((diff.shape[0], diff.shape[1], 3), dtype=np.uint8)
    norm = np.clip(diff / 64.0, 0.0, 1.0)
    heat[..., 0] = (norm * 255).astype(np.uint8)
    heat[..., 1] = (np.clip(1.0 - np.abs(norm - 0.5) * 2.0, 0.0, 1.0) * 200).astype(np.uint8)
    heat[..., 2] = ((1.0 - norm) * 60).astype(np.uint8)
    Image.fromarray(heat).save(out_heatmap)
    return ssim, mae


def build_sim_index(sim_dir: str) -> dict:
    index = {}
    for p in glob.glob(os.path.join(sim_dir, "**", "*.png"), recursive=True):
        index[os.path.basename(p)] = p
    for mf in glob.glob(os.path.join(sim_dir, "**", "manifest.json"), recursive=True):
        import json
        mf_dir = os.path.dirname(mf)
        with open(mf, "r", encoding="utf-8") as f:
            entries = json.load(f)
        for entry in entries:
            for att in entry.get("attachments", []):
                hr = att.get("suggestedHumanReadableName", "")
                exp = att.get("exportedFileName", "")
                exp_path = os.path.join(mf_dir, exp)
                if exp and os.path.exists(exp_path) and hr:
                    for key in ("iPhone_Live_01_MainMenu", "iPhone_Live_02_Settings", "iPhone_Live_03_Skins", "iPhone_Live_02b_Potions",
                                "iPad_Live_01_MainMenu", "iPad_Live_02_Settings", "iPad_Live_03_Skins", "iPad_Live_02b_Potions",
                                "01_MenuMain", "02_Settings", "03_Skins"):
                        if hr.startswith(key):
                            index[key + ".png"] = exp_path
    return index


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim-dir", required=True, help="Directory with Simulator PNGs")
    ap.add_argument("--ref-dir", default="Tests/AgarParityTests/Fixtures/ccbi_ref")
    ap.add_argument("--out-dir", default="build/diff_heatmaps")
    ap.add_argument("--min-ssim", type=float, default=0.70)
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    sim_index = build_sim_index(args.sim_dir)
    mapping = [
        ("iPhone_Live_01_MainMenu.png", "iPhone_MenuMain.png"),
        ("iPhone_Live_02_Settings.png", "iPhone_MenuSettings.png"),
        ("iPhone_Live_03_Skins.png", "iPhone_MenuShopSkins.png"),
        ("iPhone_Live_02b_Potions.png", "iPhone_PotionSlot.png"),
        ("iPad_Live_01_MainMenu.png", "iPad_MenuMain.png"),
        ("iPad_Live_02_Settings.png", "iPad_MenuSettings.png"),
        ("iPad_Live_03_Skins.png", "iPad_MenuShopSkins.png"),
        ("iPad_Live_02b_Potions.png", "iPad_PotionSlot.png"),
    ]

    failures = []
    checked = 0
    for sim_name, ref_name in mapping:
        sim_path = sim_index.get(sim_name)
        ref_path = os.path.join(args.ref_dir, ref_name)
        if not sim_path or not os.path.exists(ref_path):
            continue
        heat_path = os.path.join(args.out_dir, f"{sim_name[:-4]}_diff_heatmap.png")
        ssim, mae = audit_pair(sim_path, ref_path, heat_path, args.min_ssim)
        checked += 1
        status = "PASS" if ssim >= args.min_ssim else "FAIL"
        print(f"[{status}] {sim_name} vs {ref_name}: SSIM={ssim:.4f} MAE={mae:.2f} -> {heat_path}")
        if ssim < args.min_ssim:
            failures.append((sim_name, ssim, mae))

    print(f"Audited {checked} screenshot pairs, {len(failures)} below SSIM {args.min_ssim}.")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
