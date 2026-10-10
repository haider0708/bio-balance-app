"""Traces the BioBalance leaf mark from the logo into a vector (assets/brand/leaf-mark.svg).

The only source of the mark is a small raster logo; tracing it once gives smooth outlines that
every icon size is rendered from (tool/brand/make_icons.py). Needs: numpy, pillow, potracer.
"""
import numpy as np
from PIL import Image, ImageFilter
import potrace

SRC = 'assets/brand/biobalance-logo.jpg'
OUT = 'assets/brand/leaf-mark.svg'
LEAF = '#74BC1F'
VEIN = '#126B3C'
SCALE = 10

im = Image.open(SRC).convert('RGB')
a = np.asarray(im).astype(int)
green = (a[..., 1] > a[..., 0] + 25) & (a[..., 1] > a[..., 2] + 25)
ys, xs = np.where(green)
pad = 3
box = (xs.min() - pad, ys.min() - pad, xs.max() + pad + 1, ys.max() + pad + 1)
crop = im.crop(box)
big = crop.resize((crop.width * SCALE, crop.height * SCALE), Image.BICUBIC)


def channels(blur):
    # Blurring before the threshold turns the source's pixel steps into smooth edges.
    b = np.asarray(big.filter(ImageFilter.GaussianBlur(SCALE * blur))).astype(int)
    return b[..., 0], b[..., 1], b[..., 2]


r, g, bl = channels(0.9)
leaf_mask = (g > r + 20) & (g > bl + 20)
# The thin line between the two leaves stays open: inside the shape, what is not green at a
# finer blur is that line.
def morph(mask, f):
    return np.asarray(Image.fromarray(mask.astype('uint8') * 255).filter(f)) > 0


r, g, bl = channels(0.2)
inside = morph(leaf_mask, ImageFilter.MinFilter(15))
gap = inside & ~((g > r + 20) & (g > bl + 20))
# The source line is one pixel wide and broken: fit one smooth curve through it and cut along it.
gy, gx = np.where(gap)
fit = np.poly1d(np.polyfit(gy, gx, 3))
cut = Image.new('L', big.size, 0)
from PIL import ImageDraw
top, bottom = gy.min() - SCALE * 2, gy.max() + SCALE
ImageDraw.Draw(cut).line(
    [(float(fit(y)), float(y)) for y in range(int(top), int(bottom), 4)],
    fill=255, width=int(SCALE * 0.9), joint='curve')
leaf_mask &= ~(np.asarray(cut) > 0)
# Veins are a blue-ish dark green; the leaf's edge fading into the dark background is not.
r, g, bl = channels(0.3)
vein_mask = (g > r + 30) & (bl > r + 10) & ((r + g + bl) / 3 < 100)


def trace(mask):
    # potrace fills the dark pixels: the shape goes in as False.
    bmp = potrace.Bitmap(~mask)
    path = bmp.trace(turdsize=SCALE * SCALE * 2, alphamax=1.0, opticurve=True, opttolerance=0.8)
    d = []
    for curve in path:
        sp = curve.start_point
        d.append(f'M{sp.x:.1f},{sp.y:.1f}')
        for seg in curve.segments:
            if seg.is_corner:
                d.append(f'L{seg.c.x:.1f},{seg.c.y:.1f}L{seg.end_point.x:.1f},{seg.end_point.y:.1f}')
            else:
                d.append(f'C{seg.c1.x:.1f},{seg.c1.y:.1f} {seg.c2.x:.1f},{seg.c2.y:.1f} {seg.end_point.x:.1f},{seg.end_point.y:.1f}')
        d.append('Z')
    return ''.join(d)


w, h = big.size
svg = (
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}">'
    f'<path fill="{LEAF}" fill-rule="evenodd" d="{trace(leaf_mask)}"/>'
    f'<path fill="{VEIN}" fill-rule="evenodd" d="{trace(vein_mask)}"/>'
    '</svg>\n'
)
open(OUT, 'w').write(svg)
print(OUT, w, h, len(svg))
