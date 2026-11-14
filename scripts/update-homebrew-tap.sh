#!/bin/sh
set -eu

version=${1:?usage: update-homebrew-tap.sh VERSION [DIST_DIR] [--publish]}
version=${version#v}
dist=${2:-dist/packages/$version}
publish=${3:-}
if [ "$#" -gt 3 ] || { [ -n "$publish" ] && [ "$publish" != --publish ]; }; then
  echo 'Expected VERSION [DIST_DIR] [--publish]' >&2
  exit 2
fi
if ! printf '%s\n' "$version" | LC_ALL=C grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
  echo 'Expected a stable X.Y.Z version' >&2
  exit 2
fi

tarball="snapclip_${version}_darwin_universal.tar.gz"
checksums="$dist/SHA256SUMS"
if [ ! -f "$checksums" ]; then
  echo "Missing $checksums" >&2
  exit 1
fi

sha256=$(awk -v asset="$tarball" '
  $2 == asset { count++; hash=$1 }
  END {
    if (count != 1 || length(hash) != 64 || hash ~ /[^a-fA-F0-9]/) exit 1
    print hash
  }' "$checksums" || {
    echo "Missing, duplicate, or invalid checksum for $tarball in $checksums" >&2
    exit 1
  })

formula="${dist%/}/snapclip.rb"
cat > "$formula" <<EOF
class Snapclip < Formula
  desc "Copy macOS screenshots to the clipboard, Desktop, and a floating preview"
  homepage "https://github.com/aklkbqx/snapclip"
  version "$version"
  url "https://github.com/aklkbqx/snapclip/releases/download/v$version/$tarball"
  sha256 "$sha256"
  license "MIT"

  depends_on macos: :sonoma

  def install
    bin.install "snapclip"
  end

  def caveats
    <<~EOS
      Configure macOS screencapture staging and start the LaunchAgent:
        snapclip install
    EOS
  end

  test do
    assert_match "$version", shell_output("#{bin}/snapclip version")
  end
end
EOF

[ "$publish" = --publish ] || exit 0

tap_dir="${HOMEBREW_TAP_DIR:-}"
if [ -z "$tap_dir" ] && command -v brew >/dev/null 2>&1; then
  tap_dir="$(brew --repository aklkbqx/snapclip 2>/dev/null || true)"
fi
if [ -z "$tap_dir" ] || [ ! -d "$tap_dir" ] || ! git -C "$tap_dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo 'Homebrew tap Git directory not found; publication aborted' >&2
  exit 1
fi
if [ "$(git -C "$tap_dir" branch --show-current)" != main ] || [ -n "$(git -C "$tap_dir" status --porcelain)" ]; then
  echo 'Homebrew tap must be on main with a clean working tree and index; publication aborted' >&2
  exit 1
fi
git -C "$tap_dir" fetch --no-tags origin main
remote_tip=$(git -C "$tap_dir" rev-parse FETCH_HEAD)
if ! git -C "$tap_dir" merge-base --is-ancestor "$remote_tip" HEAD; then
  echo 'Homebrew tap is behind or diverged from origin main; publication aborted' >&2
  exit 1
fi
pending_files=$(git -C "$tap_dir" log --format= --name-only -m "$remote_tip..HEAD")
if printf '%s\n' "$pending_files" | LC_ALL=C grep -Ev '^$|^Formula/snapclip\.rb$' >/dev/null; then
  echo 'Homebrew tap has unrelated unpublished commits; publication aborted' >&2
  exit 1
fi
mkdir -p "$tap_dir/Formula"
cp "$formula" "$tap_dir/Formula/snapclip.rb"
git -C "$tap_dir" add -- Formula/snapclip.rb
if ! git -C "$tap_dir" diff --cached --quiet; then
  git -C "$tap_dir" commit -m "chore: update formula for v$version" -- Formula/snapclip.rb
fi
git -C "$tap_dir" push origin main
echo "Published Homebrew formula for v$version"
