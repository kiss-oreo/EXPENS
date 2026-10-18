#!/usr/bin/env python3
"""Build the sample statement PDFs from the text files in samples/.

The text files are the source of truth. This only wraps each non-comment
line in a FlateDecode content stream so the on-device extractor has a
compressed PDF to read. It does not invent rows.
"""

import pathlib
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def lines_of(path):
    rows = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        rows.append(line)
    return rows


def pdf_bytes(lines):
    parts = ["BT", "/F1 11 Tf", "40 760 Td"]
    for index, line in enumerate(lines):
        if index:
            parts.append("0 -16 Td")
        escaped = (
            line.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
        )
        parts.append(f"({escaped}) Tj")
    parts.append("ET")
    raw = ("\n".join(parts) + "\n").encode("latin1")
    stream = zlib.compress(raw)
    contents = (
        f"<< /Length {len(stream)} /Filter /FlateDecode >>\nstream\n".encode(
            "ascii"
        )
        + stream
        + b"\nendstream"
    )
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        contents,
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for number, obj in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n".encode("ascii")
        out += obj
        out += b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode("ascii")
    out += b"0000000000 65535 f \n"
    for offset in offsets[1:]:
        out += f"{offset:010d} 00000 n \n".encode("ascii")
    out += (
        f"trailer << /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref}\n%%EOF\n"
    ).encode("ascii")
    return bytes(out)


def main():
    samples = ROOT / "samples"
    for name in ("gpay_statement", "phonepe_statement"):
        text = samples / f"{name}.txt"
        target = samples / f"{name}.pdf"
        target.write_bytes(pdf_bytes(lines_of(text)))
        print(f"wrote {target} ({target.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
