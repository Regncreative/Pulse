"""Generate Pulse app icons (PNG + multi-size ICO) from geometric logo rules."""

from __future__ import annotations

import io
import struct
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT_BRANDING = ROOT / "branding" / "generated"
OUT_WINDOWS = ROOT / "apps" / "pulse_app" / "windows" / "runner" / "resources"
OUT_ASSETS = ROOT / "apps" / "pulse_app" / "assets" / "branding"

TILE = (0x1B, 0x1F, 0x24, 0xFF)
ACCENT = (0x60, 0xCD, 0xFF, 0xFF)
SIZES = [16, 24, 32, 48, 64, 128, 256, 512]


def _round_rect(draw: ImageDraw.ImageDraw, box, radius: float, fill) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s = float(size)

    radius = s * 0.22
    _round_rect(draw, [0, 0, size - 1, size - 1], radius, TILE)

    stroke = max(2.0, s * (0.078 if size >= 32 else 0.1))
    node_r = max(1.2, s * 0.066)

    def x(u: float) -> float:
        return u / 32.0 * s

    def y(u: float) -> float:
        return u / 32.0 * s

    baseline_y = y(22)
    points = [
        (x(5), baseline_y),
        (x(10.5), baseline_y),
        (x(14), y(8)),
        (x(17.5), baseline_y),
        (x(27), baseline_y),
    ]

    for i in range(len(points) - 1):
        draw.line(
            [points[i], points[i + 1]],
            fill=ACCENT,
            width=int(round(stroke)),
            joint="curve",
        )

    half = stroke / 2.0
    for px, py in points:
        draw.ellipse([px - half, py - half, px + half, py + half], fill=ACCENT)

    cx, cy = points[2]
    draw.ellipse([cx - node_r, cy - node_r, cx + node_r, cy + node_r], fill=ACCENT)
    return img


def render_mark(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s = float(size)
    stroke = max(2.0, s * 0.08)
    node_r = max(1.2, s * 0.07)

    def x(u: float) -> float:
        return u / 32.0 * s

    def y(u: float) -> float:
        return u / 32.0 * s

    baseline_y = y(23)
    points = [
        (x(4), baseline_y),
        (x(10), baseline_y),
        (x(14.5), y(7)),
        (x(19), baseline_y),
        (x(28), baseline_y),
    ]
    for i in range(len(points) - 1):
        draw.line(
            [points[i], points[i + 1]],
            fill=ACCENT,
            width=int(round(stroke)),
            joint="curve",
        )
    half = stroke / 2.0
    for px, py in points:
        draw.ellipse([px - half, py - half, px + half, py + half], fill=ACCENT)
    cx, cy = points[2]
    draw.ellipse([cx - node_r, cy - node_r, cx + node_r, cy + node_r], fill=ACCENT)
    return img


def write_ico(path: Path, images_by_size: dict[int, Image.Image], sizes: list[int]) -> None:
    """Write a multi-size ICO using PNG-compressed frames (Windows Vista+)."""
    entries: list[tuple[int, bytes]] = []
    for size in sizes:
        buf = io.BytesIO()
        images_by_size[size].save(buf, format="PNG")
        entries.append((size, buf.getvalue()))

    count = len(entries)
    header = struct.pack("<HHH", 0, 1, count)
    offset = 6 + (16 * count)
    directory = bytearray()
    blobs = bytearray()
    for size, data in entries:
        w = 0 if size >= 256 else size
        h = 0 if size >= 256 else size
        directory += struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)

    path.write_bytes(header + directory + blobs)


def main() -> None:
    OUT_BRANDING.mkdir(parents=True, exist_ok=True)
    OUT_WINDOWS.mkdir(parents=True, exist_ok=True)
    OUT_ASSETS.mkdir(parents=True, exist_ok=True)

    images: dict[int, Image.Image] = {}
    for size in SIZES:
        images[size] = render(size)
        images[size].save(OUT_BRANDING / f"app_icon_{size}.png")
        images[size].save(OUT_ASSETS / f"app_icon_{size}.png")

    images[512].save(OUT_BRANDING / "app_icon.png")
    images[512].save(OUT_ASSETS / "app_icon.png")
    images[256].save(OUT_ASSETS / "taskbar_icon.png")

    mark = render_mark(128)
    mark.save(OUT_ASSETS / "mark.png")
    mark.save(OUT_BRANDING / "mark.png")

    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    ico_path = OUT_WINDOWS / "app_icon.ico"
    write_ico(ico_path, images, ico_sizes)
    write_ico(OUT_BRANDING / "app_icon.ico", images, ico_sizes)

    for name in ("app_icon.svg", "mark.svg", "app_icon_mono.svg"):
        src = ROOT / "branding" / "logo" / name
        if src.exists():
            (OUT_ASSETS / name).write_text(src.read_text(encoding="utf-8"), encoding="utf-8")

    print(f"Wrote icons to {OUT_BRANDING}")
    print(f"Wrote Windows ICO to {ico_path} ({ico_path.stat().st_size} bytes)")
    print(f"Wrote Flutter assets to {OUT_ASSETS}")


if __name__ == "__main__":
    main()
