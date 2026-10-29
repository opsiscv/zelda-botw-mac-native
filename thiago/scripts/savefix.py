import struct, sys, zlib
MAX = 6553500   # what the game itself stores for a full weapon of Life 65535 (hundredths)
H = lambda s: zlib.crc32(s.encode())
for path in sys.argv[1:]:
    d = bytearray(open(path, 'rb').read())
    recs = [(struct.unpack_from('<I', d, o)[0], o) for o in range(0x0c, len(d) - 8, 8)]
    items = [o for h, o in recs if h == H('PorchItem')]
    vals = [o for h, o in recs if h == H('PorchItem_Value1')]
    n = 0
    for i, o in enumerate(vals):
        name = b''.join(d[x+4:x+8] for x in items[i*16:i*16+16]).split(b'\0')[0].decode()
        if not name: break
        if name.startswith(('Weapon_Sword_', 'Weapon_Lsword_', 'Weapon_Spear_', 'Weapon_Bow_', 'Weapon_Shield_')):
            if struct.unpack_from('<i', d, o+4)[0] != MAX: struct.pack_into('<i', d, o+4, MAX); n += 1
    open(path, 'wb').write(d)
    print(path.split('/')[-2], 'weapons refilled:', n)
