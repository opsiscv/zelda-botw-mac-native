"""Writes a RomFS mod with unbreakable weapons, bows and shields (General.Life in each actor pack's bgparamlist)."""
import struct, sys, zlib
from pathlib import Path
sys.path.insert(0, str(Path.home()/'Games/MacNativeGames-BOTW/games/totk/scripts'))
import make_mod_manifest as m

LIFE_VALUE = 1000000   # unbreakable in practice (one point per hit)
R = Path.home()/'Downloads/Games/Zelda BOTW/basegame/BotW_build/totk/extracted/botw160/romfs'
OUT = Path.home()/'Library/Application Support/MacNativeGames/BotW/mods/botw160'
GENERAL, LIFE = zlib.crc32(b'General'), zlib.crc32(b'Life')


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


def life_offsets(d, base):
    """Offsets (in d) of General.Life int values in the AAMP at d[base:]."""
    assert d[base:base+4] == b'AAMP'
    found = []
    def plist(o):
        _, lo, nl, oo, no = struct.unpack_from('<IHHHH', d, o)
        for k in range(nl): plist(o + lo*4 + k*12)
        for k in range(no):
            po = o + oo*4 + k*8
            crc, pr, npar = struct.unpack_from('<IHH', d, po)
            if crc != GENERAL: continue
            for j in range(npar):
                p = po + pr*4 + j*8
                pcrc, word = struct.unpack_from('<II', d, p)
                if pcrc == LIFE:
                    assert word >> 24 == 2, 'Life is not an int'
                    found.append(p + (word & 0xffffff)*4)
    pio = struct.unpack_from('<I', d, base + 0x14)[0]
    plist(base + 0x30 + pio)
    return found


idx = m.read_index(R/'runtime-index.bin')
packs = sorted(p for p in idx if p.startswith('Actor/Pack/Weapon_') and not p.startswith('Actor/Pack/Weapon_Arrow'))
rom = open(R/'romfs.bin', 'rb'); written = 0
for path in packs:
    o, s = idx[path]; rom.seek(o)
    d = bytearray(yaz0_decode(rom.read(s)))
    lives = []
    for name, a, e in sarc_files(d):
        if name.startswith('Actor/GeneralParamList/'):
            for v in life_offsets(d, a):
                old = struct.unpack_from('<i', d, v)[0]
                if old > 0:
                    struct.pack_into('<i', d, v, LIFE_VALUE); lives.append((old, LIFE_VALUE))
    if not lives: print('no Life:', path); continue
    dst = OUT/path; dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(yaz0_encode(bytes(d)))
    assert yaz0_decode(dst.read_bytes()) == bytes(d)
    written += 1
    print(path, lives)
print('written', written, 'of', len(packs))
