#!/usr/bin/env python3
"""Pack the Anvil world's sprites into one RGBA PNG strip (stdlib only).

Usage: gen_atlas.py assets/art/world.json build/web/art.png
Sprites are laid out left to right in the order of the first sprite set; the
Odin `Sprite` enum in src/main.odin must list them in the same order.
Palette index 0 is the sprite's transparent colour and becomes alpha 0.
"""
import json, struct, sys, zlib

def main(src, dst):
    w = json.load(open(src))
    tw, th = w["tile_width"], w["tile_height"]
    pal = [(c["r"], c["g"], c["b"]) for c in w["palette"]]
    images = {}
    for ts in w["tilesets"]:
        for im in ts["tileset"]["images"]:
            images[(ts["name"], im["name"])] = im["bytes"]
    sprites = w["sprite_sets"][0]["sprites"]
    row_bytes = (tw + 1) // 2
    width = tw * len(sprites)
    rows = []
    for y in range(th):
        line = bytearray([0])  # PNG filter: none
        for sp in sprites:
            data = images[(sp["tileset"], sp["image"])]
            for x in range(tw):
                b = data[y * row_bytes + x // 2]
                idx = (b >> 4) if x % 2 == 0 else (b & 15)
                if idx == sp["transparent"]:
                    line += bytes((0, 0, 0, 0))
                else:
                    line += bytes(pal[idx]) + b"\xff"
        rows.append(bytes(line))

    def chunk(kind, body):
        c = struct.pack(">I", len(body)) + kind + body
        return c + struct.pack(">I", zlib.crc32(kind + body))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, th, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
    png += chunk(b"IEND", b"")
    open(dst, "wb").write(png)
    print(f"{dst}: {len(sprites)} sprites {tw}x{th}: " + ", ".join(s["name"] for s in sprites))

main(sys.argv[1], sys.argv[2])
