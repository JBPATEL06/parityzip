#!/usr/bin/env python3
"""
Generate Freedesktop hicolor icon theme hierarchy for ParityZip.
"""
import os
import shutil
from PIL import Image

SIZES = [16, 32, 48, 64, 128, 256, 512]
APP_ID = "io.github.jbpatel06.parityzip"

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    source_png = os.path.join(root, "assets", "app_icon.png")
    source_svg = os.path.join(root, "packaging", "parityzip.svg")
    icons_root = os.path.join(root, "packaging", "icons", "hicolor")

    if not os.path.exists(source_png):
        print(f"Error: {source_png} not found.")
        return 1

    img = Image.open(source_png).convert("RGBA")

    for size in SIZES:
        size_dir = os.path.join(icons_root, f"{size}x{size}", "apps")
        os.makedirs(size_dir, exist_ok=True)
        dest_path = os.path.join(size_dir, f"{APP_ID}.png")
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(dest_path, "PNG", optimize=True)
        print(f"Generated: {dest_path}")

    # Scalable SVG
    if os.path.exists(source_svg):
        scalable_dir = os.path.join(icons_root, "scalable", "apps")
        os.makedirs(scalable_dir, exist_ok=True)
        dest_svg = os.path.join(scalable_dir, f"{APP_ID}.svg")
        shutil.copyfile(source_svg, dest_svg)
        print(f"Copied: {dest_svg}")

    # Standard 256x256 fallback in packaging/
    p256 = os.path.join(root, "packaging", "parityzip.png")
    img.resize((256, 256), Image.Resampling.LANCZOS).save(p256, "PNG", optimize=True)
    print(f"Generated: {p256}")

    print("Icon hierarchy generation complete.")
    return 0

if __name__ == "__main__":
    exit(main())
