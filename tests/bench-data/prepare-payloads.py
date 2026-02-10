#!/usr/bin/env python3
"""Pre-process telnet log payloads into clean text for benchmarking.

Reads recv-*.txt files (raw log payloads with escaped characters),
unescapes them, strips ANSI codes, and writes clean-*.txt files
that represent what collect-words-from-text actually receives.
"""

import re
import sys
from pathlib import Path

HERE = Path(__file__).parent


def unescape_log(text: str) -> str:
    """Unescape telnet log encoding: \\n -> newline, \\r -> CR, \\xNN -> byte."""
    result = []
    i = 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            c = text[i + 1]
            if c == "n":
                result.append("\n")
                i += 2
            elif c == "r":
                result.append("\r")
                i += 2
            elif c == "x" and i + 3 < len(text):
                hex_str = text[i + 2 : i + 4]
                try:
                    result.append(chr(int(hex_str, 16)))
                    i += 4
                except ValueError:
                    result.append(text[i])
                    i += 1
            elif c == "\\":
                result.append("\\")
                i += 2
            else:
                result.append(text[i])
                i += 1
        else:
            result.append(text[i])
            i += 1
    return "".join(result)


def strip_ansi(text: str) -> str:
    """Strip ANSI escape sequences (same as C strip_ansi_codes)."""
    return re.sub(r"\033\[[0-9;]*[A-Za-z]", "", text)


def strip_iac(text: str) -> str:
    """Strip telnet IAC sequences."""
    return re.sub(r"<IAC>[^\s]*", "", text)


def process_payload(name: str) -> None:
    src = HERE / f"recv-{name}.txt"
    dst = HERE / f"clean-{name}.txt"

    raw = src.read_text()
    # Unescape log encoding
    unescaped = unescape_log(raw)
    # Strip IAC markers
    no_iac = strip_iac(unescaped)
    # Strip ANSI escape sequences
    clean = strip_ansi(no_iac)
    # Remove carriage returns (C strips these in telnet receive)
    clean = clean.replace("\r", "")

    dst.write_text(clean)
    word_count = len([w for w in clean.split() if len(w) >= 1])
    print(
        f"  {src.name} ({len(raw)} bytes) -> {dst.name} ({len(clean)} bytes, ~{word_count} words)"
    )


def main():
    print("Preparing clean payloads for benchmark...")
    for name in ["200", "500", "1k", "2k", "4k", "5k"]:
        src = HERE / f"recv-{name}.txt"
        if src.exists():
            process_payload(name)
        else:
            print(f"  SKIP: {src.name} not found")
    print("Done.")


if __name__ == "__main__":
    main()
