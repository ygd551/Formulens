"""Isolated HTTP boundary fixture: no ML, downloads, user data or real keys."""
import http.server
import json
import sys
import time

port, behavior = int(sys.argv[1]), sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer fixture":
            self.respond(401, {})
        else:
            self.respond(200, {"status": "healthy"})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if behavior == "slow":
            time.sleep(10)
        if behavior == "failure":
            self.respond(500, {"error": "fixture model cannot load"})
        elif body.get("model") != sys.argv[3]:
            self.respond(400, {"error": "wrong selected model path"})
        elif behavior == "table":
            self.respond(200, {"choices": [{"message": {"content": "| a | b |\n| --- | --- |\n| 1 | 2 |"}}]})
        else:
            self.respond(200, {"choices": [{"message": {"content": "x^2+1"}}]})

http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
