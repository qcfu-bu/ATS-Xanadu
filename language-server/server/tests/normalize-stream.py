#!/usr/bin/env python3
# normalize-stream.py <file> — render a server output stream as one line of
# canonical JSON per frame, with $ATS3_REPO occurrences replaced by @X@, so
# goldens are machine-independent.  Framing itself is validated separately
# (check-stream.py); this only canonicalizes the bodies.
import json
import os
import sys

repo = os.environ.get("ATS3_REPO", "")
data = open(sys.argv[1], "rb").read()
i = 0
while i < len(data):
    he = data.find(b"\r\n\r\n", i)
    if he < 0:
        sys.exit("normalize-stream: truncated header")
    clen = None
    for line in data[i:he].decode("ascii", "replace").split("\r\n"):
        if line.lower().startswith("content-length:"):
            clen = int(line.split(":", 1)[1].strip())
    if clen is None:
        sys.exit("normalize-stream: no Content-Length")
    body = data[he + 4 : he + 4 + clen].decode("utf-8")
    if repo:
        body = body.replace(repo, "@X@")
    obj = json.loads(body)
    print(json.dumps(obj, ensure_ascii=False))
    i = he + 4 + clen
