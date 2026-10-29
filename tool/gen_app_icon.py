#!/usr/bin/env python3
"""生成 NeoLink 应用图标与品牌 PNG（链·N，方向 A）。

产出：
- apps/desktop_app/windows/runner/resources/app_icon.ico（16/24/32/48/64/256，
  ≤24px 自动用简化形：连续对角线 + 在线 accent 节点）
- design/png/*.png（512：单墨 / accent / 主色砖；256：主色砖）

几何空间 0..96，与 packages/neolink_ui/lib/src/widgets/nl_logo.dart 的画笔一致。
依赖 Pillow（pip install pillow）。
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICO = ROOT / "apps/desktop_app/windows/runner/resources/app_icon.ico"
PNG = ROOT / "design/png"

SS = 8  # 超采样倍数（抗锯齿）
INK = (22, 24, 29, 255)           # #16181D elevated ink（砖底，比纯黑任务栏亮一档）
MARK = (255, 255, 255, 255)       # 砖上反白
NODE_DARK = (20, 187, 194, 255)   # #14BBC2 暗面 accent（砖面用）
ACCENT_LIGHT = (0, 145, 155, 255) # #00919B 亮面 accent
INK_LIGHT = (22, 24, 29, 255)     # 亮面单墨（同 elevated ink）


def _capsule(d, p0, p1, w, color):
    d.line([p0, p1], fill=color, width=w)
    r = w / 2
    for p in (p0, p1):
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=color)


def _draw_mark(d, s, ink, node, simple):
    """在 0..96 几何空间画链·N；s = 每单位多少像素。"""
    w = round((11 if simple else 9) * s)
    pt = lambda x, y: (x * s, y * s)  # noqa: E731
    _capsule(d, pt(24, 22), pt(24, 74), w, ink)
    _capsule(d, pt(72, 22), pt(72, 74), w, ink)
    if simple:
        _capsule(d, pt(24, 22), pt(72, 74), w, ink)
    else:
        _capsule(d, pt(26, 24), pt(40, 39), w, ink)
        _capsule(d, pt(56, 57), pt(70, 72), w, ink)
    cx, cy = pt(48, 48)
    r = 8 * s
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=node)


def make_mark(px, ink, node, simple):
    """透明底标志 PNG（先超采样再 LANCZOS 缩小）。"""
    canvas = round(px * SS)
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    _draw_mark(ImageDraw.Draw(img), canvas / 96, ink, node, simple)
    return img.resize((round(px), round(px)), Image.LANCZOS)


def make_tile(px, simple):
    """主色砖图标：elevated ink 圆角砖（rx≈22%）+ 居中 75% 反白标志。"""
    canvas = round(px * SS)
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle(
        [0, 0, canvas - 1, canvas - 1], radius=round(canvas * 0.22), fill=INK
    )
    img = img.resize((round(px), round(px)), Image.LANCZOS)
    mark = make_mark(px * 0.75, MARK, NODE_DARK, simple)
    off = round(px * 0.125)
    img.paste(mark, (off, off), mark)
    return img


def main():
    PNG.mkdir(parents=True, exist_ok=True)
    ICO.parent.mkdir(parents=True, exist_ok=True)

    sizes = [16, 24, 32, 48, 64, 256]
    frames = [make_tile(s, simple=s <= 24) for s in sizes]
    frames[-1].save(  # 256 为基图，其余按尺寸入包
        ICO, format="ICO", append_images=frames[:-1], sizes=[(s, s) for s in sizes]
    )

    make_mark(512, INK_LIGHT, INK_LIGHT, False).save(PNG / "neolink-logo-512.png")
    make_mark(512, INK_LIGHT, ACCENT_LIGHT, False).save(PNG / "neolink-logo-accent-512.png")
    make_tile(512, False).save(PNG / "neolink-logo-tile-512.png")
    make_tile(256, False).save(PNG / "neolink-logo-tile-256.png")

    got = Image.open(ICO).info.get("sizes")
    print(f"ico: {ICO.relative_to(ROOT)} sizes={sorted(got or [])}")
    for f in sorted(PNG.glob("*.png")):
        print(f"png: {f.relative_to(ROOT)} {f.stat().st_size // 1024}KB")


if __name__ == "__main__":
    main()
