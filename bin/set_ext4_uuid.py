#!/usr/bin/env python3
import sys
import struct
import os

# Ext4 superblocks have the s_uuid field at offset 0x68
# The primary superblock starts at byte 1024 (0x400)
# So the primary UUID offset is 0x468
UUID_OFFSET = 0x68
SUPERBLOCK_BASE = 0x400

def set_uuid(image_path, uuid_hex):
    if len(uuid_hex) != 32:
        print(f"Error: UUID hex strictly requires 32 characters, got {len(uuid_hex)}")
        sys.exit(1)
        
    try:
        uuid_bytes = bytes.fromhex(uuid_hex)
    except ValueError:
        print("Error: Invalid hex string for UUID.")
        sys.exit(1)

    try:
        with open(image_path, 'r+b') as f:
            # Check Ext4 Magic to be sure (at 0x438)
            f.seek(SUPERBLOCK_BASE + 0x38)
            magic = struct.unpack('<H', f.read(2))[0]
            if magic != 0xEF53:
                print(f"Error: Not a valid Ext4 image. Magic is 0x{magic:04X}, expected 0xEF53.")
                sys.exit(1)

            # Write UUID to primary superblock
            f.seek(SUPERBLOCK_BASE + UUID_OFFSET)
            f.write(uuid_bytes)
            print(f"Success: Wrote UUID {uuid_hex} to primary superblock.")

            # TODO: To be completely robust, we should iterate through block groups
            # to update backup superblocks, but for Android dm-verity/init scripts
            # only the primary superblock is usually read during early mount.
    
    except Exception as e:
        print(f"Error writing UUID: {e}")
        sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python3 set_ext4_uuid.py <image_path> <uuid_hex>")
        sys.exit(1)
    
    set_uuid(sys.argv[1], sys.argv[2])
