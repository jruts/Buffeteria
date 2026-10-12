"""Build Media/OrcGlow.tga: a soft white glow around the orc silhouette.

The silhouette is shrunk to SCALE of the canvas so the glow has room to spread.
Draw the result at 1 / SCALE of the head's size, centered on the head.
"""
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "Media"
SIZE = 256
SCALE = 0.625  # keep in sync with GLOW_SCALE in Features/Tracker/Tracker.lua


def silhouette():
    alpha = None
    for mood in ("Happy", "Grumpy", "Angry"):
        a = Image.open(MEDIA / f"Orc{mood}.tga").convert("RGBA").getchannel("A")
        alpha = a if alpha is None else ImageChops.lighter(alpha, a)
    return alpha


def glow():
    inner = int(SIZE * SCALE)
    canvas = Image.new("L", (SIZE, SIZE), 0)
    off = (SIZE - inner) // 2
    canvas.paste(silhouette().resize((inner, inner), Image.LANCZOS), (off, off))
    spread = canvas.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(14))
    # Brighten the falloff so the rim reads clearly against dark scenery.
    spread = spread.point(lambda v: min(255, int(v * 1.6)))
    # Fade to nothing well before the canvas edge, avoiding a square cut-off.
    edge = Image.new("L", (SIZE, SIZE), 0)
    edge.paste(255, (6, 6, SIZE - 6, SIZE - 6))
    return ImageChops.multiply(spread, edge.filter(ImageFilter.GaussianBlur(4)))


def write_tga(path, alpha):
    # Uncompressed 32-bit, bottom-left origin, matching the orc artwork.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    rows = []
    for y in range(SIZE - 1, -1, -1):
        rows.append(b"".join(bytes((255, 255, 255, alpha.getpixel((x, y)))) for x in range(SIZE)))
    path.write_bytes(header + b"".join(rows))


if __name__ == "__main__":
    write_tga(MEDIA / "OrcGlow.tga", glow())
    print("wrote", MEDIA / "OrcGlow.tga")
