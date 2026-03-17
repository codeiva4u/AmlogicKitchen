#!/usr/bin/env python3
import sys
import struct
import os

# Ext4 superblocks have the s_uuid field at offset 0x68
# The primary superblock starts at byte 1024 (0x400)
# So the primary UUID offset is 0x468
UUID_OFFSET = 0x68
SUPERBLOCK_BASE = 0x400

# Sparse image magic and header sizes
SPARSE_MAGIC = 0xED26FF3A
SPARSE_HEADER_SIZE = 28
CHUNK_HEADER_SIZE = 12

CHUNK_TYPE_RAW = 0xCAC1
CHUNK_TYPE_FILL = 0xCAC2
CHUNK_TYPE_DONT_CARE = 0xCAC3
CHUNK_TYPE_CRC = 0xCAC4

def set_uuid_raw(f, uuid_bytes):
    # Check Ext4 Magic to be sure (at 0x438)
    f.seek(SUPERBLOCK_BASE + 0x38)
    magic = struct.unpack('<H', f.read(2))[0]
    if magic != 0xEF53:
        print(f"Error: Not a valid Raw Ext4 image. Magic is 0x{magic:04X}, expected 0xEF53.")
        return False

    # Write UUID to primary superblock
    f.seek(SUPERBLOCK_BASE + UUID_OFFSET)
    f.write(uuid_bytes)
    return True

def set_uuid_sparse(f, uuid_bytes):
    f.seek(0)
    # Read sparse header (28 bytes)
    header_data = f.read(SPARSE_HEADER_SIZE)
    if len(header_data) < SPARSE_HEADER_SIZE:
        return False
        
    (magic, major_ver, minor_ver, file_hdr_sz, chunk_hdr_sz,
     blk_sz, total_blks, total_chunks, image_checksum) = struct.unpack('<I4H4I', header_data)
     
    if magic != SPARSE_MAGIC:
        return False
        
    print(f"Detected Sparse Image: block_size={blk_sz}, chunks={total_chunks}")
    
    # We need to find the physical offset of logical block 0 (which contains the 1024 byte superblock).
    # Since logical blocks for ext4 are typically 4096 bytes, block 0 holds offsets 0 to 4095.
    
    current_physical_offset = file_hdr_sz
    current_logical_block = 0
    
    for i in range(total_chunks):
        f.seek(current_physical_offset)
        chunk_data = f.read(chunk_hdr_sz)
        if len(chunk_data) < 12:  # Safe fallback if chunk header is unexpectedly small
            break
            
        chunk_type, reserved, chunk_size, total_sz = struct.unpack('<HHII', chunk_data[:12])
        data_sz = total_sz - chunk_hdr_sz
        
        # Superblock is in logical block 0.
        if current_logical_block == 0:
            if chunk_type == CHUNK_TYPE_RAW:
                # The superblock data is literally written in this raw chunk.
                # Physical offset to the chunk's payload is current_physical_offset + chunk_hdr_sz
                superblock_payload_offset = current_physical_offset + chunk_hdr_sz
                
                # Verify Ext4 Magic at offset 0x438 inside the chunk payload
                f.seek(superblock_payload_offset + SUPERBLOCK_BASE + 0x38)
                ext4_magic = struct.unpack('<H', f.read(2))[0]
                
                if ext4_magic != 0xEF53:
                    print(f"Error: Found Ext4 Superblock chunk but magic is invalid (0x{ext4_magic:04X})")
                    return False
                
                # Inject UUID!
                f.seek(superblock_payload_offset + SUPERBLOCK_BASE + UUID_OFFSET)
                f.write(uuid_bytes)
                print(f"Success: Wrote UUID natively inside Sparse chunk!")
                return True
            else:
                print("Error: Logical block 0 is NOT a RAW chunk. Cannot spoof UUID.")
                return False
                
        # Advance pointers
        current_logical_block += chunk_size
        current_physical_offset += total_sz
        
    print("Error: Could not locate logical block 0 in Sparse image chunks.")
    return False

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
            # Check if it's a Sparse image first
            f.seek(0)
            magic_bytes = f.read(4)
            if len(magic_bytes) == 4 and struct.unpack('<I', magic_bytes)[0] == SPARSE_MAGIC:
                if set_uuid_sparse(f, uuid_bytes):
                    sys.exit(0)
                else:
                    sys.exit(1)
            else:
                # Fallback to standard RAW Ext4 edit
                if set_uuid_raw(f, uuid_bytes):
                    print(f"Success: Wrote UUID {uuid_hex} to primary RAW superblock.")
                    sys.exit(0)
                else:
                    sys.exit(1)
                    
    except Exception as e:
        print(f"Error writing UUID: {e}")
        sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python3 set_ext4_uuid.py <image_path> <uuid_hex>")
        sys.exit(1)
    
    set_uuid(sys.argv[1], sys.argv[2])
