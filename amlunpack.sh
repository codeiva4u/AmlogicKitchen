#!/usr/bin/sudo bash

set -e

# --- FIX: Proper while loop instead of recursive self-call ---
# This allows user to run Level 1 → Level 2 → Level 3 in sequence
while true; do

echo "....................."
echo "Amlogic Kitchen"
echo "....................."
read -p "Select level 1, 2, 3 or q/Q to exit: " level

case "$level" in
  1)
    [[ -d level1 ]] && { echo "Deleting existing level1"; rm -rf level1; }
    mkdir level1

    echo "....................."
    echo "Amlogic Kitchen"
    echo "....................."

    [[ -d in ]] || { echo "Creating /in folder"; mkdir in; }

    img_list=(in/*.img)
    if [[ ${#img_list[@]} -eq 0 || ! -f "${img_list[0]}" ]]; then
      echo "No .img files found in /in"
      exit 0
    fi

    rename 's/ /_/g' in/*.img
    
    # Auto-select the first .img file
    img_file="${img_list[0]}"
    projectname=$(basename "$img_file" .img)
    echo "Auto-selected firmware: $projectname.img"

    # Auto-detect unpack tool based on Amlogic Image Header Magic
    # "AMLB" (Amlogic Image V2) starts at offset 0
    # "AMLA" (Amlogic Image V1) starts at offset 0
    magic=$(head -c 4 "$img_file" 2>/dev/null || true)
    
    if [[ "$magic" == "AMLB" ]]; then
      echo "Detected AMLB Magic Header (Amlogic Image V2)."
      echo "Auto-selecting aml_image_v2_packer..."
      bin/aml_image_v2_packer -d "$img_file" level1
      echo "2" > level1/pack_tool_index.txt
    else
      echo "Auto-selecting ampack (Standard Amlogic format)..."
      bin/ampack unpack "$img_file" level1
      echo "1" > level1/pack_tool_index.txt
    fi

    echo "$projectname" > level1/projectname.txt
    echo "Done."
    ;;

  2)
    [[ -d level1 ]] || { echo "Unpack level 1 first"; exit 1; }
    [[ -d level2 ]] && { echo "Deleting existing level2"; rm -rf level2; }
    mkdir -p level2/config

    ./common/extract_images.sh level1 level2

    [[ -f level1/super.PARTITION ]] && ./common/extract_super.sh level1/super.PARTITION level2/

    echo "Done."
    ;;

  3)
    [[ -d level1 ]] || { echo "Unpack level 1 first"; exit 1; }
    [[ -d level3 ]] && rm -rf level3
    mkdir level3

    ./common/unpack_boot.sh

    if [[ -f level1/logo.PARTITION ]]; then
      mkdir level3/logo
      bin/logo_img_packer -d level1/logo.PARTITION level3/logo
    fi

    if [[ ! -f level1/_aml_dtb.PARTITION ]]; then
      read -p "Do you want to copy dtb to level1? (y/n): " answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        for part in boot recovery vendor_boot boot_a recovery_a vendor_boot_a; do
          [[ -f level1/_aml_dtb.PARTITION ]] && break
          for suffix in PARTITION-dtb PARTITION-second; do
            src="level3/$part/split_img/$part.$suffix"
            [[ -f "$src" ]] && cp "$src" level1/_aml_dtb.PARTITION && break
          done
        done
      fi
    fi

    if [[ -f level1/_aml_dtb.PARTITION ]]; then
      read -p "Do you want to unpack _aml_dtb.PARTITION? (y/n): " answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        mkdir -p level3/devtree
        # Attempt gzip decompression (may or may not be compressed)
        7zz x level1/_aml_dtb.PARTITION -y >/dev/null 2>&1 || true
        # --- FIX: 7zz extracts a FILE not directory, use -e instead of -d ---
        if [[ -e _aml_dtb ]]; then
          bin/dtbSplit _aml_dtb level3/devtree/ >/dev/null 2>&1 || true
          rm -rf _aml_dtb
        fi
        
        # --- FIX: Hide "Invalid AML DTB header" completely ---
        # Amlogic firmwares often use Standard Single DTBs instead of Multi-DTBs.
        # dtbSplit prints "Invalid AML DTB header" when it sees a single DTB.
        # This is not an error! It just falls back to dtc in the 'else' block.
        bin/dtbSplit level1/_aml_dtb.PARTITION level3/devtree/ >/dev/null 2>&1 || true

        if [[ "$(ls -A level3/devtree/ 2>/dev/null)" ]]; then
          echo "Multi-DTB detected and unpacked."
          for dtb in level3/devtree/*.dtb; do
            [[ -e "$dtb" ]] || continue
            dts="${dtb%.dtb}.dts"
            dtc -I dtb -O dts "$dtb" -o "$dts" >/dev/null 2>&1 || true
            rm -f "$dtb"
          done
        else
          echo "Single DTB detected. Unpacking to single.dts..."
          dtc -I dtb -O dts level1/_aml_dtb.PARTITION -o level3/devtree/single.dts >/dev/null 2>&1 || true
        fi
      fi
    fi

    if [[ -f level1/meson1.dtb ]]; then
      read -p "Do you want to unpack meson1.dtb? (y/n): " answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        mkdir -p level3/meson1
        
        # --- FIX: Attempt decompression just like _aml_dtb.PARTITION ---
        7zz x level1/meson1.dtb -y >/dev/null 2>&1 || true
        if [[ -e meson1 ]]; then
          bin/dtbSplit meson1 level3/meson1/ >/dev/null 2>&1 || true
          rm -rf meson1
        fi

        # Hide "Invalid header" error for Single DTB fallbacks
        bin/dtbSplit level1/meson1.dtb level3/meson1/ >/dev/null 2>&1 || true

        if [[ "$(ls -A level3/meson1/ 2>/dev/null)" ]]; then
          echo "Multi-DTB detected and unpacked."
          for dtb in level3/meson1/*.dtb; do
            [[ -e "$dtb" ]] || continue
            dts="${dtb%.dtb}.dts"
            dtc -I dtb -O dts "$dtb" -o "$dts" >/dev/null 2>&1 || true
            rm -f "$dtb"
          done
        else
          echo "Single DTB detected. Unpacking to single.dts..."
          dtc -I dtb -O dts level1/meson1.dtb -o level3/meson1/single.dts >/dev/null 2>&1 || true
          
          # --- FIX: If dtc failed (e.g. encrypted or unknown format), we leave the folder empty.
          # amlpack.sh is now updated to handle empty/missing L3 meson1 by keeping the original file.
          if [[ ! -s level3/meson1/single.dts ]]; then
            echo "Failed to decompile meson1.dtb. It will be preserved as-is during repack."
            rm -f level3/meson1/single.dts
          fi
        fi
      fi
    fi

    echo "Done."
    ;;

  q|Q)
    # Fix permissions before exiting
    ./common/write_perm.sh
    echo "All operations completed successfully."
    exit 0
    ;;

  *)
    echo "Invalid option."
    ;;
esac

# Fix permissions after each level operation
./common/write_perm.sh

done
