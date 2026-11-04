#!/usr/bin/env python3
"""Exercise the bundled scripts against an interrupting local HTTP server."""
import argparse
import io
import json
import pathlib
import shutil
import subprocess
import tarfile
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROJECT = pathlib.Path(__file__).resolve().parents[2]


def fixture(root, slow=False):
    resources = root / "Resources"
    resources.mkdir(parents=True)
    for name in ("setup_models_modelscope.sh", "install_runtime.sh", "download_file.sh"):
        shutil.copy(PROJECT / "script" / name, resources)
    rows = [line.split("\t") for line in (PROJECT / "script/model_downloads.tsv").read_text().splitlines()]
    payloads = {}
    for row in rows:
        payloads[row[0]] = (b"PaperReview synthetic download fixture.\n" * (30000 if slow else 400))
    archive = io.BytesIO()
    with tarfile.open(fileobj=archive, mode="w:gz", compresslevel=0) as tar:
        for name, data, mode in [("llama-fixture/llama-server", b"#!/bin/sh\nexit 0\n", 0o755),
                                 ("llama-fixture/test-data", b"x" * (2_000_000 if slow else 20000), 0o644)]:
            member = tarfile.TarInfo(name)
            member.size, member.mode = len(data), mode
            tar.addfile(member, io.BytesIO(data))
    payloads["runtime"] = archive.getvalue()
    requests = []
    runtime_interrupted = False

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            nonlocal runtime_interrupted
            key = self.path.strip("/")
            data = payloads[key]
            offset = int(self.headers.get("Range", "bytes=0-").split("=")[1].split("-")[0])
            requests.append({"id": key, "offset": offset})
            (root / "requests.json").write_text(json.dumps(requests))
            if key == "ocr" and offset and not (root / "allow-retry").exists():
                self.send_error(503, "Fixture temporarily offline")
                return
            self.send_response(206 if offset else 200)
            self.send_header("Content-Length", str(len(data) - offset))
            if offset:
                self.send_header("Content-Range", f"bytes {offset}-{len(data)-1}/{len(data)}")
            self.end_headers()
            cut = (128 * 1024 if slow else 4096)
            if key == "ocr" and offset == 0 and not (root / "allow-retry").exists():
                self.wfile.write(data[:cut])
                self.wfile.flush()
                self.close_connection = True
                return
            if key == "runtime" and not runtime_interrupted and not slow:
                runtime_interrupted = True
                self.wfile.write(data[:4096])
                self.wfile.flush()
                self.close_connection = True
                return
            try:
                for index in range(offset, len(data), 32768):
                    self.wfile.write(data[index:index + 32768])
                    self.wfile.flush()
                    if slow:
                        time.sleep(0.12)
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    for row in rows:
        row[4] = str(len(payloads[row[0]]))
        row[5] = f"http://127.0.0.1:{server.server_port}/{row[0]}"
    (resources / "model_downloads.tsv").write_text("".join("\t".join(row) + "\n" for row in rows))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, rows, payloads, requests


def run_test():
    with tempfile.TemporaryDirectory(prefix="PaperReview-download-test-") as temp:
        root = pathlib.Path(temp)
        server, rows, payloads, requests = fixture(root)
        try:
            home = root / "models"
            script = root / "Resources/setup_models_modelscope.sh"
            import os
            env = dict(os.environ, PAPERREVIEW_MODEL_HOME=str(home))
            # A fully transferred partial must be promoted without another GET.
            cached = rows[1]
            partial = home / (cached[2] + cached[3])
            partial.parent.mkdir(parents=True)
            partial.write_bytes(payloads[cached[0]])
            failed = subprocess.run(["/bin/bash", str(script)], env=env, capture_output=True, text=True, timeout=45)
            assert failed.returncode != 0, failed.stdout
            assert "PR_DOWNLOAD\tocr\tfailed\t6\t" in failed.stdout
            ocr = home / (rows[0][2] + rows[0][3])
            assert ocr.read_bytes() == payloads["ocr"][:4096]
            assert not (home / "models-ready").exists()
            before = list(requests)
            assert not any(r["id"] == cached[0] for r in before)
            (root / "allow-retry").touch()
            success = subprocess.run(["/bin/bash", str(script)], env=env, capture_output=True, text=True, timeout=30)
            assert success.returncode == 0, success.stdout + success.stderr
            assert (home / "models-ready").exists()
            resumed = requests[len(before):]
            assert {r["id"] for r in resumed} == {"ocr", "runtime"}, resumed
            assert next(r for r in resumed if r["id"] == "ocr")["offset"] == 4096
            assert any(r["id"] == "runtime" and r["offset"] == 4096 for r in resumed)
            for row in rows:
                assert (home / row[2]).read_bytes() == payloads[row[0]], row[0]
            assert "PR_DOWNLOAD\truntime\tinstalling\t0\t" in success.stdout
            assert "PR_DOWNLOAD\truntime\tcomplete\t0\t" in success.stdout
            print("PASS: visible retries, terminal failure, exact resumed bytes, cached-file skipping, runtime resume and installation")
        finally:
            server.shutdown()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--serve", type=pathlib.Path, help="Retain a slow native UI fixture until interrupted")
    args = parser.parse_args()
    if args.serve:
        args.serve.mkdir(parents=True, exist_ok=True)
        server, *_ = fixture(args.serve, slow=True)
        print(json.dumps({"root": str(args.serve), "port": server.server_port}), flush=True)
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            server.shutdown()
    else:
        run_test()
