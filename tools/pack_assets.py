#!/usr/bin/env python3
"""Writes and checks Tessera asset packs (.tpak): a game's assets in one file. build_player.py uses this.

  pack_assets.py --list game.tpak          the files in a pack, with sizes
  pack_assets.py --verify game.tpak        reads every file back and checks it; exit status 1 if any is damaged

The format is described at the top of native/tessera_pack.c, which reads it. Files are deflated when that makes
them smaller and then scrambled, so they cannot be opened or edited with ordinary tools, and each carries a checksum
so that a changed file is refused. It is not encryption."""
import argparse
import os
import struct
import sys
import zlib

KEY = 0x7E55E2A5
BLOCK = 4096
MAGIC = b'TPAK1\0\0\0'
# Already compressed: deflating again gains nothing.
STORED = {'.png', '.jpg', '.jpeg', '.ogg', '.mp3', '.flac', '.tpak'}


def _block(seed, salt):
    state = (seed ^ KEY ^ ((salt * 2654435761) & 0xFFFFFFFF)) & 0xFFFFFFFF
    if state == 0:
        state = KEY
    out = bytearray(BLOCK)
    for i in range(BLOCK):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        out[i] = (state >> 11) & 0xFF
    return bytes(out)


def _scramble(data, seed, salt):
    """XOR with the repeating block; the same call undoes it."""
    if not data:
        return data
    block = _block(seed, salt)
    stream = (block * (len(data) // BLOCK + 1))[:len(data)]
    return (int.from_bytes(data, 'little') ^ int.from_bytes(stream, 'little')).to_bytes(len(data), 'little')


def write_pack(path, files, compress=True):
    """files: (name inside the pack, path of the file on disk) pairs. Names use forward slashes.
    compress=False stores every file at its full size (still scrambled and checksummed)."""
    seed = int.from_bytes(os.urandom(4), 'little')
    index = bytearray()
    with open(path, 'wb') as out:
        out.write(b'\0' * 32)
        for name, source in sorted(files):
            with open(source, 'rb') as handle:
                plain = handle.read()
            crc = zlib.crc32(plain) & 0xFFFFFFFF
            stored, flags = plain, 0
            if compress and os.path.splitext(name)[1].lower() not in STORED:
                deflated = zlib.compress(plain, 9)
                if len(deflated) < len(plain):
                    stored, flags = deflated, 1
            encoded = name.encode('utf-8')
            index += struct.pack('<H', len(encoded)) + encoded + struct.pack('<QIIIB', out.tell(), len(stored), len(plain), crc, flags)
            out.write(_scramble(stored, seed, crc))
        index_offset = out.tell()
        out.write(_scramble(bytes(index), seed, 0xFFFFFFFF))
        out.seek(0)
        out.write(MAGIC + struct.pack('<IIQII', 1, len(files), index_offset, len(index), seed))
    return len(files)


def read_index(handle):
    header = handle.read(32)
    if len(header) != 32 or header[:8] != MAGIC:
        raise ValueError('not a Tessera asset pack')
    version, count, index_offset, index_size, seed = struct.unpack('<IIQII', header[8:])
    if version != 1:
        raise ValueError(f'pack version {version} is not supported')
    handle.seek(index_offset)
    index = _scramble(handle.read(index_size), seed, 0xFFFFFFFF)
    entries, at = [], 0
    for _ in range(count):
        length, = struct.unpack_from('<H', index, at)
        name = index[at + 2:at + 2 + length].decode('utf-8')
        offset, stored, size, crc, flags = struct.unpack_from('<QIIIB', index, at + 2 + length)
        entries.append((name, offset, stored, size, crc, flags))
        at += 2 + length + 21
    return seed, entries


def read_file(handle, seed, entry):
    name, offset, stored, size, crc, flags = entry
    handle.seek(offset)
    data = _scramble(handle.read(stored), seed, crc)
    if flags & 1:
        data = zlib.decompress(data)
    if len(data) != size or (zlib.crc32(data) & 0xFFFFFFFF) != crc:
        raise ValueError(f'{name} is damaged')
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--list', metavar='PACK')
    parser.add_argument('--verify', metavar='PACK')
    args = parser.parse_args()
    if not args.list and not args.verify:
        parser.error('give --list or --verify')
    with open(args.list or args.verify, 'rb') as handle:
        seed, entries = read_index(handle)
        bad = 0
        for entry in entries:
            if args.verify:
                try:
                    read_file(handle, seed, entry)
                except (ValueError, zlib.error) as error:
                    print(f'DAMAGED {entry[0]}: {error}')
                    bad += 1
            else:
                print(f'{entry[3]:>10}  {entry[2]:>10}  {entry[0]}')
        print(f'{len(entries)} files' + (f', {bad} damaged' if args.verify else ''))
        return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
