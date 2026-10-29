"""python3 -m unittest test_key_icons (in thiago/scripts)."""
import unittest
import bntx_bc4
import key_icons


class Labels(unittest.TestCase):
    def test_default(self):
        k = key_icons.labels('', '')
        self.assertEqual((k['a'], k['b'], k['x'], k['plus'], k['minus']), ('e', 'shift', 'space', 'esc', 'tab'))
        self.assertEqual((k['y'], k['zr'], k['r']), ('u', None, 'ctrl'))

    def test_mouse_buttons_win(self):
        k = key_icons.labels('', 'mouse_left = y\nmouse_right = zr aim mouse_left\nmouse_middle = r\nmouse5 = x  # side\n')
        self.assertEqual((k['y'], k['zr'], k['r'], k['x']), ('mouse_left', 'mouse_right', 'mouse_middle', 'space'))

    def test_keys_txt_moves_a_key(self):
        k = key_icons.labels('f = e\ne = none\n# c\n', '')
        self.assertEqual(k['a'], 'f')
        self.assertEqual(k['dpad_left'], None)   # F was the d-pad's left; it does E's job now

    def test_key_gone(self):
        self.assertIsNone(key_icons.labels('tab = none\n', '')['minus'])


class MenuLabels(unittest.TestCase):
    def test_menu(self):
        k = key_icons.labels('', 'mouse_left = y\nmouse_middle = r\nmouse_right = zr aim mouse_left\n', menu=True)
        self.assertEqual((k['a'], k['b'], k['r'], k['y'], k['l'], k['zr']), ('mouse_left', 'esc', 'e', 'v', 'q', 'mouse_right'))

    def test_menu_follows_keys_txt(self):
        k = key_icons.labels('f = e\ne = none\nn = v\nv = none\n', '', menu=True)
        self.assertEqual((k['r'], k['y']), ('f', 'n'))


class MenuCamera(unittest.TestCase):
    def test_right_stick_is_the_arrows_in_menus(self):
        k = key_icons.labels('', '', menu=True)
        self.assertEqual((k['look_left'], k['look_right']), ('left', 'right'))
        world, menu = key_icons.glyphs(key_icons.labels('', '')), key_icons.glyphs(k, menu=True)
        self.assertEqual(world[18].kind, 'mouse')   # the camera in the world: the mouse
        self.assertEqual(menu[18].kind, 'keys')     # rotating Link in the inventory: the arrow keys


class Yaz0Patch(unittest.TestCase):
    def test_changed_bytes_only(self):
        import nx
        # A hand-made stream: 8 literals "abcdefgh", then a copy of 16 bytes from 8 back (dist 8, len 16), then "XY".
        raw = b'Yaz0' + (26).to_bytes(4, 'big') + bytes(8)
        raw += bytes([0xff]) + b'abcdefgh' + bytes([0b01100000]) + bytes([0xe0, 0x07]) + b'XY'
        d = nx.yaz0_decode(raw)
        self.assertEqual(d, b'abcdefgh' + b'abcdefgh' * 2 + b'XY')
        d2 = bytearray(d); d2[2] = ord('Z')   # the copy's source changes: the copy becomes literals
        out = nx.yaz0_patch(raw, bytes(d2), [(2, 3)])
        self.assertEqual(nx.yaz0_decode(out), bytes(d2))
        d3 = bytearray(d); d3[25] = ord('!')
        out = nx.yaz0_patch(raw, bytes(d3), [(25, 26)])
        self.assertEqual(nx.yaz0_decode(out), bytes(d3))
        self.assertLessEqual(len(out), len(raw) + 2)   # the copy kept


class SarcResize(unittest.TestCase):
    @unittest.skipUnless((key_icons.ROMFS/'romfs.bin').exists(), 'the game files are not here')
    def test_grow_one_file_of_bootup(self):
        import nx, struct
        arc = key_icons.romfs_file('Pack/Bootup.pack')
        before = {n: arc[a:e] for n, a, e in nx.sarc_files(arc)}
        out = nx.sarc_replace(arc, 'Layout/Common.sblarc', b'9' * (len(before['Layout/Common.sblarc']) + 12345))
        after = {n: out[a:e] for n, a, e in nx.sarc_files(out)}
        self.assertEqual(after['Layout/Common.sblarc'], b'9' * (len(before['Layout/Common.sblarc']) + 12345))
        self.assertEqual({n: v for n, v in after.items() if n != 'Layout/Common.sblarc'},
                         {n: v for n, v in before.items() if n != 'Layout/Common.sblarc'})
        self.assertEqual(struct.unpack_from('<I', out, 8)[0], len(out))
        starts = {n: a for n, a, e in nx.sarc_files(arc)}; moved = {n: a for n, a, e in nx.sarc_files(out)}
        self.assertTrue(all((moved[n] - starts[n]) % 0x2000 == 0 for n in starts))   # alignments kept


class Sheet(unittest.TestCase):
    def test_bc4_block_round_trip(self):
        px = [0, 255] * 8
        self.assertEqual(bntx_bc4.bc4_decode_block(bntx_bc4.bc4_encode_block(px)), px)
        self.assertEqual(bntx_bc4.bc4_decode_block(bntx_bc4.bc4_encode_block([0] * 16)), [0] * 16)

    @unittest.skipUnless((key_icons.ROMFS/'romfs.bin').exists(), 'the game files are not here')
    def test_game_font_unchanged_round_trip(self):
        import sys
        sys.path.insert(0, str(key_icons.Path(__file__).resolve().parents[2]/'games/totk/scripts'))
        import make_mod_manifest as m
        o, s = m.read_index(key_icons.ROMFS/'runtime-index.bin')['Font/Font_US.sbfarc']
        with open(key_icons.ROMFS/'romfs.bin', 'rb') as rom:
            rom.seek(o); arc = key_icons.yaz0_decode(rom.read(s))
        a, e = next((a, e) for n, a, e in key_icons.sarc_files(arc) if n == key_icons.FONT)
        font = arc[a:e]
        self.assertEqual(bntx_bc4.encode(font, bntx_bc4.decode(font)), font)

    def test_tex_round_trip(self):
        w, h, bh = 60, 65, 2
        for fmt in (0x201, 0x1d01):
            wb, hb, bpb, size = bntx_bc4.level_geometry(w, h, bh, fmt)
            px = bytes(255 if (x // 8 + y // 8) % 2 else 0 for y in range(h) for x in range(w))
            data = bntx_bc4.write_tex(bytes(size + 16), (16, w, h, bh, fmt), px)
            self.assertEqual(bntx_bc4.read_tex(data, (16, w, h, bh, fmt)), px)

    def test_swizzle_round_trip(self):
        w, h, bh = 32, 256, 16
        lin = bytes(i * 7 % 251 for i in range(w * h * 8))
        size = w * 8 * h
        self.assertEqual(bntx_bc4.deswizzle(bntx_bc4.swizzle(lin, w, h, 8, bh, size), w, h, 8, bh), lin)


if __name__ == '__main__':
    unittest.main()
