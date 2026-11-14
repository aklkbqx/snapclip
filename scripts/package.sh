#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

version=$(sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' Sources/SnapClipCLI/SnapClipCLI.swift)
[ -n "$version" ] || { echo "Cannot determine version from SnapClipCLI.swift" >&2; exit 1; }

out="dist/packages/$version"
mkdir -p "$out"

swift build -c release --scratch-path .build-universal --arch arm64 --arch x86_64
bin_path="$(swift build -c release --scratch-path .build-universal --arch arm64 --arch x86_64 --show-bin-path)/snapclip"
mkdir -p dist
cp "$bin_path" dist/snapclip
chmod 755 dist/snapclip
codesign --force --sign - --identifier com.aklkbqx.snapclip dist/snapclip

tarball="snapclip_${version}_darwin_universal.tar.gz"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp dist/snapclip "$stage/snapclip"
cp LICENSE "$stage/LICENSE"
cp README.md "$stage/README.md"
tar -C "$stage" -czf "$out/$tarball" snapclip LICENSE README.md

sha256=$(shasum -a 256 "$out/$tarball" | awk '{print $1}')
(
    cd "$out"
    shasum -a 256 "$tarball" > SHA256SUMS
)

sh scripts/update-homebrew-tap.sh "$version" "$out"

echo "Packaged: $out/$tarball"
echo "Binary:   $(lipo -archs dist/snapclip)"
echo "Checksum: $sha256"
echo "Formula:  $out/snapclip.rb"

make build >/dev/null
