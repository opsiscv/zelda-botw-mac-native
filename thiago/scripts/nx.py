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


def yaz0_tokens(c):
    """The tokens of a Yaz0 stream: (output position, length, source position or None for a literal)."""
    size = struct.unpack_from('>I', c, 4)[0]; i, p = 16, 0
    while p < size:
        flags = c[i]; i += 1
        for b in range(8):
            if p >= size: break
            if flags & (0x80 >> b):
                yield p, 1, None; i += 1; p += 1
            else:
                b1, b2 = c[i], c[i+1]; i += 2
                n = b1 >> 4
                if n == 0: n = c[i] + 0x12; i += 1
                else: n += 2
                yield p, n, p - ((b1 & 0xf) << 8 | b2) - 1; p += n


def yaz0_patch(c, d2, changed):
    """A Yaz0 stream of d2 that reuses c's copies: d2 differs from what c decodes only inside the changed (start, end)
    ranges, and the tokens that write or read there become literals (the file grows by about those bytes)."""
    changed = sorted(changed)
    def hit(a, b):
        return any(s < b and a < e for s, e in changed)
    out = bytearray(c[:16]); group = []
    def flush():
        flags = 0; body = bytearray()
        for k, t in enumerate(group):
            if t[0] == 'lit': flags |= 0x80 >> k
            body += t[1]
        out.append(flags); out.extend(body); group.clear()
    for p, n, src in yaz0_tokens(c):
        if src is None or hit(p, p + n) or hit(src, src + n):
            toks = [('lit', bytes([d2[q]])) for q in range(p, p + n)]
        else:
            dist = p - src - 1
            toks = [('ref', bytes([((n - 2) << 4) | dist >> 8, dist & 0xff]) if n <= 0x11 else bytes([dist >> 8, dist & 0xff, n - 0x12]))]
        for t in toks:
            group.append(t)
            if len(group) == 8: flush()
    if group: flush()
    return bytes(out)


def sarc_replace(arc, name, new):
    """The SARC with one file's data replaced; the files after it move by a multiple of 0x2000 (their alignment holds)."""
    arc = bytearray(arc)
    hl = struct.unpack_from('<H', arc, 4)[0]; ds = struct.unpack_from('<I', arc, 0xc)[0]
    n = struct.unpack_from('<H', arc, hl + 6)[0]
    entry = next(hl + 12 + k * 16 for k, (nm, a, e) in enumerate(sarc_files(arc)) if nm == name)
    start, end = struct.unpack_from('<II', arc, entry + 8)
    grow = start + len(new) - end; delta = -(-max(0, grow) // 0x2000) * 0x2000
    for k in range(n):
        e = hl + 12 + k * 16; s0, e0 = struct.unpack_from('<II', arc, e + 8)
        if s0 >= end and e != entry: struct.pack_into('<II', arc, e + 8, s0 + delta, e0 + delta)
    struct.pack_into('<I', arc, entry + 12, start + len(new))
    out = arc[:ds + start] + new + bytes(end + delta - start - len(new)) + arc[ds + end:]
    struct.pack_into('<I', out, 8, len(out))
    return bytes(out)
