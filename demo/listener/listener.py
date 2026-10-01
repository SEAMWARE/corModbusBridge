#
# FILE            listener.py
#
# AUTHOR          Ken Zangelin
#
# Copyright 2026 Seamware
# SPDX-License-Identifier: Apache-2.0
#
# A notification receiver for the demo: prints every notification it gets, one line per entity.
#
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try:
            for e in json.loads(body).get("data", []):
                attrs = {k: (v.get("value") if isinstance(v, dict) else v) for k, v in e.items() if k not in ("id", "type")}
                print("NOTIFICATION", e.get("id"), json.dumps(attrs), flush=True)
        except ValueError:
            print("NOTIFICATION (not JSON)", body[:200], flush=True)
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


print("listener: waiting for notifications on :8000", flush=True)
HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
