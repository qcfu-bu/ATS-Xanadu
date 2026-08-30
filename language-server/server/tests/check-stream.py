#!/usr/bin/env python3
# check-stream.py <file> — INDEPENDENT validation of a server output stream:
# every frame must carry a Content-Length equal to the actual body byte
# count, every body must be valid JSON (per Python's json), and the stream
# must end exactly at a frame boundary.  Exit 0 iff all checks pass.
import json
import sys

data = open(sys.argv[1], "rb").read()
i = 0
nmsg = 0
while i < len(data):
    he = data.find(b"\r\n\r\n", i)
    if he < 0:
        print(f"!! trailing garbage at byte {i}: no header terminator")
        sys.exit(1)
    header = data[i:he].decode("ascii", "replace")
    clen = None
    for line in header.split("\r\n"):
        if line.lower().startswith("content-length:"):
            clen = int(line.split(":", 1)[1].strip())
    if clen is None:
        print(f"!! frame at byte {i}: no Content-Length in {header!r}")
        sys.exit(1)
    body = data[he + 4 : he + 4 + clen]
    if len(body) != clen:
        print(f"!! frame at byte {i}: body truncated ({len(body)} < {clen})")
        sys.exit(1)
    try:
        json.loads(body.decode("utf-8"))
    except Exception as e:
        print(f"!! frame at byte {i}: bad JSON body: {e}")
        sys.exit(1)
    nmsg += 1
    i = he + 4 + clen
print(f">> stream ok: {nmsg} well-formed frames")
