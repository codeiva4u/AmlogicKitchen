#!/bin/bash

set -e

# Add bin/ to LD_LIBRARY_PATH if not already present
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
[[ ":$LD_LIBRARY_PATH:" != *":$ROOT_DIR/bin:"* ]] && export LD_LIBRARY_PATH="$ROOT_DIR/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

USE_SPARSE=false
USE_RESIZE=false
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) USE_SPARSE=true ;;  # Enable sparse image
        -r) USE_RESIZE=true ;;  # Enable resize2fs
        *)  ARGS+=("$1") ;;
    esac
    shift
done

PART=${ARGS[0]}
SIZE=${ARGS[1]}
INPUT_DIR=${ARGS[2]}
# --- FIX: ARGS[3] was the output, but callers only pass 3 positional args ---
# Call pattern from amlpack.sh:   make_image.sh -s "system" "size" "level2/system/" "level1/system.PARTITION"
# Call pattern from make_super.sh: make_image.sh -r system msize level2/system level2/system.img
# So OUTPUT_IMG is ARGS[3]
OUTPUT_IMG=${ARGS[3]}

FS="level2/config/${PART}_fs_config"
FC="level2/config/${PART}_file_contexts"
TEMP_IMG="$(dirname "$OUTPUT_IMG")/temp_$(basename "$OUTPUT_IMG")"

# --- FIX: Determine original image type from saved metadata ---
ORIG_TYPE=""
if [[ -f "level2/config/${PART}_imgtype.txt" ]]; then
    ORIG_TYPE=$(cat "level2/config/${PART}_imgtype.txt" 2>/dev/null)
fi

# --- FIX: Use original raw size if available, otherwise use passed SIZE ---
ORIG_RAW_SIZE=""
if [[ -f "level2/config/${PART}_raw_size.txt" ]]; then
    ORIG_RAW_SIZE=$(cat "level2/config/${PART}_raw_size.txt" 2>/dev/null)
fi

# Determine the size to use for ext4 filesystem creation
if [[ -n "$ORIG_RAW_SIZE" && "$ORIG_RAW_SIZE" -gt 0 ]] 2>/dev/null; then
    if [[ $USE_RESIZE == true ]]; then
        # When resize2fs -M is going to be run, we can safely pad the size (10%) to prevent
        # "out of space" block allocation errors in make_ext4fs.
        EXT4_SIZE=$(echo "$ORIG_RAW_SIZE" | awk '{printf "%.0f", $1 * 1.10}')
    else
        # --- CRITICAL BUG FIX ---
        # When USE_RESIZE is false (non-super Amlogic repacks), we MUST NOT use the inflated 
        # _raw_size.txt directly if we are building a SPARSE image! The raw size includes fully
        # allocated 0x00 sectors mathematically. But we want the exact footprint matching the ZIP.
        # Fall back to the passed '$SIZE' parameter (which is the actual original sparse file size)!
        EXT4_SIZE="$SIZE"
    fi
else
    EXT4_SIZE="$SIZE"
fi

if [[ "$ORIG_TYPE" == "erofs" ]]; then
    # EROFS: use mkfs.erofs with original settings
    echo "  -> Building EROFS image for $PART"
    bin/mkfs.erofs -zlz4hc --mount-point "/$PART" --fs-config-file "$FS" --file-contexts "$FC" "$TEMP_IMG" "level2/$PART"
else
    # EXT4: use make_ext4fs with padded original size
    echo "  -> Building EXT4 image for $PART (allocated size: $EXT4_SIZE)"
    FLAGS="-J -L $PART -T -1 -S $FC -C $FS -l $EXT4_SIZE -a $PART"

    # --- FIX: Generate sparse output only if explicitly requested (-s) ---
    # We do NOT want to use $ORIG_TYPE=="sparse" if -r (USE_RESIZE) is passed,
    # because -r means it's for make_super.sh -> lpmake, which requires RAW images.
    SPARSE_REQUIRED=false
    if [[ $USE_SPARSE == true ]] || ( [[ "$ORIG_TYPE" == "sparse" ]] && [[ $USE_RESIZE == false ]] ); then
        SPARSE_REQUIRED=true
        FLAGS="-s $FLAGS"
    fi

    # ALWAYS create formatted EXT4 Image natively (Sparse or RAW depending on FLAGS)
    bin/make_ext4fs $FLAGS "$TEMP_IMG" "level2/$PART"
    
    # --- FIX: Inject Original Filesystem UUID into Superblock ---
    # The bootloader or kernel panics if the newly rebuilt ext4 image has a random UUID.
    # We use our custom Python script to perfectly hex-edit the original bits into either the RAW or SPARSE output.
    UUID_FILE="level2/config/${PART}_uuid.txt"
    if [[ -f "$UUID_FILE" ]]; then
        ORIG_UUID=$(cat "$UUID_FILE")
        echo "  -> Restoring original Ext4 UUID natively: $ORIG_UUID"
        python3 bin/set_ext4_uuid.py "$TEMP_IMG" "$ORIG_UUID" || true
    fi

    # Resize if requested (used by make_super.sh to minimize before lpmake)
    [[ $USE_RESIZE == true ]] && bin/resize2fs -M "$TEMP_IMG"

    # --- FIX: Strip dm-verity if rmverity tool is available ---
    if [[ -f bin/rmverity ]]; then
        bin/rmverity "$TEMP_IMG" 2>/dev/null || true
    fi
fi

mv -f "$TEMP_IMG" "$OUTPUT_IMG"
echo "  -> $PART image created: $(du -h "$OUTPUT_IMG" | cut -f1)"
