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

    def test_swizzle_round_trip(self):
        w, h, bh = 32, 256, 16
        lin = bytes(i * 7 % 251 for i in range(w * h * 8))
        size = w * 8 * h
        self.assertEqual(bntx_bc4.deswizzle(bntx_bc4.swizzle(lin, w, h, 8, bh, size), w, h, 8, bh), lin)


if __name__ == '__main__':
    unittest.main()
