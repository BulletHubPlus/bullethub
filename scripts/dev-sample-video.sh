#!/usr/bin/env sh
# Generates the dev-only sample video played when the media provider is Fake
# (no Bunny credentials). Served at /dev/sample.mp4; never shipped in the image.
set -e
out="$(dirname "$0")/../backend/priv/static/dev/sample.mp4"
mkdir -p "$(dirname "$out")"
ffmpeg -loglevel error -y \
  -f lavfi -i "testsrc2=size=854x480:rate=24:duration=150" \
  -f lavfi -i "sine=frequency=330:duration=150" \
  -vf "drawtext=text='bullethub dev sample  %{pts\\:hms}':fontcolor=white:fontsize=30:x=(w-tw)/2:y=h-70:box=1:boxcolor=black@0.6" \
  -c:v libx264 -preset veryfast -crf 38 -pix_fmt yuv420p -c:a aac -b:a 48k -movflags +faststart "$out"
echo "wrote $out"
