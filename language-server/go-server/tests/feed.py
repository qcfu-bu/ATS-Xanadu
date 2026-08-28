#!/usr/bin/env python3
# feed.py <case.jsonl> [--chunk N] [--delay MS] — frame each nonblank line of
# the case file as one LSP base-protocol message (Content-Length header, byte
# count of the UTF-8 body) and write the stream to stdout.
#
# Directives and substitutions:
#   - a line `#sleep MS` flushes what has accumulated and sleeps (lets an
#     async server action — a spawned check — finish before the next message);
#   - `@X@` in a body is replaced with $ATS3_REPO (machine-independent cases);
#   - --chunk dribbles the bytes N at a time (with --delay ms between writes)
#     to exercise incremental framing across short reads.
import os
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

repo = os.environ.get("ATS3_REPO", "")
w = sys.stdout.buffer


def emit(data):
    if chunk <= 0:
        w.write(data)
        w.flush()
        return
    for i in range(0, len(data), chunk):
        w.write(data[i : i + chunk])
        w.flush()
        if delay:
            time.sleep(delay)


for line in open(path, "rb").read().split(b"\n"):
    if not line.strip():
        continue
    if line.startswith(b"#sleep "):
        time.sleep(int(line.split()[1]) / 1000.0)
        continue
    body = line.replace(b"@X@", repo.encode())
    emit(b"Content-Length: %d\r\n\r\n" % len(body) + body)
