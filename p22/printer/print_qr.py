#!/usr/bin/env python3
"""Print a five-character heading and QR code on the captured P22 label layout."""

import argparse
from pathlib import Path
import re
import sys

import qrcode
from qrcode.exceptions import DataOverflowError
from PIL import Image, ImageDraw, ImageFont

import p22_bitmap
import print_captured

HEADING_HEIGHT = 16
HEADING_QR_GAP = 3
QR_SIDE = 96
QUIET_ZONE = 0
MIN_MODULE_SIZE = 2


def make_label(qr_text, label):
    if not qr_text:
        raise ValueError("QR text must not be empty")
    if not re.fullmatch(r"[\x20-\x7e]{5}", label):
        raise ValueError("label must contain exactly five printable ASCII characters")

    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,
                       border=QUIET_ZONE, box_size=1)
    qr.add_data(qr_text)
    try:
        qr.make(fit=True)
    except DataOverflowError as error:
        raise ValueError("QR text is too long") from error
    matrix = qr.get_matrix()
    module_size = QR_SIDE // len(matrix)
    if module_size < MIN_MODULE_SIZE:
        raise ValueError("QR text is too long for a 96-pixel QR code with "
                         "two-pixel minimum modules")

    image = Image.new("1", (p22_bitmap.WIDTH, p22_bitmap.HEIGHT), 1)
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=14)
    left, top, right, bottom = draw.textbbox((0, 0), label, font=font)
    text_width, text_height = right - left, bottom - top
    if text_height > HEADING_HEIGHT - HEADING_QR_GAP:
        font = ImageFont.load_default(size=13)
        left, top, right, bottom = draw.textbbox((0, 0), label, font=font)
        text_width, text_height = right - left, bottom - top
    if text_width > p22_bitmap.WIDTH or text_height > HEADING_HEIGHT - HEADING_QR_GAP:
        raise ValueError("label does not fit the heading area")
    draw.text(((p22_bitmap.WIDTH - text_width) // 2 - left,
               HEADING_HEIGHT - HEADING_QR_GAP - bottom), label, font=font, fill=0)

    # Distribute pixel rounding across modules instead of adding outside margins.
    for row, values in enumerate(matrix):
        for column, black in enumerate(values):
            if black:
                x0 = column * QR_SIDE // len(matrix)
                x1 = (column + 1) * QR_SIDE // len(matrix)
                y0 = HEADING_HEIGHT + row * QR_SIDE // len(matrix)
                y1 = HEADING_HEIGHT + (row + 1) * QR_SIDE // len(matrix)
                draw.rectangle((x0, y0, x1 - 1, y1 - 1), fill=0)
    return image, module_size


def image_to_raster(image):
    if image.size != (p22_bitmap.WIDTH, p22_bitmap.HEIGHT) or image.mode != "1":
        raise ValueError("label image must be a 96x112 monochrome image")
    return image.tobytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address", help="real printer Bluetooth MAC address")
    parser.add_argument("qr_text", help="text encoded in the QR code")
    parser.add_argument("label", help="exactly five printable ASCII characters")
    parser.add_argument("--adapter", default="/org/bluez/hci0",
                        help="BlueZ adapter object path")
    parser.add_argument("--capture", type=Path, default=print_captured.DEFAULT_CAPTURE,
                        help="successful capture used as the print template")
    parser.add_argument("--log", type=Path, help="new print log path")
    parser.add_argument("--preview", type=Path, help="save a new BMP preview")
    parser.add_argument("--dry-run", action="store_true", help="generate without printing")
    args = parser.parse_args()
    if not re.fullmatch(r"(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}", args.address):
        parser.error("address must be a Bluetooth MAC address")
    try:
        image, module_size = make_label(args.qr_text, args.label)
        writes = print_captured.replace_bitmap(
            print_captured.load_job(args.capture), image_to_raster(image)
        )
        if args.preview:
            with args.preview.open("xb") as file:
                file.write(p22_bitmap.export_bmp(image_to_raster(image)))
    except (OSError, ValueError) as error:
        parser.exit(1, f"Cannot prepare label: {error}\n")
    print(f"Generated 96x112 label, minimum QR module size {module_size} pixels.", flush=True)
    if args.preview:
        print(f"Preview: {args.preview}", flush=True)
    if args.dry_run:
        return 0
    try:
        return print_captured.print_job(writes, args.address, args.adapter, args.log)
    except OSError as error:
        parser.exit(1, f"Print failed: {error}\n")


if __name__ == "__main__":
    sys.exit(main())
