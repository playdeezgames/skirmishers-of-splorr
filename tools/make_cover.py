"""Crops the raw captures from tools/shots.sh to the canvas and builds the cover.

Usage: python3 -I tools/make_cover.py SHOTS_DIR ASSETS_DIR
  SHOTS_DIR/NN-name.png -> ASSETS_DIR/screenshots/NN-name.png (cropped to 1060x580)
  ASSETS_DIR/cover.png  -> 630x500 (itch.io cover): a slice of the battle map
                           under a title band.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CANVAS = (0, 0, 1060, 580)  # the window is sized so the canvas sits at the top left
MAP_W = 660  # the hex map is the left 660 pixels of the canvas
COVER = (630, 500)
BAND = 112  # title band height
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"


def main(shots: Path, assets: Path) -> None:
    out = assets / "screenshots"
    out.mkdir(parents=True, exist_ok=True)
    for raw in sorted(shots.glob("[0-9][0-9]-*.png")):
        Image.open(raw).convert("RGB").crop(CANVAS).save(out / raw.name)

    battle = Image.open(out / "02-battle.png")
    cover = Image.new("RGB", COVER, (22, 22, 30))
    # the middle of the battle map, where the lines meet
    h = COVER[1] - BAND
    left = (MAP_W - COVER[0]) // 2
    top = (580 - h) // 2
    cover.paste(battle.crop((left, top, left + COVER[0], top + h)), (0, BAND))

    draw = ImageDraw.Draw(cover)
    draw.rectangle((0, 0, COVER[0], BAND), fill=(22, 22, 30))
    draw.line((0, BAND - 1, COVER[0], BAND - 1), fill=(255, 217, 77), width=2)
    title = ImageFont.truetype(FONT, 40)
    sub = ImageFont.truetype(FONT, 18)
    for text, font, y, colour in (
        ("Skirmishers", title, 30, (255, 217, 77)),
        ("of SPLORR!!", title, 74, (255, 217, 77)),
    ):
        w = draw.textlength(text, font=font)
        draw.text(((COVER[0] - w) / 2, y), text, font=font, fill=colour, anchor="lm")
    tag = "kobolds, dice and hexes"
    draw.text((COVER[0] - 12, BAND + 18), tag, font=sub, fill=(240, 240, 240), anchor="rm",
              stroke_width=3, stroke_fill=(22, 22, 30))
    cover.save(assets / "cover.png")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
