"""Build the runtime Save icon from the approved logo. Python 3, standard library only.

Crops the shield-and-swords emblem from the 512-pixel logo PNG, box-filters it to
64 x 64, and writes an uncompressed 32-bit TGA, a texture format WoW AddOns load.
The output is deterministic for the same input PNG.
"""

import argparse
import struct
import sys
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "artwork" / "weapon-sets-forever-logo-512.png"
TARGET = ROOT / "Textures" / "SaveIcon.tga"
# The emblem without the outer frame and diamonds, which vanish at button size.
CROP_LEFT, CROP_TOP, CROP_SIZE = 96, 92, 320
ICON_SIZE = 64
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
RGBA = 6
TGA_TRUECOLOR = 2
# Bits 0-3: 8 alpha bits; bit 5: rows run top to bottom.
TGA_DESCRIPTOR = 0x28


def _paeth(left, up, up_left):
    estimate = left + up - up_left
    left_distance = abs(estimate - left)
    up_distance = abs(estimate - up)
    up_left_distance = abs(estimate - up_left)
    if left_distance <= up_distance and left_distance <= up_left_distance:
        return left
    return up if up_distance <= up_left_distance else up_left


def read_png_rgba(path):
    """Return (width, height, rows) for an 8-bit, non-interlaced RGBA PNG."""
    data = Path(path).read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("Source is not a PNG")
    offset = len(PNG_SIGNATURE)
    header = None
    compressed = bytearray()
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            compressed += body
        elif kind == b"IEND":
            break
    if header is None:
        raise ValueError("PNG has no IHDR chunk")
    width, height, depth, color, _, _, interlace = header
    if depth != 8 or color != RGBA or interlace != 0:
        raise ValueError("Source must be an 8-bit, non-interlaced RGBA PNG")
    raw = zlib.decompress(bytes(compressed))
    stride = width * 4
    rows = []
    previous = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        row = bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            left = row[x - 4] if x >= 4 else 0
            up = previous[x]
            up_left = previous[x - 4] if x >= 4 else 0
            if kind == 1:
                row[x] = (row[x] + left) & 0xFF
            elif kind == 2:
                row[x] = (row[x] + up) & 0xFF
            elif kind == 3:
                row[x] = (row[x] + (left + up) // 2) & 0xFF
            elif kind == 4:
                row[x] = (row[x] + _paeth(left, up, up_left)) & 0xFF
            elif kind != 0:
                raise ValueError(f"Unsupported PNG filter type {kind}")
        rows.append(bytes(row))
        previous = row
    return width, height, rows


def build_icon_pixels(width, height, rows):
    """Crop the emblem and box-filter it to ICON_SIZE; returns RGBA rows."""
    if CROP_LEFT + CROP_SIZE > width or CROP_TOP + CROP_SIZE > height:
        raise ValueError("Crop exceeds the source image")
    if CROP_SIZE % ICON_SIZE:
        raise ValueError("Crop size must be a whole multiple of the icon size")
    factor = CROP_SIZE // ICON_SIZE
    area = factor * factor
    result = []
    for y in range(ICON_SIZE):
        row = bytearray()
        for x in range(ICON_SIZE):
            totals = [0, 0, 0, 0]
            for source_y in range(CROP_TOP + y * factor, CROP_TOP + (y + 1) * factor):
                line = rows[source_y]
                for source_x in range(CROP_LEFT + x * factor, CROP_LEFT + (x + 1) * factor):
                    pixel = line[source_x * 4:source_x * 4 + 4]
                    for channel in range(4):
                        totals[channel] += pixel[channel]
            row += bytes((total + area // 2) // area for total in totals)
        result.append(bytes(row))
    return result


def encode_tga(rows):
    """Encode square RGBA rows as an uncompressed, top-left-origin BGRA TGA."""
    size = len(rows)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, TGA_TRUECOLOR, 0, 0, 0,
                         0, 0, size, size, 32, TGA_DESCRIPTOR)
    body = bytearray()
    for row in rows:
        for x in range(0, len(row), 4):
            red, green, blue, alpha = row[x:x + 4]
            body += bytes((blue, green, red, alpha))
    return header + bytes(body)


def build(source=SOURCE, target=TARGET):
    width, height, rows = read_png_rgba(source)
    data = encode_tga(build_icon_pixels(width, height, rows))
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return data


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=TARGET)
    args = parser.parse_args(argv)
    try:
        data = build(args.source, args.output)
    except (ValueError, OSError, zlib.error) as error:
        parser.exit(1, f"Icon build failed: {error}\n")
    print(f"Wrote {args.output} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
