import struct, sys, zlib
d = open(sys.argv[1], 'rb').read()
print('size', len(d), 'head', d[:12].hex())
H = lambda s: zlib.crc32(s.encode())
names = {H(n): n for n in ['PorchItem', 'PorchItem_Value1', 'PorchItem_EquipFlag']}
recs = [(struct.unpack_from('<I', d, o)[0], o) for o in range(0x0c, len(d) - 8, 8)]
items = [o for h, o in recs if h == H('PorchItem')]
vals = [o for h, o in recs if h == H('PorchItem_Value1')]
print(len(items), len(vals))
names = []
for k in range(0, len(items), 16):
    s = b''.join(d[o+4:o+8] for o in items[k:k+16]).split(b'\0')[0].decode()
    names.append(s)
for i, (n, o) in enumerate(zip(names, vals)):
    if not n: break
    if n.startswith('Weapon_'): print(i, n, struct.unpack_from('<i', d, o+4)[0])
