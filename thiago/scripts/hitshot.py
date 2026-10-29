"""hitshot.py <shot.png> <log> <out.png>: the last uilist hit boxes drawn on a game shot (the picture: 1920x1080 at the
shot's top-left; layout units 1280x720, centre 0,0, y up)."""
import re, sys
from PIL import Image, ImageDraw
shot, log, out = sys.argv[1:4]
lines = open(log, errors='replace').read().splitlines()
start = max(i for i, l in enumerate(lines) if '[uilist] obj+00' in l)
hits = [re.search(r'hit (\d+) (\S+) (\S+) (\S+)x(\S+)( \(selected\))?', l) for l in lines[start:] if '[uilist] hit ' in l]
im = Image.open(shot).convert('RGB').crop((0, 0, 1920, 1080)); d = ImageDraw.Draw(im)
for m in hits:
    i, x, y, w, h, sel = int(m[1]), float(m[2]), float(m[3]), float(m[4]), float(m[5]), m[6]
    k = 1.5; x0, y0 = (x - w / 2 + 640) * k, (360 - y - h / 2) * k
    d.rectangle((x0, y0, x0 + w * k, y0 + h * k), outline=(255, 40, 40) if sel else (40, 255, 80), width=3)
    d.text((x0 + 4, y0 + 2), str(i), fill=(255, 255, 0))
im.resize((960, 540)).save(out)
