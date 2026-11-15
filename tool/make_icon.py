"""Makes the Bleu Home app icon and in-app logo from the Bleu Land logo.

    python3 tool/make_icon.py

Source: tool/brand/bleuland_logo.webp (the company logo, 2000 x 2000).
The vertical "BLEULAND" text is left out: unreadable at icon size, and the
phone writes the app name under the icon anyway.
"""
from PIL import Image, ImageDraw

BG = (0, 0, 25)                      # the logo's navy, #000019
SYMBOL_BOX = (524, 324, 1482, 1676)  # the circuit "B" in the source, incl. its glow
TEXT_BOX = (552, 510, 606, 1478)     # the vertical text, painted over

RES = 'android/app/src/main/res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def mark():
    im = Image.open('tool/brand/bleuland_logo.webp').convert('RGB')
    ImageDraw.Draw(im).rectangle(TEXT_BOX, fill=BG)
    return im.crop(SYMBOL_BOX)


def square(sym, side, height_frac, radius_frac=0.0):
    """The symbol centred on a navy square, the symbol's height a fraction of the side."""
    h = round(side * height_frac)
    w = round(sym.width * h / sym.height)
    out = Image.new('RGB', (side, side), BG)
    out.paste(sym.resize((w, h), Image.LANCZOS), ((side - w) // 2, (side - h) // 2))
    if radius_frac:
        m = Image.new('L', (side, side), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, side - 1, side - 1], round(side * radius_frac), fill=255)
        rgba = out.convert('RGBA'); rgba.putalpha(m); return rgba
    return out


def main():
    sym = mark()
    # Adaptive icon (Android 8+): ic_launcher.xml insets the foreground by 16 %,
    # so a symbol 74 % tall here ends up ~50 % of the icon: inside the 66 dp
    # safe circle every launcher shape keeps.
    for d, k in DENSITIES.items():
        square(sym, round(108 * k), 0.74).save(f'{RES}/drawable-{d}/ic_launcher_foreground.png')
        # older Androids (6-7): a ready-made rounded square
        square(sym, round(48 * k), 0.66, 0.2).save(f'{RES}/mipmap-{d}/ic_launcher.png')
    square(sym, 1024, 0.74).save('assets/images/icon_foreground.png')
    square(sym, 1024, 0.66).save('assets/images/icon.png')
    square(sym, 512, 0.72).save('assets/images/logo_mark.png')  # in-app logo (BrandMark)


if __name__ == '__main__':
    main()
