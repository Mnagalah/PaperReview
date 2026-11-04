#!/usr/bin/env python3
"""Pause, parent death, and byte-exact resume using only local small files."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
from download_resume_tests import fixture


def until(predicate, seconds=8):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for the owned download session")


def gone(group):
    # On macOS killpg(..., 0) can return EPERM for departed groups. Inspect
    # live members instead; zombies have no descriptors and cannot write.
    members = subprocess.check_output(["/bin/ps", "-axo", "pgid=,stat="], text=True)
    return not any(int(fields[0]) == group and not fields[1].startswith("Z")
                   for line in members.splitlines() if len(fields := line.split()) == 2)


def partials(home, rows):
    return {r[0]: (home / (r[2] + r[3])).stat().st_size
            for r in rows if (home / (r[2] + r[3])).exists()}


def start(root, home):
    process = subprocess.Popen(["/bin/bash", str(root / "Resources/download_supervisor.sh"),
                                str(root / "Resources/setup_models_modelscope.sh")],
                               env=dict(os.environ, PAPERREVIEW_MODEL_HOME=str(home)),
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    while True:
        line = process.stdout.readline()
        if line.startswith("PR_DOWNLOAD_SESSION\t"):
            return process, int(line.split("\t")[1])
        assert line, "Supervisor exited before the ownership handshake"


with tempfile.TemporaryDirectory(prefix="PaperReview-pause-test-") as temp:
    root = pathlib.Path(temp)
    server, rows, payloads, requests = fixture(root, slow=True)
    (root / "allow-retry").touch()
    home = root / "models"
    try:
        first, group = start(root, home)
        assert group != os.getpgrp()
        until(lambda: sum(partials(home, rows).values()) > 200_000)
        first.stdin.close()
        first.stdin = None
        first.communicate(timeout=8)
        assert first.returncode != 0
        until(lambda: gone(group))
        paused = partials(home, rows)
        time.sleep(0.3)
        assert paused == partials(home, rows), "Pause left a writer running"
        before_resume = len(requests)

        # A separate owner holds the stdin writer, as the native app does.
        owner_code = '''
import json,pathlib,sys,time
sys.path.insert(0, sys.argv[1])
from download_pause_owner import run
run(pathlib.Path(sys.argv[2]))
'''
        owner_module = root / "download_pause_owner.py"
        owner_module.write_text('''
import json,os,subprocess,time
def run(root):
 p=subprocess.Popen(["/bin/bash",str(root/"Resources/download_supervisor.sh"),str(root/"Resources/setup_models_modelscope.sh")],env=dict(os.environ,PAPERREVIEW_MODEL_HOME=str(root/"models")),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 while True:
  line=p.stdout.readline()
  if line.startswith("PR_DOWNLOAD_SESSION\\t"):
   (root/"owner-ready.json").write_text(json.dumps({"group":int(line.split("\\t")[1])}))
   break
  assert line
 while True: time.sleep(0.1)
''')
        owner = subprocess.Popen([sys.executable, "-c", owner_code, str(root), str(root)])
        until(lambda: (root / "owner-ready.json").exists())
        second_group = json.loads((root / "owner-ready.json").read_text())["group"]
        until(lambda: sum(partials(home, rows).values()) > sum(paused.values()) + 100_000)
        owner.kill()
        owner.wait(timeout=3)
        until(lambda: gone(second_group))
        interrupted = partials(home, rows)
        time.sleep(0.3)
        assert interrupted == partials(home, rows), "Owner exit left a writer running"
        assert not (home / "models-ready").exists()
        next_request = len(requests)
        final, final_group = start(root, home)
        final.wait(timeout=40)
        final.stdin.close()
        final.stdout.read()
        assert final.returncode == 0
        until(lambda: gone(final_group))
        for row in rows:
            assert (home / row[2]).read_bytes() == payloads[row[0]]
        for key, count in interrupted.items():
            matches = [r for r in requests[next_request:] if r["id"] == key]
            if count < len(payloads[key]):
                assert matches and matches[0]["offset"] == count, (key, count, matches)
        assert any(r["offset"] == paused.get(r["id"]) for r in requests[before_resume:next_request])
        print("PASS: pause stops every writer; owner death stops its session; both resumes keep exact byte offsets")
    finally:
        server.shutdown()
