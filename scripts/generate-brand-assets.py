#!/usr/bin/env python3
"""Rebuild mobile branding from the supplied wordmark (requires Pillow)."""
import json
from pathlib import Path
from PIL import Image
root = Path(__file__).resolve().parents[1] / 'apps/mobile'
logo = Image.open(root / 'assets/brand/biobalance-logo.jpg').convert('RGBA')
mask = Image.new('L', logo.size)
mask.putdata([255 if a > 0 and g > r + 20 and g > b + 20 else 0 for r,g,b,a in logo.get_flattened_data()])
x0,y0,x1,y1 = mask.getbbox()
leaf = logo.crop((max(0,x0-5),max(0,y0-5),min(logo.width,x1+5),min(logo.height,y1+5)))

def icon(size, transparent=False):
    canvas = Image.new('RGBA',(size,size),(255,255,255,0 if transparent else 255))
    artwork = leaf.copy()
    scale=size*.62/max(artwork.size)
    artwork=artwork.resize((round(artwork.width*scale),round(artwork.height*scale)),Image.Resampling.LANCZOS)
    canvas.alpha_composite(artwork,((size-artwork.width)//2,(size-artwork.height)//2))
    return canvas if transparent else canvas.convert('RGB')

res=root/'android/app/src/main/res'
for density,scale in [('mdpi',1),('hdpi',1.5),('xhdpi',2),('xxhdpi',3),('xxxhdpi',4)]:
    folder=res/f'mipmap-{density}';folder.mkdir(exist_ok=True)
    icon(round(48*scale)).save(folder/'ic_launcher.png')
    icon(round(108*scale),True).save(folder/'ic_launcher_foreground.png')
    folder=res/f'drawable-{density}';folder.mkdir(exist_ok=True)
    width=round(240*scale);height=round(width*logo.height/logo.width)
    logo.resize((width,height),Image.Resampling.LANCZOS).save(folder/'launch_image.png')
for folder in ['drawable','drawable-v21']:
    (res/folder/'launch_background.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
  <item android:drawable="@android:color/white" />
  <item><bitmap android:gravity="center" android:src="@drawable/launch_image" /></item>
</layer-list>
''')
folder=res/'mipmap-anydpi-v26';folder.mkdir(exist_ok=True)
(folder/'ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@android:color/white" />
  <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')
for qualifier in ['values-v31','values-night-v31']:
    folder=res/qualifier;folder.mkdir(exist_ok=True)
    (folder/'styles.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources>
  <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
    <item name="android:windowSplashScreenBackground">@android:color/white</item>
    <item name="android:windowSplashScreenAnimatedIcon">@mipmap/ic_launcher</item>
    <item name="android:windowBackground">@drawable/launch_background</item>
  </style>
</resources>
''')
assets=root/'ios/Runner/Assets.xcassets'
icons=assets/'AppIcon.appiconset'
for item in json.loads((icons/'Contents.json').read_text())['images']:
    size=round(float(item['size'].split('x')[0])*float(item['scale'].removesuffix('x')))
    icon(size).save(icons/item['filename'])
for scale,suffix in [(1,''),(2,'@2x'),(3,'@3x')]:
    width=240*scale
    logo.resize((width,round(width*logo.height/logo.width)),Image.Resampling.LANCZOS).save(assets/'LaunchImage.imageset'/f'LaunchImage{suffix}.png')
print('Generated Android/iOS icons and launch images from BioBalance assets.')
