#!/usr/bin/env python3
"""Simple development web server for the Passiflora WWW target.

Run from the project root:
    python3 webserver.py

Then open http://localhost:8000 in your browser.
"""

import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin", "WWW")

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

if __name__ == "__main__":
    with http.server.HTTPServer(("", PORT), Handler) as httpd:
        print(f"Serving bin/WWW/ at http://localhost:{PORT}")
        print("Press Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
