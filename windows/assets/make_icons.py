#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render the whale SVG into tray PNGs and a multi-size ICO (Windows launcher)."""
import io
import os
import re
import subprocess
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent
SVG = (ROOT / "whale.svg").read_text(encoding="utf-8")
PATH_MATCH = re.search(r'<path[^>]*d="([^"]+)"', SVG)
assert PATH_MATCH, "whale path not found in SVG"
PATH_D = PATH_MATCH.group(1)

EDGE_CANDIDATES = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]
EDGE = next((p for p in EDGE_CANDIDATES if Path(p).exists()), None)
if not EDGE:
    print("Edge not found; cannot rasterize SVG")
    sys.exit(1)


def html_for(fill: str, stroke: str | None = None, size: int = 256) -> str:
    # 使用紧贴鲸鱼实际绘制区域的 viewBox，去掉四周留白，让鲸鱼铺满图标宽度
    tight = "0.63 6.63 49.04 37.03"
    stroke_attr = f' stroke="{stroke}" stroke-width="1.0" stroke-linejoin="round"' if stroke else ""
    return f"""<!doctype html>
<html><head><meta charset="utf-8"></head>
<body style="margin:0;width:{size}px;height:{size}px;background:transparent;">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="{tight}" width="100%" height="100%" preserveAspectRatio="xMidYMid meet">
  <path fill="{fill}"{stroke_attr} d="{PATH_D}"/>
</svg>
</body></html>"""


def render_svg_to_png(html: str, png_path: Path, size: int = 256) -> None:
    html_path = ROOT / f"_tmp_render_{int(size)}_{abs(hash(png_path.stem))}.html"
    html_path.write_text(html, encoding="utf-8")
    try:
        subprocess.run(
            [
                EDGE,
                "--headless",
                "--disable-gpu",
                "--hide-scrollbars",
                "--force-device-scale-factor=1",
                f"--window-size={size},{size}",
                f"--default-background-color=00000000",
                f"--screenshot={png_path}",
                html_path.as_uri(),
            ],
            check=True,
            capture_output=True,
            timeout=60,
        )
    finally:
        html_path.unlink(missing_ok=True)


def render_svg_file_to_png(svg_path: Path, png_path: Path, size: int = 256) -> None:
    """Render a standalone .svg file (already opaque background) to a square PNG."""
    html_path = ROOT / f"_tmp_app_{abs(hash(png_path.stem))}.html"
    html_path.write_text(
        f"""<!doctype html>
<html><head><meta charset="utf-8"></head>
<body style="margin:0;width:{size}px;height:{size}px;background:transparent;">
<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 1024 1024" preserveAspectRatio="xMidYMid meet">
  {svg_path.read_text(encoding="utf-8").split("<svg", 1)[1].split(">", 1)[1].rsplit("</svg>", 1)[0].strip()}
</svg>
</body></html>""",
        encoding="utf-8",
    )
    try:
        subprocess.run(
            [
                EDGE,
                "--headless",
                "--disable-gpu",
                "--hide-scrollbars",
                "--force-device-scale-factor=1",
                f"--window-size={size},{size}",
                "--default-background-color=00000000",
                f"--screenshot={png_path}",
                html_path.as_uri(),
            ],
            check=True,
            capture_output=True,
            timeout=60,
        )
    finally:
        html_path.unlink(missing_ok=True)


def build_ico_from_png(png: Path, ico_path: Path, crop: bool = False) -> None:
    img = Image.open(png).convert("RGBA")
    if crop:
        bbox = img.getchannel("A").getbbox()
        if bbox:
            # 四周留一点边距，避免圆角贴边太尖
            pad = max(1, int((bbox[2] - bbox[0]) * 0.01))
            img = img.crop((max(0, bbox[0] - pad), max(0, bbox[1] - pad),
                            min(img.width, bbox[2] + pad), min(img.height, bbox[3] + pad)))
    sizes = [16, 20, 24, 32, 48, 64, 128, 256]
    resized = [img.resize((s, s), Image.LANCZOS) for s in sizes]
    resized[-1].save(ico_path, format="ICO", sizes=[(s, s) for s in sizes],
                     append_images=resized[:-1])


def make_app_icon(png_path: Path, ico_path: Path, size: int = 256) -> None:
    """深灰圆角方块 + 居中的大号白色鲸鱼（桌面/应用图标）。"""
    square = size * 0.94
    margin = (size - square) / 2
    rx = square * 0.22
    whale_w = square * 0.70          # 鲸鱼宽度占据方块的 70%（介于 80% 太大与 60% 太小之间）
    scale = whale_w / 49.04          # 鲸鱼原始宽度 49.04
    cx = (0.63 + 49.67) / 2          # 鲸鱼绘制区域的横向中心
    cy = (6.63 + 43.66) / 2          # 鲸鱼绘制区域的纵向中心
    tx = size / 2 - cx * scale
    ty = size / 2 - cy * scale

    html = f"""<!doctype html>
<html><head><meta charset="utf-8"></head>
<body style="margin:0;width:{size}px;height:{size}px;background:transparent;">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="100%" height="100%">
  <rect x="{margin:.2f}" y="{margin:.2f}" width="{square:.2f}" height="{square:.2f}" rx="{rx:.2f}" fill="#2F3237"/>
  <g transform="translate({tx:.3f},{ty:.3f}) scale({scale:.5f})">
    <path fill="#FFFFFF" d="{PATH_D}"/>
  </g>
</svg>
</body></html>"""
    render_svg_to_png(html, png_path)
    build_ico_from_png(png_path, ico_path)


def main() -> None:
    out = ROOT
    # Running = brand blue, Stopped = grey. Keep medium contrast on both themes.
    # 托盘图标：白色鲸鱼 + 细深色描边（深浅色任务栏都能看清）
    variants = {
        "whale_running": ("#FFFFFF", "#333333"),
        "whale_stopped": ("#D0D3D6", "#5A5E63"),
    }
    for name, (fill, stroke) in variants.items():
        png = out / f"{name}.png"
        render_svg_to_png(html_for(fill, stroke), png)
        build_ico_from_png(png, out / f"{name}.ico")
        print(f"built {png.name} and {name}.ico")

    # 桌面快捷方式 / 应用图标：深灰圆角底 + 居中的大号白色鲸鱼
    make_app_icon(out / "dsh_app.png", out / "dsh_app.ico")
    print("built dsh_app.png and dsh_app.ico")


if __name__ == "__main__":
    main()
