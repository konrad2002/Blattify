#!/usr/bin/env python3
"""Export and import the 96x112 monochrome raster used by the captured P22 job."""

import argparse
from pathlib import Path
import struct
import sys

WIDTH = 96
HEIGHT = 112
ROW_BYTES = WIDTH // 8
RASTER_SIZE = ROW_BYTES * HEIGHT
BITMAP_COMMAND = b"BITMAP 0,0,12,112,1,"


def bitmap_offset(stream):
    offset = stream.find(BITMAP_COMMAND)
    if offset < 0:
        raise ValueError("captured bitmap command not found")
    offset += len(BITMAP_COMMAND)
    if len(stream) < offset + RASTER_SIZE:
        raise ValueError("captured bitmap is incomplete")
    return offset


def export_bmp(raster):
    if len(raster) != RASTER_SIZE:
        raise ValueError(f"expected {RASTER_SIZE} raster bytes")
    stride = (WIDTH * 3 + 3) & ~3
    pixels = bytearray()
    for y in range(HEIGHT - 1, -1, -1):
        for x in range(WIDTH):
            white = bool(raster[y * ROW_BYTES + x // 8] & (0x80 >> (x % 8)))
            pixels.extend(b"\xff\xff\xff" if white else b"\x00\x00\x00")
        pixels.extend(b"\0" * (stride - WIDTH * 3))
    header = struct.pack("<2sIHHI", b"BM", 54 + len(pixels), 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, WIDTH, HEIGHT, 1, 24, 0,
                       len(pixels), 0, 0, 0, 0)
    return header + info + pixels


def import_bmp(blob):
    if len(blob) < 54 or blob[:2] != b"BM":
        raise ValueError("not a supported BMP file")
    pixel_offset = struct.unpack_from("<I", blob, 10)[0]
    header_size = struct.unpack_from("<I", blob, 14)[0]
    if header_size < 40 or len(blob) < 14 + header_size:
        raise ValueError("unsupported or truncated BMP header")
    width, height, planes, depth, compression = struct.unpack_from("<iiHHI", blob, 18)
    if width != WIDTH or abs(height) != HEIGHT:
        raise ValueError(f"image must be exactly {WIDTH}x{HEIGHT} pixels")
    if planes != 1 or depth not in (1, 24, 32) or compression != 0:
        raise ValueError("BMP must be uncompressed 1-bit, 24-bit, or 32-bit RGB")
    palette = None
    if depth == 1:
        palette_start = 14 + header_size
        if pixel_offset < palette_start + 8 or len(blob) < palette_start + 8:
            raise ValueError("1-bit BMP palette is missing")
        palette = [tuple(blob[palette_start + i * 4:palette_start + i * 4 + 3])
                   for i in range(2)]
    elif pixel_offset < 14 + header_size:
        raise ValueError("invalid BMP pixel offset")
    stride = ((WIDTH * depth + 31) // 32) * 4
    if len(blob) < pixel_offset + stride * HEIGHT:
        raise ValueError("BMP pixel data is truncated")
    result = bytearray(RASTER_SIZE)
    for y in range(HEIGHT):
        source_y = y if height < 0 else HEIGHT - 1 - y
        row = pixel_offset + source_y * stride
        for x in range(WIDTH):
            if depth == 1:
                index = (blob[row + x // 8] >> (7 - x % 8)) & 1
                color = palette[index]
            else:
                index = row + x * (depth // 8)
                color = tuple(blob[index:index + 3])
                if depth == 32 and blob[index + 3] not in (0, 255):
                    raise ValueError("partially transparent BMP pixels are not supported")
            if color == (255, 255, 255):
                result[y * ROW_BYTES + x // 8] |= 0x80 >> (x % 8)
            elif color != (0, 0, 0):
                raise ValueError("image must contain only pure black and white pixels")
    return bytes(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new BMP file to create")
    parser.add_argument("--capture", type=Path, help="successful capture to extract")
    args = parser.parse_args()
    from print_captured import DEFAULT_CAPTURE, load_job

    try:
        writes = load_job(args.capture or DEFAULT_CAPTURE)
        stream = b"".join(data for _, _, data in writes)
        offset = bitmap_offset(stream)
        image = export_bmp(stream[offset:offset + RASTER_SIZE])
        with args.output.open("xb") as file:
            file.write(image)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Bitmap export failed: {error}\n")
    print(f"Exported {WIDTH}x{HEIGHT} BMP to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
