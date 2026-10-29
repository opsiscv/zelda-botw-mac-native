"""Yaz0 and SARC, the game's compression and archive (shared by the mod scripts)."""
import struct


def yaz0_decode(d):
    assert d[:4] == b'Yaz0'
    size = struct.unpack_from('>I', d, 4)[0]
    out = bytearray(); i = 16
    while len(out) < size:
        flags = d[i]; i += 1
        for b in range(8):
            if len(out) >= size: break
            if flags & (0x80 >> b):
                out.append(d[i]); i += 1
            else:
                b1, b2 = d[i], d[i+1]; i += 2
                dist = ((b1 & 0xf) << 8 | b2) + 1
                n = b1 >> 4
                if n == 0: n = d[i] + 0x12; i += 1
                else: n += 2
                for _ in range(n): out.append(out[-dist])
    return bytes(out)


def yaz0_encode(d):   # literals only: valid Yaz0, about 12% larger than the raw data
    out = bytearray(b'Yaz0' + struct.pack('>I', len(d)) + bytes(8))
    for i in range(0, len(d), 8):
        out.append(0xff); out += d[i:i+8]
    return bytes(out)


def sarc_files(d):
    hl = struct.unpack_from('<H', d, 4)[0]; data_start = struct.unpack_from('<I', d, 0xc)[0]
    n = struct.unpack_from('<H', d, hl + 6)[0]; sfnt = hl + 12 + n*16
    for k in range(n):
        _, attr, s, e = struct.unpack_from('<IIII', d, hl + 12 + k*16)
        name_off = sfnt + 8 + (attr & 0xffff)*4
        name = d[name_off:d.index(b'\0', name_off)].decode()
        yield name, data_start + s, data_start + e
