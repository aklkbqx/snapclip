#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

if [ -d .github ]; then
    echo "error: .github directory is disallowed" >&2
    exit 1
fi

swift test
make build

./dist/snapclip version >/dev/null
./dist/snapclip --help >/dev/null
./dist/snapclip config show >/dev/null
./dist/snapclip donate --json >/dev/null

python3 - <<'PY'
import pathlib, re, sys

root = pathlib.Path(".")
errors = []

skip_dirs = {".build", ".build-universal", ".git", ".swiftpm", "dist", "site", "promo"}
files = [
    p for p in sorted(root.rglob("*"))
    if p.is_file()
    and not any(part in skip_dirs for part in p.parts)
    and p.suffix in {".md", ".swift", ".sh"}
]

private_home_re = re.compile(r"/Users/[^/]+")
private_handle_re = re.compile(r"akalak" + r"(?:kruaboon)?", re.IGNORECASE)

for path in files:
    if path.name == "verify.sh":
        continue
    content = path.read_text(encoding="utf-8")
    if private_home_re.search(content):
        errors.append(f"{path}: contains hardcoded /Users/<name> path")
    if private_handle_re.search(content):
        errors.append(f"{path}: contains personal identifier outside public handle")

if errors:
    for err in errors:
        print(f"hygiene error: {err}", file=sys.stderr)
    sys.exit(1)
print("hygiene checks passed")
PY

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git diff --check
fi
