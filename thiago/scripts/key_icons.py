"""Writes a RomFS mod whose button icons show the Mac's keys and mouse buttons instead of the Switch's.

The icons are the glyphs of the font External_00.bffnt (inside every Font/Font_*.sbfarc; the Xbox prompt mod of
gamebanana.com/mods/33340 changes the same font). Each icon shows the key that does that button's job in the world:
the default keys (games/totk/runtime/input.c, frontend.m), moved by keys.txt (runtime/key_map.h), and the mouse's left,
right and middle buttons from controls.txt. Run it again after changing either file, with the game closed, then the
manifest (README). python3 key_icons.py [--preview out.png]
"""
import struct, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import bntx_bc4
from nx import yaz0_decode, yaz0_encode, yaz0_patch, sarc_files, sarc_replace

DATA = Path.home()/'Library/Application Support/MacNativeGames/BotW'
ROMFS = Path.home()/'Downloads/Games/Zelda BOTW/basegame/BotW_build/totk/extracted/botw160/romfs'
OUT = DATA/'mods/botw160'
FONT = 'External_00.bffnt'

# The key behind each Switch button with no keys.txt (world context); ZR has no key (the right mouse button).
DEFAULT = {'a': 'e', 'b': 'shift', 'x': 'space', 'y': 'u', 'l': 'q', 'r': 'ctrl', 'zl': 'caps', 'zr': None,
           'plus': 'esc', 'minus': 'tab', 'lstick': 'z', 'rstick': 'c', 'dpad_left': 'f', 'dpad_up': 'g',
           'dpad_right': 'b', 'dpad_down': 'v', 'move_up': 'w', 'move_left': 'a', 'move_down': 's', 'move_right': 'd',
           'look_up': 'up', 'look_left': 'left', 'look_down': 'down', 'look_right': 'right'}
# In a menu (the world stopped: dialogs, the pause menu; runtime/frontend.m) these buttons come from other keys: the
# left click confirms (A), Esc goes back (B), E is the next tab (R), V sorts (Y). The right stick (rotating Link) is the
# arrow keys there: the mouse moves the pointer.
MENU = {'a': 'mouse_left', 'b': 'esc', 'r': 'e', 'y': 'v'}
CONTROLS_NAMES = {'left': 'dpad_left', 'up': 'dpad_up', 'right': 'dpad_right', 'down': 'dpad_down'}
MOUSE = ('mouse_left', 'mouse_right', 'mouse_middle')   # the side buttons only repeat keys: not shown


def lines(text):
    for line in text.splitlines():
        line = line.split('#')[0]
        if '=' in line:
            a, b = (s.strip().lower() for s in line.split('=', 1))
            yield a, b


def labels(keys_txt, controls_txt, menu=False):
    """Switch button -> the key or mouse button shown for it (None: nothing does it; the Switch icon stays)."""
    moved = dict(lines(keys_txt))
    out = {}
    for button, key in {**DEFAULT, **MENU}.items() if menu else DEFAULT.items():
        if key in MOUSE: out[button] = key; continue
        found = [p for p, t in moved.items() if t == key]
        out[button] = ([key] if key and key not in moved else []) + found
        out[button] = out[button][0] if out[button] else None
    for physical, value in lines(controls_txt):
        if physical in MOUSE and value.split():
            target = CONTROLS_NAMES.get(value.split()[0], value.split()[0])
            if not (menu and target in MENU): out[target] = physical
    return out


SYMBOLS = {'up': '↑', 'down': '↓', 'left': '←', 'right': '→'}
WORDS = {'esc': 'esc', 'ctrl': 'ctrl', 'shift': 'shift', 'space': 'space', 'caps': 'caps', 'tab': 'tab',
         'enter': 'enter', 'backspace': 'del', 'option': 'opt'}
SS = 4   # drawn 4 times larger, then scaled down (smooth edges)


def font(text, px):
    if text in SYMBOLS.values(): return ImageFont.truetype('/System/Library/Fonts/Apple Symbols.ttf', int(px * 1.25))
    return ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', px, index=1)


def cap(d, box, key):
    """A keycap filling box with its label cut out of it."""
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, radius=(y1 - y0) // 4, fill=255)
    if key in SYMBOLS: return arrow_hole(d, box, key)
    text = WORDS.get(key) or key.upper()
    px = int((y1 - y0) * 0.72)
    while True:
        f = font(text, px); l, t, r, b = d.textbbox((0, 0), text, font=f)
        if r - l <= (x1 - x0) * 0.82 and b - t <= (y1 - y0) * 0.72 or px < 8: break
        px -= SS
    d.text(((x0 + x1 - (r - l)) / 2 - l, (y0 + y1 - (b - t)) / 2 - t), text, font=f, fill=0)


def arrow_hole(d, box, way):
    x0, y0, x1, y1 = box; cx, cy, a = (x0 + x1) / 2, (y0 + y1) / 2, (y1 - y0) * 0.26
    tri = {'up': [(cx - a, cy + a * 0.6), (cx + a, cy + a * 0.6), (cx, cy - a * 0.8)],
           'down': [(cx - a, cy - a * 0.6), (cx + a, cy - a * 0.6), (cx, cy + a * 0.8)],
           'left': [(cx + a * 0.6, cy - a), (cx + a * 0.6, cy + a), (cx - a * 0.8, cy)],
           'right': [(cx - a * 0.6, cy - a), (cx - a * 0.6, cy + a), (cx + a * 0.8, cy)]}[way]
    d.polygon(tri, fill=0)


def mouse(d, box, button=None, arrow=None):
    """A mouse, its button filled; arrow: the way it is moved ('up', 'down', 'left', 'right', 'updown', 'leftright')."""
    x0, y0, x1, y1 = box; h = y1 - y0; w = h * 0.62
    cx = (x0 + x1) / 2 - (h * 0.18 if arrow else 0); s = SS * 2.2
    body = (cx - w / 2, y0, cx + w / 2, y1)
    d.rounded_rectangle(body, radius=w / 2, outline=255, width=int(s))
    mid = y0 + h * 0.42
    d.line((body[0], mid, body[2], mid), fill=255, width=int(s))
    d.line((cx, y0, cx, mid), fill=255, width=int(s))
    if button == 'mouse_left': d.pieslice((body[0], y0, body[2], y0 + w), 180, 270, fill=255); d.rectangle((body[0], y0 + w / 2, cx, mid), fill=255)
    if button == 'mouse_right': d.pieslice((body[0], y0, body[2], y0 + w), 270, 360, fill=255); d.rectangle((cx, y0 + w / 2, body[2], mid), fill=255)
    if button == 'mouse_middle': d.rounded_rectangle((cx - w * 0.2, y0 + h * 0.06, cx + w * 0.2, mid + h * 0.04), radius=w * 0.12, fill=255)
    if arrow:
        ax, ay, a = body[2] + h * 0.22, (y0 + y1) / 2, h * 0.16
        tri = {'up': [(ax - a, ay + a / 2), (ax + a, ay + a / 2), (ax, ay - a)],
               'down': [(ax - a, ay - a / 2), (ax + a, ay - a / 2), (ax, ay + a)],
               'left': [(ax + a / 2, ay - a), (ax + a / 2, ay + a), (ax - a, ay)],
               'right': [(ax - a / 2, ay - a), (ax - a / 2, ay + a), (ax + a, ay)]}
        for way in {'updown': ('up', 'down'), 'leftright': ('left', 'right')}.get(arrow, (arrow,)):
            shift = {'up': (0, -a * 0.9), 'down': (0, a * 0.9), 'left': (-a * 0.9, 0), 'right': (a * 0.9, 0)}[way] if arrow in ('updown', 'leftright') else (0, 0)
            d.polygon([(x + shift[0], y + shift[1]) for x, y in tri[way]], fill=255)


def cluster(d, box, up, left, down, right):
    """Four small caps: one on top, three below (W, A S D), or a cross (the d-pad) when left/right flank the middle."""
    x0, y0, x1, y1 = box; k = min((x1 - x0) / 3, (y1 - y0) / 2) - SS; g = SS
    cx = (x0 + x1) / 2; top = (y0 + y1) / 2 - k - g / 2
    for key, (x, y) in ((up, (cx - k / 2, top)), (left, (cx - k * 1.5 - g, top + k + g)), (down, (cx - k / 2, top + k + g)),
                        (right, (cx + k / 2 + g, top + k + g))):
        if key: cap(d, (x, y, x + k, y + k), key)


def pair(d, box, a, b, vertical=False):
    x0, y0, x1, y1 = box
    if vertical:
        k = (y1 - y0 - SS) / 2; cx = (x0 + x1) / 2
        cap(d, (cx - k * 0.6, y0, cx + k * 0.6, y0 + k), a); cap(d, (cx - k * 0.6, y1 - k, cx + k * 0.6, y1), b)
    else:
        k = min((x1 - x0 - SS) / 2, y1 - y0); cy = (y0 + y1) / 2
        cap(d, (x0, cy - k / 2, x0 + k, cy + k / 2), a); cap(d, (x1 - k, cy - k / 2, x1, cy + k / 2), b)


def one(key, mouse_arrow=None):
    def draw(d, box):
        if key in MOUSE: mouse(d, box, key, mouse_arrow)
        else: cap(d, box, key)
    draw.wide = key in WORDS   # a word: the whole cell's width (the glyph's width in CWDH grows to it)
    draw.kind = 'mouse' if key in MOUSE else 'keys'
    return draw if key else None


def kind(f, name):
    f.kind = name; return f


def glyphs(k, menu=False):
    """Glyph index (zeldaret-free: the order of the font's character map, 0 = U+E040) -> how to draw it."""
    mv = (k['move_up'], k['move_left'], k['move_down'], k['move_right'])
    dp = (k['dpad_up'], k['dpad_left'], k['dpad_down'], k['dpad_right'])
    g = {0: one(k['a']), 1: one(k['b']), 2: one(k['x']), 3: one(k['y']), 4: one(k['l']), 5: one(k['r']),
         6: one(k['zl']), 7: one(k['zr']), 11: one(k['plus']), 12: one(k['minus']),
         19: one(k['lstick']), 20: one(k['rstick']),
         15: one(k['move_up']), 13: one(k['move_down']), 21: one(k['move_right']), 23: one(k['move_left']),
         28: one(k['dpad_up']), 29: one(k['dpad_down']), 30: one(k['dpad_left']), 31: one(k['dpad_right'])}
    if all(mv): g[26] = lambda d, b: cluster(d, b, *mv)
    if k['move_left'] and k['move_right']: g[17] = lambda d, b: pair(d, b, k['move_left'], k['move_right'])
    if all(dp): g[9] = lambda d, b: cluster(d, b, *dp)
    if k['dpad_up'] and k['dpad_down']: g[32] = lambda d, b: pair(d, b, k['dpad_up'], k['dpad_down'], vertical=True)
    if k['dpad_left'] and k['dpad_right']: g[33] = lambda d, b: pair(d, b, k['dpad_left'], k['dpad_right'])
    # The right stick is the camera: the mouse moved; in a menu (rotating Link) the arrow keys.
    lk = (k['look_up'], k['look_left'], k['look_down'], k['look_right'])
    if menu:
        g.update({27: all(lk) and kind(lambda d, b: cluster(d, b, *lk), 'keys'), 14: one(k['look_down']), 16: one(k['look_up']),
                  22: one(k['look_right']), 24: one(k['look_left']),
                  18: k['look_left'] and k['look_right'] and kind(lambda d, b: pair(d, b, k['look_left'], k['look_right']), 'keys'),
                  25: k['look_up'] and k['look_down'] and kind(lambda d, b: pair(d, b, k['look_up'], k['look_down'], vertical=True), 'keys')})
    else:
        for i, way in ((27, None), (14, 'down'), (16, 'up'), (22, 'right'), (24, 'left'), (18, 'leftright'), (25, 'updown')):
            g[i] = kind((lambda w: lambda d, b: mouse(d, b, None, w))(way), 'mouse')
    return {i: f for i, f in g.items() if f}


CELL_W, CELL_H, COLS = 44, 39, 2


WIDE = (1, CELL_W - 1)   # a wide glyph's columns in its cell


def redraw(img, draws):
    """img: the decoded sheet (rows bottom-up, as stored). Each glyph's cell is cleared and redrawn inside the box its
    original icon used (so its width and spacing in the text stay), or across the cell for a wide one."""
    h = len(img)
    for i, draw in draws.items():
        r, c = divmod(i, COLS); x0, y0 = c * (CELL_W + 1) + 1, r * (CELL_H + 1) + 1
        rows = [img[h - 1 - (y0 + y)][x0:x0 + CELL_W] for y in range(CELL_H)]   # top-down
        xs = [x for row in rows for x, v in enumerate(row) if v > 40]; ys = [y for y, row in enumerate(rows) if max(row) > 40]
        box = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
        if getattr(draw, 'wide', False): box = (WIDE[0], box[1], WIDE[1], box[3])
        big = Image.new('L', (CELL_W * SS, CELL_H * SS), 0)
        draw(ImageDraw.Draw(big), tuple(v * SS for v in box))
        small = big.resize((CELL_W, CELL_H), Image.LANCZOS).tobytes()
        for y in range(CELL_H):
            img[h - 1 - (y0 + y)][x0:x0 + CELL_W] = small[y * CELL_W:(y + 1) * CELL_W]


def widths(fnt, wide):
    """CWDH (left, glyph width, advance) of the wide glyphs: the whole cell (the same in the world's and the menu's)."""
    fnt = bytearray(fnt); c = fnt.index(b'CWDH'); first = int.from_bytes(fnt[c + 8:c + 10], 'little')
    for i in wide:
        e = c + 16 + (i - first) * 3
        fnt[e:e + 3] = bytes((1, WIDE[1], WIDE[1] + 2))   # the bitmap starts at the cell's column 0
    return bytes(fnt)


def preview(img, path):
    sheet = Image.frombytes('L', (len(img[0]), len(img)), b''.join(bytes(r) for r in img)).transpose(Image.FLIP_TOP_BOTTOM)
    out = Image.new('L', (10 * 52, 5 * 46), 40)
    for i in range(49):
        r, c = divmod(i, COLS)
        out.paste(sheet.crop((c * 45 + 1, r * 40 + 1, c * 45 + 45, r * 40 + 40)), ((i % 10) * 52 + 4, (i // 10) * 46 + 4))
    out.resize((out.width * 2, out.height * 2), Image.LANCZOS).save(path)


def romfs_file(path):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'games/totk/scripts'))
    import make_mod_manifest as m
    o, s = m.read_index(ROMFS/'runtime-index.bin')[path]
    with open(ROMFS/'romfs.bin', 'rb') as rom:
        rom.seek(o); return rom.read(s)


# The HUD's own button pictures (Pack/Bootup.pack > Layout/Common.sblarc > timg/__Combined.bntx, R8 48x48: "A Mount",
# "X Jump"...), drawn as the font's glyph of the same button. The world's keys: the HUD is the world's.
HUD = {'Nt_KeyTexA_00^d': 0, 'Nt_KeyTexB_00^d': 1, 'Nt_KeyTexX_00^d': 2, 'Nt_KeyTexY_00^d': 3, 'Nt_KeyTexL_00^d': 4,
       'Nt_KeyTexZL_00^d': 6, 'Nt_KeyTexLSt_00^d': 15, 'Nt_KeyTexLSt_01^d': 26}
HUD_GONE = ('Nt_KeyBtnSubBaseAL_00^s', 'Nt_KeyBtnSubBaseBL_00^s')
PACK, LAYOUT, BNTX = 'Pack/Bootup.pack', 'Layout/Common.sblarc', 'timg/__Combined.bntx'


def hud_pack(draws):
    """Bootup.pack with the HUD's button pictures redrawn (only their bytes recompressed: nx.yaz0_patch)."""
    pack = romfs_file(PACK); layout = {n: (a, e) for n, a, e in sarc_files(pack)}[LAYOUT]
    c = pack[layout[0]:layout[1]]; d = bytearray(yaz0_decode(c))
    a, e = {n: (a, e) for n, a, e in sarc_files(d)}[BNTX]; tex = bntx_bc4.textures(d[a:e]); changed = []
    def redo(name, draw):   # the texture redrawn inside its own picture's box
        nonlocal d
        info = tex[name]; off, w, h, bh, fmt = info; px = bntx_bc4.read_tex(d[a:e], info)
        xs = [x for y in range(h) for x in range(w) if px[y * w + x] > 40]; ys = [y for y in range(h) for x in range(w) if px[y * w + x] > 40]
        box = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
        if getattr(draw, 'wide', False): box = (1, box[1], w - 1, box[3])
        big = Image.new('L', (w * SS, h * SS), 0); draw(ImageDraw.Draw(big), tuple(v * SS for v in box))
        bntx = bntx_bc4.write_tex(d[a:e], info, big.resize((w, h), Image.LANCZOS).tobytes())
        size = bntx_bc4.level_geometry(w, h, bh, fmt)[3]; d[a + off:a + off + size] = bntx[off:off + size]
        changed.append((a + off, a + off + size))
    for name, glyph in HUD.items():
        if glyph in draws: redo(name, draws[glyph])
    # The prompt's base: a key's rounded square instead of the Switch button's circle; the faint four-button guide
    # beside it (X / Y / B round A) left out.
    redo('Nt_KeyBtnBaseLL_00^s', lambda dr, b: dr.rounded_rectangle(b, radius=(b[3] - b[1]) // 4, fill=255))
    for name in HUD_GONE: redo(name, lambda dr, b: None)
    c2 = yaz0_patch(c, bytes(d), changed); assert yaz0_decode(c2) == bytes(d)
    return sarc_replace(pack, LAYOUT, c2)


def write_mod_file(path, data):
    dst = OUT/path
    if dst.exists() and dst.read_bytes() == data: print(path, 'unchanged')   # left alone: a running game checks its mod files
    else: dst.parent.mkdir(parents=True, exist_ok=True); dst.write_bytes(data); print(path, 'written (run the manifest again)')


def swapped_sheet(fnt):
    """The font's sheet as stored (swizzled BC4): what the runtime looks for in the game's memory and replaces."""
    off, size, *_ = bntx_bc4.sheet(fnt)
    return fnt[off:off + size]


def main():
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'games/totk/scripts'))
    import make_mod_manifest as m
    read = lambda p: p.read_text() if p.exists() else ''
    keys, controls = read(DATA/'keys.txt'), read(DATA/'controls.txt')
    world, menu = glyphs(labels(keys, controls)), glyphs(labels(keys, controls, menu=True), menu=True)
    print('icons:', labels(keys, controls)); print('in menus:', labels(keys, controls, menu=True))
    wide = sorted({i for d in (world, menu) for i, f in d.items() if getattr(f, 'wide', False)})
    for d in (world, menu):   # a glyph is as wide in both (its width is in the font data, not the sheet)
        for i in wide:
            if i in d: d[i].wide = True
    idx = m.read_index(ROMFS/'runtime-index.bin'); rom = open(ROMFS/'romfs.bin', 'rb')
    shown, pairs = None, []
    for path in sorted(p for p in idx if p.startswith('Font/Font_') and p.endswith('.sbfarc')):
        o, s = idx[path]; rom.seek(o); arc = bytearray(yaz0_decode(rom.read(s)))
        files = {n: (a, e) for n, a, e in sarc_files(arc)}
        if FONT not in files: continue
        a, e = files[FONT]; fnt = widths(bytes(arc[a:e]), wide)
        img = bntx_bc4.decode(fnt); redraw(img, world); out = bntx_bc4.encode(fnt, img)
        img2 = bntx_bc4.decode(fnt); redraw(img2, menu); pair = (swapped_sheet(out), swapped_sheet(bntx_bc4.encode(fnt, img2)))
        if pair not in pairs: pairs.append(pair)
        arc[a:e] = out   # the same size: the archive's layout holds
        write_mod_file(path, yaz0_encode(bytes(arc)))
        shown = shown or (img, img2)
    write_mod_file(PACK, hud_pack(world))
    # key_icons.bin (runtime/game_patches_botw.c): the menu sheet swapped in while the world is stopped.
    size = len(pairs[0][0])
    (DATA/'key_icons.bin').write_bytes(b'KICO' + struct.pack('<II', len(pairs), size) + b''.join(w + m for w, m in pairs))
    print(DATA/'key_icons.bin', len(pairs), 'sheets')
    if '--preview' in sys.argv and shown:
        p = sys.argv[sys.argv.index('--preview') + 1]
        preview(shown[0], p); preview(shown[1], p.replace('.png', '-menu.png'))


if __name__ == '__main__':
    main()
