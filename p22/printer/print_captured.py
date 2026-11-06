#!/usr/bin/env python3
"""Reproduce the successfully captured P22 print job without a phone."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import signal
import sys
from uuid import uuid4

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

import fake_p22 as fake
from p22_bridge import Bridge, Capture
from p22_bitmap import RASTER_SIZE, bitmap_offset, import_bmp


DEFAULT_CAPTURE = Path(__file__).with_name("p22-relay-20261106T122739Z-c21ae499.jsonl")
FF02 = fake.uuid("ff02")


def load_job(path):
    writes = []
    accepted = {}
    with open(path, encoding="utf-8") as file:
        for line_number, line in enumerate(file, 1):
            try:
                event = json.loads(line)
                direction = event["direction"]
                operation = event["operation"]
                data = bytes.fromhex(event["hex"])
                if len(data) != event["length"]:
                    raise ValueError("length does not match data")
                if direction == "phone_to_printer" and operation == "write":
                    if event["characteristic"] != FF02:
                        raise ValueError("unsupported write characteristic")
                    options = event.get("options", {})
                    if options.get("type", "command") != "command" or int(options.get("offset", 0)):
                        raise ValueError("only zero-offset write commands are supported")
                    timestamp = datetime.fromisoformat(event["timestamp"])
                    if timestamp.tzinfo is None:
                        raise ValueError("timestamp has no timezone")
                    writes.append((event["write_id"], timestamp, data))
                elif direction == "bridge_to_printer" and operation == "write_accepted":
                    accepted.setdefault(event["write_id"], []).append(
                        (int(event["offset"]), event["characteristic"], data)
                    )
                elif operation in ("write_failed", "error"):
                    raise ValueError("capture contains an error")
            except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
                raise ValueError(f"{path}:{line_number}: {error}") from error
    if not writes:
        raise ValueError("capture has no phone writes")
    seen = set()
    previous = None
    for write_id, timestamp, data in writes:
        if write_id in seen:
            raise ValueError(f"duplicate write id {write_id}")
        seen.add(write_id)
        if previous is not None and timestamp < previous:
            raise ValueError("write timestamps are out of order")
        previous = timestamp
        offset = 0
        for chunk_offset, characteristic, chunk in accepted.get(write_id, []):
            if chunk_offset != offset or characteristic != FF02 or not chunk:
                raise ValueError(f"invalid accepted chunks for write {write_id}")
            if data[offset:offset + len(chunk)] != chunk:
                raise ValueError(f"accepted data does not match write {write_id}")
            offset += len(chunk)
        if offset != len(data):
            raise ValueError(f"write {write_id} was not fully accepted by BlueZ")

    job = b"".join(data for _, _, data in writes)
    if job.count(b"SIZE 15 mm,14 mm\r\n") != 1:
        raise ValueError("expected exactly one captured 15x14 mm print job")
    start = job.index(b"SIZE 15 mm,14 mm\r\n")
    prefix = b"SIZE 15 mm,14 mm\r\nGAP 0,0\r\nDIRECTION 0,0\r\nDENSITY 15\r\nCLS\r\nBITMAP 0,0,12,112,1,"
    if not job[start:].startswith(prefix):
        raise ValueError("unrecognized print header")
    if len(job[start:]) != len(prefix) + 12 * 112 + len(b"\r\nPRINT 1\r\n"):
        raise ValueError("bitmap or print job has unexpected length")
    if not job.endswith(b"\r\nPRINT 1\r\n"):
        raise ValueError("print command is missing")
    return writes


def replace_bitmap(writes, raster):
    if len(raster) != RASTER_SIZE:
        raise ValueError(f"expected {RASTER_SIZE} bitmap bytes")
    stream = b"".join(data for _, _, data in writes)
    offset = bitmap_offset(stream)
    stream = stream[:offset] + raster + stream[offset + RASTER_SIZE:]
    result = []
    position = 0
    for write_id, timestamp, data in writes:
        result.append((write_id, timestamp, stream[position:position + len(data)]))
        position += len(data)
    return result


class CapturedJobPrinter(Bridge):
    def __init__(self, bus, adapter, address, capture, writes):
        super().__init__(bus, adapter, address, "probe", capture)
        self.job_writes = writes
        self.job_index = 0
        self.timer = None
        self.complete = False

    def probe_next(self):
        self.state = "printing"
        print(f"Sending {len(self.job_writes)} captured writes.", flush=True)
        self.send_job_write()

    def send_job_write(self):
        self.timer = None
        _, timestamp, data = self.job_writes[self.job_index]

        def sent():
            self.job_index += 1
            if self.job_index == len(self.job_writes):
                print("All writes accepted by BlueZ; waiting for the printer.", flush=True)
                self.timer = GLib.timeout_add_seconds(3, self.finish_job)
            else:
                delay = (self.job_writes[self.job_index][1] - timestamp).total_seconds()
                self.timer = GLib.timeout_add(max(1, round(delay * 1000)), self.send_job_write)

        self.write(FF02, data, {"type": dbus.String("command")}, sent,
                   lambda error: print(f"Print write failed: {error}", file=sys.stderr))
        return False

    def finish_job(self):
        self.timer = None
        self.complete = True
        self.loop.quit()
        return False

    def cleanup(self):
        if self.timer is not None:
            GLib.source_remove(self.timer)
            self.timer = None
        super().cleanup()


def print_job(writes, address, adapter, log_path=None):
    log_path = log_path or Path(
        f"p22-print-{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{uuid4().hex[:8]}.jsonl"
    )
    capture = Capture(log_path)
    print(f"Print log: {log_path}", flush=True)
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    try:
        bus = dbus.SystemBus()
    except dbus.DBusException:
        capture.close()
        raise
    printer = CapturedJobPrinter(bus, adapter, address, capture, writes)
    signal_source = GLib.unix_signal_add(
        GLib.PRIORITY_DEFAULT, signal.SIGINT, lambda: (printer.loop.quit(), True)[1]
    )
    try:
        printer.start()
    finally:
        GLib.source_remove(signal_source)
        printer.cleanup()
    if not printer.complete:
        print("Print was not completed; the printer may have received partial data.",
              file=sys.stderr)
        return 1
    if printer.failed:
        return 1
    print("Transmission finished. Confirm the label printed correctly.", flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--address", default="2A:F3:AE:5A:48:33",
                        help="real printer Bluetooth MAC address")
    parser.add_argument("--adapter", default="/org/bluez/hci0")
    parser.add_argument("--capture", type=Path, default=DEFAULT_CAPTURE,
                        help="successful relay capture containing the original job")
    parser.add_argument("--bitmap", type=Path,
                        help="replace captured image with a 96x112 black-and-white BMP")
    parser.add_argument("--log", type=Path, help="new output log; must not already exist")
    parser.add_argument("--dry-run", action="store_true", help="validate without printing")
    args = parser.parse_args()
    if not re.fullmatch(r"(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}", args.address):
        parser.error("--address must be a Bluetooth MAC address")
    try:
        writes = load_job(args.capture)
        if args.bitmap:
            writes = replace_bitmap(writes, import_bmp(args.bitmap.read_bytes()))
    except (OSError, ValueError) as error:
        parser.exit(1, f"Invalid capture: {error}\n")
    print(f"Validated {len(writes)} writes from {args.capture}.", flush=True)
    if args.dry_run:
        return 0
    try:
        return print_job(writes, args.address, args.adapter, args.log)
    except OSError as error:
        parser.exit(1, f"Print failed: {error}\n")


if __name__ == "__main__":
    sys.exit(main())
