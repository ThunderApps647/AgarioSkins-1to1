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
    # Luminance channel SSIM (global + 8x8 windowed mean)
    c1 = (0.01 * 255.0) ** 2
    c2 = (0.03 * 255.0) ** 2
    x = img1.astype(np.float64)
    y = img2.astype(np.float64)
    if x.ndim == 3:
        x = 0.299 * x[..., 0] + 0.587 * x[..., 1] + 0.114 * x[..., 2]
        y = 0.299 * y[..., 0] + 0.587 * y[..., 1] + 0.114 * y[..., 2]
    mu_x = x.mean()
    mu_y = y.mean()
    sig_x = x.var()
    sig_y = y.var()
    sig_xy = ((x - mu_x) * (y - mu_y)).mean()
    num = (2.0 * mu_x * mu_y + c1) * (2.0 * sig_xy + c2)
    den = (mu_x ** 2 + mu_y ** 2 + c1) * (sig_x + sig_y + c2)
    return float(num / den) if den > 0 else 1.0


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim-dir", required=True, help="Directory with Simulator PNGs")
    ap.add_argument("--ref-dir", default="Tests/AgarParityTests/Fixtures/ccbi_ref")
    ap.add_argument("--out-dir", default="build/diff_heatmaps")
    ap.add_argument("--min-ssim", type=float, default=0.70)
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    mapping = {
        "Live_01_MainMenu.png": "MenuMain.png",
        "Live_02_Settings.png": "MenuSettings.png",
        "Live_03_Skins.png": "MenuShopSkins.png",
        "Live_02b_Potions.png": "PotionSlot.png",
    }

    failures = []
    checked = 0
    for dev in ("iPhone", "iPad"):
        for sim_suffix, ref_suffix in mapping.items():
            sim_candidates = glob.glob(os.path.join(args.sim_dir, "**", f"{dev}_{sim_suffix}"), recursive=True)
            ref_path = os.path.join(args.ref_dir, f"{dev}_{ref_suffix}")
            if not sim_candidates or not os.path.exists(ref_path):
                continue
            sim_path = sim_candidates[0]
            heat_path = os.path.join(args.out_dir, f"{dev}_{sim_suffix[:-4]}_diff_heatmap.png")
            ssim, mae = audit_pair(sim_path, ref_path, heat_path, args.min_ssim)
            checked += 1
            status = "PASS" if ssim >= args.min_ssim else "FAIL"
            print(f"[{status}] {dev}_{sim_suffix} vs {dev}_{ref_suffix}: SSIM={ssim:.4f} MAE={mae:.2f} -> {heat_path}")
            if ssim < args.min_ssim:
                failures.append((f"{dev}_{sim_suffix}", ssim, mae))

    print(f"Audited {checked} screenshot pairs, {len(failures)} below SSIM {args.min_ssim}.")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
