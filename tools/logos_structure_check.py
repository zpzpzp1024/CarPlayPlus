#!/usr/bin/env python3
"""Lightweight structural pre-flight for CarPlayPlus.xm (Logos).

The authoritative check runs `theos/bin/logos.pl` in CI on macOS; this script
catches the most common mistakes locally (Windows has no working Logos/Perl):

  * unbalanced %group / %end or %hook / %end blocks
  * unknown %init(group) references
  * %orig used outside a %hook block
  * suspicious extra %end after a hook/group that is already closed
"""
import re
import sys
from pathlib import Path


def main(path: Path) -> int:
    text = path.read_text(encoding="utf-8", errors="replace")
    errors: list[str] = []
    groups: set[str] = set()
    inits: list[str] = []
    stack: list[tuple[str, str, int]] = []  # (kind, name, lineno)

    # Strip comments so directives inside /* */ or // are ignored.
    text_no_comments = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text_no_comments = re.sub(r"//[^\n]*", "", text_no_comments)

    for lineno, line in enumerate(text_no_comments.splitlines(), 1):
        m = re.search(r"%group\s+(\w+)", line)
        if m:
            groups.add(m.group(1))
            stack.append(("group", m.group(1), lineno))
            continue
        m = re.search(r"%end\b", line)
        if m:
            if not stack:
                errors.append(f"{lineno}: orphan %end (no open %group/%hook)")
            else:
                kind, name, _ = stack.pop()
                if kind == "group":
                    pass  # group closed
                elif kind == "hook":
                    pass  # hook closed
            continue
        m = re.search(r"%hook\s+(\w+)", line)
        if m:
            stack.append(("hook", m.group(1), lineno))
            continue
        m = re.search(r"%init\(\s*(\w+)\s*\);", line)
        if m:
            inits.append(m.group(1))
        m = re.search(r"%orig", line)
        if m and not any(k == "hook" for k, _, _ in stack):
            errors.append(f"{lineno}: %orig used outside of a %hook block")

    for kind, name, lineno in stack:
        errors.append(f"{lineno}: unclosed %{kind} {name} (missing %end)")

    for init in inits:
        if init not in groups:
            errors.append(f"%init({init}) references an unknown %group")

    if errors:
        print("LOGOS STRUCTURE CHECK FAILED:")
        for e in errors:
            print("  - " + e)
        return 1

    print(
        f"LOGOS STRUCTURE OK: {len(groups)} groups, "
        f"{len(inits)} %init, all blocks balanced"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else "Tweak/CarPlayPlus.xm")))