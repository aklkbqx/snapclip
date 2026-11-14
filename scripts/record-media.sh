#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

for tool in swift ffmpeg vhs; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: '$tool' is required for media rendering" >&2
    exit 1
  fi
done

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/snapclip-media-XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/bin" "$WORK_DIR/home" "$WORK_DIR/docs/assets" "$ROOT_DIR/docs/assets" "$ROOT_DIR/dist/media"

echo "==> Building release snapclip binary..."
make build >/dev/null
cp "$ROOT_DIR/dist/snapclip" "$WORK_DIR/bin/snapclip"
chmod 755 "$WORK_DIR/bin/snapclip"

echo "==> Rendering desktop showcase animation..."
RAW_PATH="$WORK_DIR/showcase.rgba"
swift "$ROOT_DIR/scripts/render-showcase.swift" \
  --raw-out "$RAW_PATH" \
  --poster "$ROOT_DIR/docs/assets/showcase.png"

ffmpeg -v error -y \
  -f rawvideo -pixel_format rgba -video_size 1920x1080 -framerate 25 -i "$RAW_PATH" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  "$ROOT_DIR/dist/media/showcase.mp4"

ffmpeg -v error -y -i "$ROOT_DIR/dist/media/showcase.mp4" \
  -vf "fps=25,scale=960:540:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=256:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
  -loop 0 \
  "$ROOT_DIR/docs/assets/showcase.gif"

echo "==> Recording CLI demo via vhs..."
(
  export PATH="$WORK_DIR/bin:$PATH"
  export HOME="$WORK_DIR/home"
  export TERM="xterm-256color"
  unset NO_COLOR
  export COLORTERM="truecolor"
  export TZ="UTC"
  cd "$WORK_DIR"
  vhs "$ROOT_DIR/scripts/tapes/cli.tape"
)

cp -f "$WORK_DIR/docs/assets/cli.gif" "$ROOT_DIR/docs/assets/cli.gif"
cp -f "$WORK_DIR/docs/assets/cli.mp4" "$ROOT_DIR/dist/media/cli.mp4"

echo "==> Media assets updated:"
ls -lh "$ROOT_DIR/docs/assets/"* "$ROOT_DIR/dist/media/"*.mp4
