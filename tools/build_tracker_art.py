"""Pack generated three-expression sheets into the client's 256px RGBA TGAs.

Run with python tools/build_tracker_art.py (requires Pillow).
Artwork/Tracker holds the original ImageGen sheets and prompts. Media contains
only the runtime assets. This is format conversion and sprite packing; alpha
from the generated artwork is preserved, including its antialiased edges.
"""
from pathlib import Path

from PIL import Image

from make_orc_glow import glow, write_tga

ROOT = Path(__file__).resolve().parents[1]
SIZE = 256
MOODS = ("Happy", "Grumpy", "Angry")


def build(prefix):
    sheet = Image.open(ROOT / "Artwork" / "Tracker" / f"{prefix}.png").convert("RGBA")
    width, height = sheet.size
    if width != height * 3:
        raise ValueError(f"{prefix}: expected three equal square cells")
    cells = [sheet.crop((i * height, 0, (i + 1) * height, height)) for i in range(3)]
    # ImageGen can leave isolated alpha=1 speckles far outside the portrait.
    # Ignore those only when measuring bounds; preserve the sprite's alpha.
    bounds = [cell.getchannel("A").point(lambda value: 255 if value >= 2 else 0).getbbox()
              for cell in cells]
    if any(not box or min(box[:2]) <= 0 or max(box[2:]) >= height for box in bounds):
        raise ValueError(f"{prefix}: artwork touches a cell edge or a cell is empty")
    # One scale for all expressions, centred independently to correct sheet drift.
    scale = (SIZE - 12) / max(max(b[2] - b[0], b[3] - b[1]) + 4 for b in bounds)
    for mood, cell, bounds in zip(MOODS, cells, bounds):
        box = (bounds[0] - 2, bounds[1] - 2, bounds[2] + 2, bounds[3] + 2)
        dimensions = (round((box[2] - box[0]) * scale), round((box[3] - box[1]) * scale))
        image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        sprite = cell.crop(box).resize(dimensions, Image.Resampling.LANCZOS)
        image.paste(sprite, ((SIZE - dimensions[0]) // 2, (SIZE - dimensions[1]) // 2))
        path = ROOT / "Media" / f"{prefix}{mood}.tga"
        image.save(path, compression=None)
        print("wrote", path.relative_to(ROOT))
    path = ROOT / "Media" / f"{prefix}Glow.tga"
    write_tga(path, glow(prefix))
    print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    for prefix in ("Orc", "Gnome", "NightElf", "Tauren", "Human", "Troll", "Undead"):
        build(prefix)
