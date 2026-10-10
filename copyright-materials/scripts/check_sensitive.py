#!/usr/bin/env python3
"""Fail-closed local scan for generated copyright materials.

It intentionally scans only the material output directory by default.  Source
code contains legitimate words such as ``password`` and ``apiKey`` in storage
logic, so a broad repository grep would produce noise and is not a substitute
for checking the final PDF chosen by the applicant.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TARGET = ROOT / "copyright-materials" / "generated"
PATTERNS = {
    "private-key": re.compile(r"BEGIN (?:RSA|OPENSSH|EC|DSA) PRIVATE KEY"),
    "deepseek-key-shape": re.compile(r"(?i)sk-[a-z0-9]{12,}"),
    "secret-assignment": re.compile(
        r"(?i)(?:password|passwd|secret|api[_-]?key|token)\s*[:=]\s*[\"'][^\"']{8,}[\"']"
    ),
    "bearer-token": re.compile(r"(?i)Bearer\s+[A-Za-z0-9._-]{16,}"),
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", nargs="?", type=Path, default=DEFAULT_TARGET)
    args = parser.parse_args()
    target = args.target if args.target.is_absolute() else ROOT / args.target
    findings: list[dict[str, object]] = []
    for path in sorted(p for p in target.rglob("*") if p.is_file()):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for name, pattern in PATTERNS.items():
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                findings.append({"file": path.relative_to(ROOT).as_posix(), "pattern": name, "line": line})
    report = {"target": target.relative_to(ROOT).as_posix(), "findings": findings, "pass": not findings}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit(0 if report["pass"] else 1)


if __name__ == "__main__":
    main()
