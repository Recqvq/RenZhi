#!/usr/bin/env python3
"""Heuristic release hygiene check. Never prints matched secret values."""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0")
checks = {
    "home-directory path": re.compile(rb"/" + rb"Users/[A-Za-z0-9_.-]+/"),
    "JWT literal": re.compile(rb"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}"),
    "GitHub credential": re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"),
    "private key": re.compile(rb"-----BEGIN " + rb"(?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "encoded identity URL": re.compile(rb"stuempNo=[A-Za-z0-9_%+-]{24,}"),
}
failures = []
for raw in paths:
    if not raw:
        continue
    relative = raw.decode()
    if relative.startswith("dist/") or relative.endswith((".dmg", ".zip", ".log", ".db", ".sqlite", ".dSYM")):
        failures.append((relative, "generated artifact or local data tracked"))
    data = (ROOT / relative).read_bytes()
    for label, pattern in checks.items():
        if pattern.search(data):
            failures.append((relative, label))
app = ROOT / "dist/认知统计.app"
if app.exists():
    for path in app.rglob("*"):
        if path.is_file():
            for label, pattern in checks.items():
                if pattern.search(path.read_bytes()):
                    failures.append((str(path.relative_to(ROOT)), label))
if failures:
    for name, label in failures:
        print(f"FAIL: {name}: {label} (value withheld)")
    sys.exit(1)
print("PASS: tracked files and available app checked; no heuristic privacy matches")
