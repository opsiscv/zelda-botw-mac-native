"""BC4 textures of a BNTX (inside a BFFNT font sheet): Tegra block-linear swizzle, decode to a grey image, encode back."""
import struct

GOB_W, GOB_H = 64, 8   # bytes, rows


def gob_offset(x, y):   # x: byte within the 64-byte GOB row, y: row within the GOB
    return ((x % 64) // 32) * 256 + ((y % 8) // 2) * 64 + ((x % 32) // 16) * 32 + (y % 2) * 16 + (x % 16)


def swizzle_index(x, y, width_bytes, block_height):
    gobs_x = (width_bytes + GOB_W - 1) // GOB_W
    gob_x, gob_y = x // GOB_W, y // GOB_H
    block_row = gob_y // block_height
    return (block_row * gobs_x * block_height + gob_x * block_height + gob_y % block_height) * 512 + gob_offset(x, y)


def deswizzle(data, w_blocks, h_blocks, bpb, block_height):
    out = bytearray(w_blocks * h_blocks * bpb); wb = w_blocks * bpb
    for y in range(h_blocks):
        for x in range(wb):
            out[y * wb + x] = data[swizzle_index(x, y, wb, block_height)]
    return bytes(out)


def swizzle(linear, w_blocks, h_blocks, bpb, block_height, size):
    out = bytearray(size); wb = w_blocks * bpb
    for y in range(h_blocks):
        for x in range(wb):
            out[swizzle_index(x, y, wb, block_height)] = linear[y * wb + x]
    return bytes(out)


def sheet(font):
    """(data offset, size, width, height, block height) of the first BC4 texture in a BFFNT."""
    i = font.index(b'BRTI')
    fmt, = struct.unpack_from('<I', font, i + 0x1c)
    w, h = struct.unpack_from('<II', font, i + 0x24)
    block_height = 1 << struct.unpack_from('<I', font, i + 0x34)[0]
    assert fmt >> 8 == 0x1d, f'not BC4: {fmt:#x}'
    j = font.index(b'BRTD'); size = struct.unpack_from('<I', font, j + 8)[0] - 0x10
    return j + 0x10, size, w, h, block_height


def bc4_decode_block(b):
    r0, r1 = b[0], b[1]
    pal = [r0, r1] + ([((6 - k) * r0 + (k + 1) * r1) // 7 for k in range(6)] if r0 > r1 else
                      [((4 - k) * r0 + (k + 1) * r1) // 5 for k in range(4)] + [0, 255])
    bits = int.from_bytes(b[2:8], 'little')
    return [pal[(bits >> (3 * k)) & 7] for k in range(16)]


def bc4_encode_block(px):   # 16 values: endpoints min/max, 8-value palette (r0 > r1)
    hi, lo = max(px), min(px)
    if hi == lo: return bytes([hi, lo]) + bytes(6) if hi else bytes([0, 0]) + bytes(6)
    pal = [hi, lo] + [((6 - k) * hi + (k + 1) * lo) // 7 for k in range(6)]
    bits = 0
    for k, v in enumerate(px):
        bits |= min(range(8), key=lambda i: abs(pal[i] - v)) << (3 * k)
    return bytes([hi, lo]) + bits.to_bytes(6, 'little')


def decode(font):
    """Grey pixels (rows of bytes) of the font's sheet, and its geometry."""
    off, size, w, h, bh = sheet(font)
    lin = deswizzle(font[off:off + size], w // 4, h // 4, 8, bh)
    img = [bytearray(w) for _ in range(h)]
    for by in range(h // 4):
        for bx in range(w // 4):
            px = bc4_decode_block(lin[(by * (w // 4) + bx) * 8:][:8])
            for k, v in enumerate(px): img[by * 4 + k // 4][bx * 4 + k % 4] = v
    return img


def encode(font, img):
    """The font with its sheet replaced by img (same size). Blocks img leaves as they decode keep their bytes."""
    off, size, w, h, bh = sheet(font)
    old = deswizzle(font[off:off + size], w // 4, h // 4, 8, bh)
    lin = bytearray()
    for by in range(h // 4):
        for bx in range(w // 4):
            px = [img[by * 4 + k // 4][bx * 4 + k % 4] for k in range(16)]
            block = old[(by * (w // 4) + bx) * 8:][:8]
            lin += block if bc4_decode_block(block) == px else bc4_encode_block(px)
    out = bytearray(font); out[off:off + size] = swizzle(bytes(lin), w // 4, h // 4, 8, bh, size)
    return bytes(out)
