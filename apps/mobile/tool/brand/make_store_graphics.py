"""The Google Play feature graphic (1024 × 500) and the 512 px store icon, from the vector mark.

    python tool/brand/make_store_graphics.py      (run from apps/mobile; needs pycairo, pillow)
Written to build/store/.
"""
import os
import sys

import cairo
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import make_icons  # noqa: E402  (renders the mark)

os.makedirs('build/store', exist_ok=True)
W, H = 1024, 500
EMERALD = (12 / 255, 107 / 255, 69 / 255)

surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
ctx = cairo.Context(surface)
ctx.set_source_rgb(*EMERALD)
ctx.paint()
# Soft rings, like the headline cards of the app.
for r, a in [(260, 0.07), (180, 0.06)]:
    ctx.set_source_rgba(1, 1, 1, a)
    ctx.set_line_width(36)
    ctx.arc(W - 120, H + 40, r, 0, 6.3)
    ctx.stroke()
# The mark on a white tile at the left.
tile = 260
ctx.save()
ctx.translate(96, (H - tile) / 2)
ctx.new_path()
radius = 58
ctx.arc(tile - radius, radius, radius, -1.5708, 0)
ctx.arc(tile - radius, tile - radius, radius, 0, 1.5708)
ctx.arc(radius, tile - radius, radius, 1.5708, 3.1416)
ctx.arc(radius, radius, radius, 3.1416, 4.7124)
ctx.close_path()
ctx.set_source_rgb(1, 1, 1)
ctx.fill()
make_icons.mark(ctx, tile, 0.74)
ctx.restore()
surface.write_to_png('build/store/feature-graphic.png')

img = Image.open('build/store/feature-graphic.png').convert('RGB')
draw = ImageDraw.Draw(img)


def font(size, weight):
    f = ImageFont.truetype('assets/fonts/Inter.ttf', size)
    # Inter is a variable font: set its weight axis (and leave the others at their default).
    axes = f.get_variation_axes()
    f.set_variation_by_axes(
        [weight if a['name'] in (b'Weight', 'Weight') else a['default'] for a in axes]
    )
    return f


draw.text((410, 170), 'BioBalance', font=font(84, 800), fill='white')
draw.text((414, 282), 'Ventes · Stock · Récompenses', font=font(34, 600), fill=(222, 245, 233))
draw.text((414, 330), 'Sales · Stock · Rewards', font=font(28, 500), fill=(170, 220, 196))
img.save('build/store/feature-graphic.png')

make_icons.render('build/store/play-icon-512.png', 512, 0.70, background=make_icons.WHITE)
print('build/store/feature-graphic.png, build/store/play-icon-512.png')
