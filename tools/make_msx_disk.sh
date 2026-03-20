#!/bin/bash
# MSX-DOS Disk Image Builder
# Creates a bootable MSX-DOS disk with music player and data files

set -e

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$TOOLS_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DATA_DIR="$PROJECT_DIR/data"
MSX_DIR="$PROJECT_DIR/msx"

# MSX-DOS base image
BASE_IMAGE="$TOOLS_DIR/msxdos103-111hf clean.dsk"
OUTPUT_IMAGE="$BUILD_DIR/msx-music.dsk"

# Check if base image exists
if [ ! -f "$BASE_IMAGE" ]; then
    echo "Error: Base MSX-DOS image not found: $BASE_IMAGE"
    exit 1
fi

# Check if player exists
if [ ! -f "$BUILD_DIR/PLAYER.COM" ]; then
    echo "Error: PLAYER.COM not found. Run 'make msx-player' first."
    exit 1
fi

# Create output directory
mkdir -p "$BUILD_DIR"

# Copy base image
echo "Creating MSX-DOS disk image..."
cp "$BASE_IMAGE" "$OUTPUT_IMAGE"
chmod 644 "$OUTPUT_IMAGE"

# Copy player
echo "Copying PLAYER.COM..."
mcopy -i "$OUTPUT_IMAGE" "$BUILD_DIR/PLAYER.COM" ::PLAYER.COM

# Copy MPS files
echo "Copying music files..."
for mps in "$DATA_DIR"/*.MPS; do
    if [ -f "$mps" ]; then
        filename=$(basename "$mps")
        echo "  - $filename"
        mcopy -i "$OUTPUT_IMAGE" "$mps" ::"$filename"
    fi
done

# Copy SONGLIST.TXT if exists
if [ -f "$MSX_DIR/SONGLIST.TXT" ]; then
    echo "Copying SONGLIST.TXT..."
    mcopy -i "$OUTPUT_IMAGE" "$MSX_DIR/SONGLIST.TXT" ::SONGLIST.TXT
fi

# List disk contents
echo ""
echo "Disk contents:"
mdir -i "$OUTPUT_IMAGE" ::

echo ""
echo "MSX-DOS disk created: $OUTPUT_IMAGE"
echo ""
echo "To test in openMSX:"
echo "  openmsx -machine Panasonic_FS-A1GT -diska \"$OUTPUT_IMAGE\""
echo ""
echo "In MSX-DOS, run:"
echo "  PLAYER TITLE.MPS"
