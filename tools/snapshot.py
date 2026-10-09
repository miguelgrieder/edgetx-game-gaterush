#!/usr/bin/env python3
"""PBM helpers for golden masters (needs Pillow).

  snapshot.py png  <in.pbm> <out.png> [scale]       6x PNG with the mockup LCD palette
  snapshot.py diff <golden.pbm> <actual.pbm> <out.png>   red = only in golden, blue = only in actual
  snapshot.py sheet <out.png> <a.pbm> <b.pbm> ...   2-column contact sheet
"""
import sys
from PIL import Image

W, H = 128, 64
ON, OFF, FRAME = (20, 24, 20), (150, 165, 130), (90, 105, 80)


def read(path):
    toks = []
    for line in open(path):
        toks += line.split('#')[0].split()
    assert toks[0] == 'P1' and toks[1:3] == ['128', '64'], path
    bits = ''.join(toks[3:])
    return [int(c) for c in bits if c in '01']


def render(px, scale=6, colors=None):
    im = Image.new('RGB', ((W + 2) * scale, (H + 2) * scale), FRAME)
    p = im.load()
    for y in range(H):
        for x in range(W):
            c = colors(x, y) if colors else (ON if px[y * W + x] else OFF)
            for a in range(scale):
                for b in range(scale):
                    p[scale + x * scale + a, scale + y * scale + b] = c
    return im


def main(argv):
    cmd = argv[1]
    if cmd == 'png':
        render(read(argv[2]), int(argv[4]) if len(argv) > 4 else 6).save(argv[3])
    elif cmd == 'diff':
        g, a = read(argv[2]), read(argv[3])

        def col(x, y):
            i = y * W + x
            if g[i] == a[i]:
                return ON if g[i] else OFF
            return (220, 30, 30) if g[i] else (30, 60, 220)
        render(g, 6, col).save(argv[4])
        n = sum(1 for i in range(W * H) if g[i] != a[i])
        print(f'{n} pixels differ')
    elif cmd == 'sheet':
        out, files = argv[2], argv[3:]
        ims = [render(read(f), 3) for f in files]
        w, h = ims[0].size
        rows = (len(ims) + 1) // 2
        sheet = Image.new('RGB', (w * 2 + 6, rows * (h + 6)), (255, 255, 255))
        for i, im in enumerate(ims):
            sheet.paste(im, ((i % 2) * (w + 6), (i // 2) * (h + 6)))
        sheet.save(out)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
