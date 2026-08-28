#!/usr/bin/env python3
# feed.py <case.jsonl> [--chunk N] [--delay MS] — frame each nonblank line of
# the case file as one LSP base-protocol message (Content-Length header, byte
# count of the UTF-8 body) and write the stream to stdout; --chunk dribbles
# the bytes N at a time (with --delay ms between writes) to exercise the
# server's incremental framing across short reads.
import sys
import time

args = sys.argv[1:]
path = args[0]
chunk = 0
delay = 0.0
if "--chunk" in args:
    chunk = int(args[args.index("--chunk") + 1])
if "--delay" in args:
    delay = int(args[args.index("--delay") + 1]) / 1000.0

out = b""
for line in open(path, "rb").read().split(b"\n"):
    if not line.strip():
        continue
    out += b"Content-Length: %d\r\n\r\n" % len(line) + line

w = sys.stdout.buffer
if chunk <= 0:
    w.write(out)
else:
    for i in range(0, len(out), chunk):
        w.write(out[i : i + chunk])
        w.flush()
        if delay:
            time.sleep(delay)
