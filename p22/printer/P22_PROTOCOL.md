# P22 BLE printer: implementation handoff

This document describes one P22 printer observed on 6 November 2026. It is a
reverse-engineering record, not a manufacturer's protocol specification.
Commands and bytes marked **observed** come from the discovery and relay
captures; meanings marked **unknown** must not be presented as confirmed facts.
Other P22 devices, firmware, paper, and operating systems may behave differently.

The relay successfully printed the original captured job. The same captured job
was then replayed directly from Linux, and the owner confirmed that it printed.
The QR generator builds on that proven job by replacing its raster, but the
latest three-pixel-gap layout has not been physically verified in these notes.
An accepted BLE write does not prove that the printer processed or printed it.

## Files to give the implementation agent

Recommended minimum:

- This file.
- [`../discovery.json`](../discovery.json): observed advertisement, services,
  characteristic properties, and descriptor information.
- [`p22-relay-20261106T122739Z-c21ae499.jsonl`](./p22-relay-20261106T122739Z-c21ae499.jsonl):
  the successful relay print, including exact writes, notifications, chunking,
  and timestamps. It contains the original label image and device identifiers;
  review it before sharing.
- [`print_captured.py`](./print_captured.py): validates and replays that
  capture, substitutes a same-size bitmap, and preserves captured write timing.
- [`p22_bitmap.py`](./p22_bitmap.py): raster packing and BMP conversion.
- [`print_qr.py`](./print_qr.py): current QR and heading layout.
- [`test_print_captured.py`](./test_print_captured.py),
  [`test_p22_bitmap.py`](./test_p22_bitmap.py), and
  [`test_print_qr.py`](./test_print_qr.py): executable examples and checks.

For further investigation, include [`p22_bridge.py`](./p22_bridge.py) and
[`fake_p22.py`](./fake_p22.py), which implement the Linux GATT relay and
service definitions, and [`p22-traffic.jsonl`](./p22-traffic.jsonl), an earlier
exchange. [`../capture/capture1.txt`](../capture/capture1.txt) contains the
original phone-to-fake-printer observations, without real printer responses.
[`captured-label.bmp`](./captured-label.bmp) visualizes the captured raster.
These Python files are reference implementations, not Swift dependencies.
Logs and discovery records may contain device identifiers and private label
contents; share only what is appropriate.

## Discovery and identification

The observed real printer advertised:

| Advertisement field | Observed value |
| --- | --- |
| Local name | `P22` |
| Advertised service | `0000af30-0000-1000-8000-00805f9b34fb` (`AF30`) |
| Manufacturer company identifier | `0xF32A` (on-air little-endian bytes `2a f3`) |
| Manufacturer payload after company ID | `ae 5a 48 33` |
| Service data | None in this discovery |

`AF30` is the **advertised** service identifier; discovery of the actual GATT
services found `FF00`, `AE3A`, and `AE00` instead. Do not assume that `AF30`
will also be returned as a connected GATT service. `P22` and `AF30` are useful
candidate filters, not proven unique product identifiers. The manufacturer
bytes above are from one printer and must not be hardcoded as a universal
identifier. In this example, the company ID bytes followed by the payload
happen to match the Linux Bluetooth address, but the meaning of that
correspondence and its validity for other printers are unknown.

List discovered candidates by the platform's peripheral identifier, name, and
optionally signal strength. On iOS, the identifier in `discovery.json` is a
platform UUID, **not** a Bluetooth MAC address; do not use the example Linux
address as an iOS identifier or assume identifiers are portable across devices.
Handle missing advertisement fields and duplicate names. A list can show
connection state immediately, but the observed advertisement does not contain
a confirmed battery level or paper type: those require a connection and status
queries. A production app also needs the platform's Bluetooth authorization
and usage description, and must handle Bluetooth being unavailable or disabled.

## Connected GATT database

The following are 16-bit UUIDs in the Bluetooth base UUID
`0000xxxx-0000-1000-8000-00805f9b34fb`. Properties are from the observed
discovery; handles are deliberately omitted because they are not portable.

| Service | Characteristic | Observed properties | Observed role |
| --- | --- | --- | --- |
| `FF00` | `FF02` | write without response | Status queries and print stream |
| `FF00` | `FF01` | notify | Status query responses |
| `FF00` | `FF04` | write without response | Unknown |
| `FF00` | `FF03` | notify | Subscribed by phone; purpose unknown |
| `FF00` | `FF05` | indicate | Purpose unknown |
| `FF00` | `FF10` | read, write | Discovery read returned `00 00 00 00`; purpose unknown |
| `AE3A` | `AE3B` | write without response | Unknown |
| `AE3A` | `AE3C` | notify | Unknown |
| `AE00` | `AE01` | write without response | A binary write was observed; purpose unknown |
| `AE00` | `AE02` | notify | Subscribed by phone; purpose unknown |

The notify/indicate characteristics had standard `2902` client configuration
descriptors. The phone in the successful relay subscribed to `FF01`, `FF03`,
and `AE02` before its status requests. The Linux probe subscribes to all
observed notification and indication characteristics before writing; that is
reference behavior, **not** evidence all subscriptions are necessary.
At minimum, establish `FF01` notifications and wait for subscription success
before sending `FF02` status requests. Discover services and characteristics
and verify their properties; do not hardcode attribute handles.

## Status requests and responses

Send the following raw bytes to `FF02` as write-without-response. The line
endings are CR LF (`0d 0a`), not just LF. Responses below arrived through
`FF01`; values following the ASCII prefixes are **binary**, not ASCII digits.

| Purpose | Request | Example observed response |
| --- | --- | --- |
| Battery query | `BATTERY?\r\n` = `42 41 54 54 45 52 59 3f 0d 0a` | `42 41 54 54 45 52 59 20 99 00 0d 0a` (`BATTERY ` + `99 00` + CR LF) |
| Configuration query | `CONFIG?\r\n` = `43 4f 4e 46 49 47 3f 0d 0a` | `43 4f 4e 46 49 47 20 00 cb 00 00 02 00 00 08 02 01 0d 0a` (`CONFIG ` + ten binary bytes + CR LF) |
| Unknown query A | `1b 21 6f 0d 0a` | `00 0c 01 22 03 00 03 00 00 12 15 0a 0f 0e 55 4f` |
| Unknown query B | `1b 21 3f 0d 0a` | `00` |

These are observed pairings based on ordering, not a complete framing or
request-correlation specification. The 16-byte binary response itself contains
`0a`, and the one-byte response has no line ending. Do not decode all
notifications as text, strip zero bytes, or treat a newline as a universal
packet delimiter. Notification boundaries happened to contain complete
responses in these captures, but fragmentation/coalescing behavior has not
been established. Preserve raw bytes, validate lengths and prefixes, and
surface unknown or malformed responses and timeouts. Avoid sending concurrent
queries whose untagged responses cannot be reliably correlated.

### Battery and paper type: important limitation

The owner reported that the original phone app displayed battery state and
paper type when connected through the relay. The relay forwards bytes; it does
not decode either value. Across the inspected captures the battery payload was
always `99 00`, and the config payload was always
`00 cb 00 00 02 00 00 08 02 01`. There is no paired record of the app's
numerical display or paper-type selection, and no controlled samples from
different battery levels or paper types. Thus:

- `99 00` is **not proven** to mean 99%, a little-endian integer, BCD, voltage,
  or anything else. Do not display a made-up percentage.
- It is plausible that `CONFIG` or the 16-byte response contains paper
  information, but neither a byte offset nor a paper-type mapping has been
  established. Do not label `02`, `01`, or any other value as a known paper
  type without more evidence.
- The list UI should show “unknown” or “not yet decoded” until a real mapping
  has been validated. Track connection/query failures separately from unknown
  values. Raw payloads can be shown in a diagnostic view.

To establish those mappings, collect timestamped query/response bytes and the
original app's displayed values for several independently confirmed battery
levels and several paper types, changing one condition at a time. Include a
reconnect and repeated reads, and record paper presence or lid state when
relevant. Compare byte differences, validate a proposed mapping against new
samples, and retain unknown handling. Passive relay captures are preferable;
do not issue speculative state-changing commands.

## Captured connection and print sequence

In the successful capture, after the three phone subscriptions above, all
phone writes were to `FF02`. The table shows phone-side write timestamps:
elapsed times include human/app delays and are observations, not documented
minimum waits. The Linux replay preserves these inter-write delays, starts
after it has subscribed to the printer, and does not parse the responses before
continuing.

| Step | Delay since preceding write | Bytes / action |
| --- | ---: | --- |
| 1 | — | `BATTERY?\r\n` |
| 2 | 0.719 s | `CONFIG?\r\n` |
| 3 | 4.650 s | `1b 21 6f 0d 0a` |
| 4 | 8.487 s | `1b 21 3f 0d 0a` |
| 5 | 0.119 s | `1b 21 6f 0d 0a` |
| 6 | 0.451 s | `1b 21 3f 0d 0a` |
| 7 | 0.213 s | First 512 bytes of the print job |
| 8 | 0.058 s | Next 512 bytes |
| 9 | 0.031 s | Final 410 bytes |

The observed response sequence was battery, config, unknown A, unknown B,
unknown A, unknown B, as above. These pre-print queries and delays were replayed
successfully; their necessity and safe minimum timings are not known. Use the
captured sequence as a conservative starting point, then test deliberately
before changing it. The original captured job can be reconstructed by joining
`hex` of `phone_to_printer` / `write` events 7–9, in order; IDs 1–6 are the
status preamble, not part of the print job.

### Write size and flow control

The phone-side ATT MTU in the relay capture was 517; the printer-side ATT MTU
was 512, so a printer-side write command could carry at most 509 value bytes
(ATT MTU minus 3). The first attempt to forward a 512-byte phone write failed.
The successful relay sent the print job as ordered chunks of `509, 3, 509, 3,
410` bytes; those are BlueZ-accepted chunks, not printer acknowledgements.
This shows that splitting at those boundaries worked for this print.

Never assume a 512-byte write will fit on a different connection. Use the
platform's current maximum write-without-response value length, split the
byte stream accordingly, preserve byte order and obey platform backpressure.
On iOS, use Core Bluetooth's maximum write length for the chosen write type
and its write-without-response readiness mechanism. Recheck on reconnect.
On a disconnect or write failure, report that the job may be partial; blindly
retrying can duplicate or corrupt a print. Successful enqueueing is not a
physical completion signal. No reliable print-complete response was identified.

## Captured print-job format

All commands below are ASCII bytes with CR LF line endings, except that raw
binary raster bytes immediately follow the last comma in `BITMAP`. There is
**no** newline between the comma and the binary image:

```text
SIZE 15 mm,14 mm\r\n
GAP 0,0\r\n
DIRECTION 0,0\r\n
DENSITY 15\r\n
CLS\r\n
BITMAP 0,0,12,112,1,<1344 raw bitmap bytes>\r\n
PRINT 1\r\n
```

The notation `\r\n` means actual bytes `0d 0a`, not four literal characters.
The verified print stream is 1,434 bytes: 79 bytes through the bitmap command's
final comma, 1,344 raster bytes, and the 11-byte `\r\nPRINT 1\r\n` suffix.
In this example, `12` is bytes per raster row and `112` is the row count.
The meaning and valid ranges of all command parameters, including bitmap mode
`1`, `GAP`, `DIRECTION`, and `DENSITY`, have not been independently explored.
Use the captured values for an initial compatible implementation rather than
assuming every printer accepts a generalized command set.

The owner requested a fixed width of 96 pixels with variable height, but the
current implementation and successful capture are **fixed at 96 × 112**.
Changing height requires changing at least the bitmap row count and raster
length, and may also require different physical `SIZE`, spacing, or
calibration. Those relationships are unverified: test variable-height jobs
separately instead of claiming arbitrary heights already work.

### Bitmap representation

- Width: 96 pixels = 12 bytes per row; height: 112 rows.
- Rows are ordered top-to-bottom in the generated image buffer.
- Pixels are packed left-to-right, most significant bit first in each byte:
  pixel `x` uses bit `0x80 >> (x % 8)` of byte `y * 12 + x // 8`.
- Bit `1` means white, `0` means black. An all-white row is twelve `ff`
  bytes; an all-black row is twelve `00` bytes.
- Pack exactly 1,344 image bytes directly into the job, not a BMP/PNG header,
  not ASCII hexadecimal, and not base64. Image bytes may contain zero, CR,
  LF, or bytes resembling commands: use the known raster length, not a
  delimiter search, to find the image end.

[`p22_bitmap.py`](./p22_bitmap.py) exports a conventional 24-bit BMP for
inspection and imports strict black-and-white BMPs, accounting for BMP row
orientation. The BLE raster is not itself a BMP. Physical print orientation
and any required rotation/mirroring should be checked on the actual device.

## Current QR label generation

[`print_qr.py`](./print_qr.py) creates a 1-bit white `96 × 112` image:

1. Require nonempty QR text and exactly five printable ASCII heading
   characters (`0x20` through `0x7e`), including `HP-GR`. Reject control
   characters and non-ASCII headings.
2. Encode the QR text with the Python `qrcode` library, automatic QR version,
   error correction **M**, no generated border, and one matrix cell per module.
   The test suite also checks Unicode QR text. For a different QR encoder,
   verify Unicode encoding and decoding rather than assuming matrix identity.
3. Use a 96 × 96 QR area beginning at image row 16. For an `N × N` QR matrix,
   require `floor(96 / N) >= 2`, otherwise reject the text. Scale each black
   module at column `c`, row `r` into pixel intervals
   `[floor(c*96/N), floor((c+1)*96/N))` horizontally and
   `[16+floor(r*96/N), 16+floor((r+1)*96/N))` vertically.
   This fills the entire width and height without interpolation; adjacent
   module widths may differ by one pixel.
4. Draw the centered heading in the top 16 rows. The default Pillow font is
   size 14; use size 13 if its measured height exceeds 13 pixels. If it still
   cannot fit, reject the label. Align its bounding-box bottom at row 13
   exclusive, leaving rows 13–15 white: a three-pixel gap before the QR.
   Another platform's fonts and rasterization may differ; test legibility and
   ensure no clipping.
5. Pack the resulting monochrome image as described above and replace only
   the 1,344 captured bitmap bytes. The current generator retains the captured
   physical size, print setup, preamble, timing and write partitioning.

**Scanning caveat:** the matrix has no generated QR quiet zone; the design
relies on white space outside the raster supplied by the physical label.
Three pixels between the heading and QR are not necessarily a standard quiet
zone. The tests decode rendered images with an added 16-pixel white exterior,
which does not prove that a physical print is reliably scannable. Do not
interpolate or antialias the QR modules. Test actual labels with multiple
scanners and representative payload lengths.

## Suggested acceptance checks

- Scan and list multiple candidates; handle unavailable Bluetooth, permissions,
  disconnect/reconnect, duplicate names, and a missing `FF00`/`FF01`/`FF02`.
- Enable `FF01` notifications, issue each status query in isolation, record
  exact raw responses, handle timeout/malformed data, and show unknown instead
  of inventing battery or paper values.
- Use fixtures for the four response examples above, including the binary
  `0a` and one-byte `00`; test both known examples and unknown variants.
- Reconstruct the captured job and verify 79-byte header, 1,344-byte bitmap,
  11-byte suffix, exact command bytes, and raster polarity. Verify ordered
  chunking for different maximum write lengths and readiness/backpressure.
- Generate and decode QR labels with a simulated exterior border, including
  `HP-GR`, Unicode QR content, maximum supported size, and too-long rejection;
  check the exact three white rows and ensure heading glyphs are not clipped.
- With the owner's printer, verify paper orientation, physical print, and QR
  scanning. Report transmission separately from confirmed physical completion.
- Gather controlled battery/paper samples and validate mappings before making
  battery percentage or paper type a completed feature.
