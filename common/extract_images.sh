#!/bin/bash

set -e

# Add bin/ to LD_LIBRARY_PATH if not already present
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
[[ ":$LD_LIBRARY_PATH:" != *":$ROOT_DIR/bin:"* ]] && export LD_LIBRARY_PATH="$ROOT_DIR/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

IMAGE_DIR="$1"
OUTPUT_FOLDER="$2"

partitions=(
  system_a system_dlkm_a system_ext_a vendor_a vendor_dlkm_a product_a odm_a odm_ext_a odm_dlkm_a oem_a
  system system_dlkm system_ext vendor vendor_dlkm product odm odm_ext odm_dlkm oem
)

for IMAGE in "${partitions[@]}"; do
  for ext in PARTITION img fex; do
    IMAGE_FILE="$IMAGE_DIR/$IMAGE.$ext"
    [[ -f "$IMAGE_FILE" ]] && break || IMAGE_FILE=""
  done

  [[ -z "$IMAGE_FILE" || ! -f "$IMAGE_FILE" ]] && continue

  SIZE=$(du -b "$IMAGE_FILE" | cut -f1)
  [[ "$SIZE" -lt 1024 ]] && continue

  echo "Extracting $IMAGE"
  TYPE=$(bin/gettype -i "$IMAGE_FILE")

  # --- FIX: Save image type for ALL partitions ---
  echo "$TYPE" > "level2/config/${IMAGE}_imgtype.txt"

  if [[ "$TYPE" == "erofs" ]]; then
    bin/extract.erofs -i "$IMAGE_FILE" -x -o "$OUTPUT_FOLDER"
    # Save original partition file size
    du -b "$IMAGE_FILE" | cut -f1 > "level2/config/${IMAGE}_size.txt"
  elif [[ "$TYPE" == "sparse" ]]; then
    # --- FIX: Save original sparse image size BEFORE converting ---
    du -b "$IMAGE_FILE" | cut -f1 > "level2/config/${IMAGE}_size.txt"
    simg2img "$IMAGE_FILE" "level2/${IMAGE}.raw.img"
    # Save the raw (desparseified) image size — needed for make_ext4fs -l
    du -b "level2/${IMAGE}.raw.img" | cut -f1 > "level2/config/${IMAGE}_raw_size.txt"
    python3 bin/imgextractor.py "level2/${IMAGE}.raw.img" "$OUTPUT_FOLDER"
    rm -f "level2/${IMAGE}.raw.img"
  else
    # Raw ext4 image
    # --- FIX: Save raw image size ---
    du -b "$IMAGE_FILE" | cut -f1 > "level2/config/${IMAGE}_size.txt"
    du -b "$IMAGE_FILE" | cut -f1 > "level2/config/${IMAGE}_raw_size.txt"
    python3 bin/imgextractor.py "$IMAGE_FILE" "$OUTPUT_FOLDER"
  fi

  awk -i inplace '!seen[$0]++' level2/config/${IMAGE}_f*
done
