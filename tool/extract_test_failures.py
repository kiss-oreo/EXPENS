#!/usr/bin/env python3
"""Pull failed Flutter JSON-reporter tests into a short file.

The full test log is too long to read back from a check-run body. This keeps
only the names and errors.
"""

import json
import sys
from pathlib import Path


def main() -> None:
    src = Path(sys.argv[1])
    dest = Path(sys.argv[2])
    names = {}
    errors = {}
    if src.exists():
        for line in src.read_text(errors="replace").splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            kind = event.get("type")
            if kind == "testStart":
                test = event.get("test") or {}
                names[event.get("testID")] = test.get("name") or test.get("url")
            elif kind == "error":
                test_id = event.get("testID")
                message = event.get("error") or event.get("message") or ""
                errors.setdefault(test_id, []).append(str(message)[:1500])
    lines = []
    for test_id, messages in errors.items():
        title = names.get(test_id) or f"test {test_id}"
        lines.append(f"FAILED {title}")
        lines.extend(messages)
        lines.append("")
    if not lines:
        lines.append("No structured test failures were recorded.")
    dest.write_text("\n".join(lines))


if __name__ == "__main__":
    main()
