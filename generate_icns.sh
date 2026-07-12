#!/bin/bash
IMAGE=$1
mkdir MyIcon.iconset
sips -s format png -z 16 16     "$IMAGE" --out MyIcon.iconset/icon_16x16.png
sips -s format png -z 32 32     "$IMAGE" --out MyIcon.iconset/icon_16x16@2x.png
sips -s format png -z 32 32     "$IMAGE" --out MyIcon.iconset/icon_32x32.png
sips -s format png -z 64 64     "$IMAGE" --out MyIcon.iconset/icon_32x32@2x.png
sips -s format png -z 128 128   "$IMAGE" --out MyIcon.iconset/icon_128x128.png
sips -s format png -z 256 256   "$IMAGE" --out MyIcon.iconset/icon_128x128@2x.png
sips -s format png -z 256 256   "$IMAGE" --out MyIcon.iconset/icon_256x256.png
sips -s format png -z 512 512   "$IMAGE" --out MyIcon.iconset/icon_256x256@2x.png
sips -s format png -z 512 512   "$IMAGE" --out MyIcon.iconset/icon_512x512.png
sips -s format png -z 1024 1024 "$IMAGE" --out MyIcon.iconset/icon_512x512@2x.png
iconutil -c icns MyIcon.iconset -o AppIcon.icns
rm -rf MyIcon.iconset
