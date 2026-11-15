"""Makes the Bleu Home app icon and in-app logo from the Bleu Land logo.

    python3 tool/make_icon.py

Source: tool/brand/bleuland_logo.webp (the company logo, 2000 x 2000).
The vertical "BLEULAND" text is left out: unreadable at icon size, and the
phone writes the app name under the icon anyway.
"""
from PIL import Image, ImageDraw

LOGO_BG = (0, 0, 25)                 # the navy in the logo file, #000019
BG = (6, 9, 42)                      # icon background: the logo navy, a touch lighter so it reads on black, #06092A
SYMBOL_BOX = (524, 324, 1482, 1676)  # the circuit "B" in the source, incl. its glow
TEXT_BOX = (552, 510, 606, 1478)     # the vertical text, painted over

RES = 'android/app/src/main/res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def mark():
    im = Image.open('tool/brand/bleuland_logo.webp').convert('RGB')
    ImageDraw.Draw(im).rectangle(TEXT_BOX, fill=LOGO_BG)
    im = im.crop(SYMBOL_BOX)
    # put the symbol on the new background: each pixel is part symbol, part
    # logo navy; swap only the navy part (keeps the glow and shading)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            p = px[x, y]
            a = max(max(0, p[c] - LOGO_BG[c]) / (255 - LOGO_BG[c]) for c in range(3))
            a = min(1.0, a)
            px[x, y] = tuple(round(p[c] + (1 - a) * (BG[c] - LOGO_BG[c])) for c in range(3))
    return im


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
    # so a symbol 62 % tall here ends up ~42 % of the layer (~63 % of the
    # visible icon), well inside the 66 dp safe circle, with room around it.
    FG = 0.62
    for d, k in DENSITIES.items():
        square(sym, round(108 * k), FG).save(f'{RES}/drawable-{d}/ic_launcher_foreground.png')
        # older Androids (6-7): a ready-made rounded square
        square(sym, round(48 * k), 0.56, 0.2).save(f'{RES}/mipmap-{d}/ic_launcher.png')
    square(sym, 1024, FG).save('assets/images/icon_foreground.png')
    square(sym, 1024, 0.56).save('assets/images/icon.png')
    square(sym, 512, 0.64).save('assets/images/logo_mark.png')  # in-app logo (BrandMark)


if __name__ == '__main__':
    main()
