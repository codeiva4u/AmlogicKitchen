#!/usr/bin/sudo bash

set -e

# --- FIX: Proper while loop instead of recursive self-call ---
# This allows user to run Level 2 → Level 1 in sequence
while true; do

echo "....................."
echo "Amlogic Kitchen"
echo "....................."
read -p "Select level 1, 2, 3 or q/Q to exit: " level

case "$level" in
  1)
    if [[ ! -d level1 ]]; then
      echo "Can't find level1 folder"
      exit 1
    fi

    [[ -d out ]] || { echo "Created out folder"; mkdir out; }

    file_name=$(<level1/projectname.txt)

    # Auto-read pack tool choice from L1 unpack config if available
    if [[ -f level1/pack_tool_index.txt ]]; then
      choice=$(<level1/pack_tool_index.txt)
      if [[ "$choice" == "2" ]]; then
        echo "Auto-selected aml_image_v2_packer from L1 metadata."
      else
        echo "Auto-selected ampack from L1 metadata."
      fi
    else
      echo "Choose pack tool:"
      echo "1) ampack"
      echo "2) aml_image_v2_packer"
      read -p "Enter choice [1 or 2]: " choice
    fi

    case "$choice" in
      1)
        echo "Using ampack..."
        rm -f level1/projectname.txt
        bin/ampack pack level1 "out/${file_name}.img"
        echo "$file_name" >level1/projectname.txt
        ;;
      2)
        if [[ ! -f level1/image.cfg ]]; then
          echo "Can't find image.cfg"
        else
          echo "Using aml_image_v2_packer..."
          bin/aml_image_v2_packer -r level1/image.cfg level1 "out/${file_name}.img"
        fi
        ;;
      *)
        echo "Invalid Pack option"
        exit 1
        ;;
    esac
    echo "Done."
    ;;

  2)
    if [[ ! -d level2 ]]; then
      echo "Unpack level 2 first"
      exit 1
    fi

    parts_common=(system system_ext vendor product odm oem oem_a)
    parts_extra=(oem_a odm_ext_a odm_ext_b)

    if [[ -f level1/super.PARTITION ]]; then
      # --- Super partition flow: rebuild partitions then rebuild super ---
      echo "Super partition detected. Rebuilding via make_super.sh..."
      ./common/make_super.sh level1/super.PARTITION amlogic
    else
      # --- Non-super flow: rebuild individual partition images ---
      echo "No super partition. Rebuilding individual partition images..."
      for part in "${parts_common[@]}"; do
        [[ -d level2/$part ]] || continue
        echo "Creating $part image"
        # --- FIX: Read saved size, with fallback ---
        if [[ -f "level2/config/${part}_size.txt" ]]; then
          size=$(<level2/config/${part}_size.txt)
        else
          echo "WARNING: No saved size for $part, calculating from content..."
          size=$(du -sb level2/$part | cut -f1 | awk '{$1=int($1*1.02); if($1<1048576) $1=1048576; printf $1}')
        fi
        [[ -n "$size" ]] && ./common/make_image.sh -s "$part" "$size" "level2/$part/" "level1/$part.PARTITION"
        echo "Done."
      done

      for part in "${parts_extra[@]}"; do
        [[ -d level2/$part ]] || continue
        echo "Creating $part image"
        if [[ -f "level2/config/${part}_size.txt" ]]; then
          size=$(<level2/config/${part}_size.txt)
        else
          size=$(du -sb level2/$part | cut -f1 | awk '{$1=int($1*1.02); if($1<1048576) $1=1048576; printf $1}')
        fi
        [[ -n "$size" ]] && ./common/make_image.sh -s "$part" "$size" "level2/$part/" "level1/$part.PARTITION"
        echo "Done."
      done
    fi

    # REVERTED: Patch vbmeta to disable AVB verification
    # Direct dd patching of vbmeta flags breaks the RSA signature on strict Amlogic bootloaders,
    # causing an immediate fall back to USB flashing mode (Flashing Loop).

    rm -f level2/*.txt
    ;;

  3)
    if [[ ! -d level3 ]]; then
      echo "Unpack level 3 first"
      exit 1
    fi

    # logo
    [[ -d level3/logo ]] && bin/logo_img_packer -r level3/logo level1/logo.PARTITION

    # devtree / meson1
    for tree in devtree meson1; do
      dir="level3/$tree"
      outfile="level1/_aml_dtb.PARTITION"
      [[ $tree == "meson1" ]] && outfile="level1/meson1.dtb"

      [[ -d "$dir" ]] || continue

      # --- FIX: Check if single.dts exists, otherwise assume multi-DTS ---
      if [[ -f "$dir/single.dts" ]]; then
        dtc -I dts -O dtb "$dir/single.dts" -o "$outfile"
      else
        # Use nullglob to avoid literal '*.dts' if no files exist
        shopt -s nullglob
        files=("$dir"/*.dts)
        shopt -u nullglob
        
        if [[ ${#files[@]} -gt 0 ]]; then
          for dts in "${files[@]}"; do
            dtb="${dts%.dts}.dtb"
            dtc -I dts -O dtb "$dts" -o "$dtb"
          done
          bin/dtbTool -o "$outfile" "$dir/"
        else
          # Both single.dts and multi.dts are missing. 
          # This means dtc failed during unpack (e.g., encrypted/unknown format).
          # We just leave the original $outfile in level1 untouched!
          echo "No DTS files found in $dir. Preserving original $outfile..."
        fi
      fi
    done

    # Compression
    for f in "_aml_dtb.PARTITION" "meson1.dtb"; do
      [[ -f level1/$f ]] || continue
      
      prompt="Do you want to compress $f? (y/n)"
      [[ "$f" == "meson1.dtb" ]] && prompt="Do you want to compress $f? (Not recommended unless supported) (y/n): "
      
      read -p "$prompt " answer </dev/tty
      if [[ "$answer" =~ ^[Yy] ]]; then
        size=$(du -b "level1/$f" | cut -f1)
        if [[ $size -gt 196607 ]]; then
          gzip -nc "level1/$f" >"level1/$f.gzip"
          mv "level1/$f.gzip" "level1/$f"
        fi
        rm -f level3/${f%.*}/*.dtb
      fi
    done

    ./common/pack_boot.sh
    echo "Done."
    ;;

  q|Q)
    # Fix permissions before exiting
    ./common/write_perm.sh
    echo "All operations completed successfully."
    exit 0
    ;;

  *)
    echo "Invalid selection"
    ;;
esac

# Fix permissions after each level operation
./common/write_perm.sh

done
