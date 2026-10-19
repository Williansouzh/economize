"""Gera o ícone do Economizze (cofrinho branco com moeda dourada sobre gradiente verde)
e grava todos os tamanhos: Android (adaptativo, monocromático e legado), iOS e web.

Rodar a partir de mobile/:  python3 tool/make_icon.py   (precisa do Pillow)
O fundo do ícone adaptativo do Android é vetorial: drawable/ic_launcher_background.xml.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # desenha grande e reduz (antialias)
GREEN_TOP, GREEN_BOTTOM = (0, 200, 128), (0, 112, 72)
WHITE = (255, 255, 255, 255)
GOLD, GOLD_DARK = (255, 196, 44, 255), (222, 150, 0, 255)


def gradient(size):
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(GREEN_TOP, GREEN_BOTTOM))
        d.line([(0, y), (size, y)], fill=c + (255,))
    return img


def piggy(size, body=WHITE, coin=True, slot=(0, 150, 96, 255)):
    """Cofrinho de perfil. Desenhado em coordenadas de 0 a 100 e depois centralizado e reduzido
    para caber no círculo seguro do adaptive icon do Android (raio ~30% do quadro)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = size / 100

    def P(x, y):  # centraliza (o desenho original vai de y=15 a 72) e reduz 10%
        return ((x - 50) * 0.9 + 50) * u, ((y - 43.5) * 0.9 + 50) * u

    def box(x0, y0, x1, y1):
        (a, b), (c, e) = P(x0, y0), P(x1, y1)
        return [a, b, c, e]

    r = lambda v: v * 0.9 * u
    for x in (37, 56):  # pernas
        d.rounded_rectangle(box(x, 60, x + 8, 72), radius=r(3), fill=body)
    d.arc(box(19, 41, 29, 51), start=90, end=330, fill=body, width=round(r(2.6)))  # rabinho
    d.ellipse(box(24, 36, 76, 68), fill=body)  # corpo
    # Orelha: elipse inclinada para trás, com a base escondida no corpo
    ear = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(ear).ellipse(box(55, 29, 65, 45), fill=body)
    img.alpha_composite(ear.rotate(-28, center=P(60, 41), resample=Image.BICUBIC))
    d.rounded_rectangle(box(70, 47, 81, 58), radius=r(4), fill=body)  # focinho
    if body == WHITE:
        for nx in (74, 77.5):
            d.ellipse(box(nx - 1, 51, nx + 1, 54), fill=slot)  # narinas
        d.ellipse(box(62, 44, 65.5, 47.5), fill=(20, 40, 32, 255))  # olho
        d.rounded_rectangle(box(43, 37.5, 57, 40.5), radius=r(1.5), fill=slot)  # fenda
    if coin:
        d.ellipse(box(42, 15, 58, 31), fill=GOLD_DARK)
        d.ellipse(box(43.2, 16.2, 56.8, 29.8), fill=GOLD)
        d.rounded_rectangle(box(48.8, 18.5, 51.2, 27.5), radius=r(1), fill=GOLD_DARK)
    return img


def shadow(fg, size):
    """Sombra suave sob o cofrinho para dar volume."""
    alpha = fg.split()[3]
    sh = Image.new("RGBA", fg.size, (0, 60, 38, 0))
    sh.putalpha(alpha.point(lambda a: a * 0.35))
    sh = sh.transform(fg.size, Image.AFFINE, (1, 0, 0, 0, 1, -size * 0.012))
    return sh.filter(ImageFilter.GaussianBlur(size * 0.012))


def rounded_mask(size, radius_ratio=0.225):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=size * radius_ratio, fill=255)
    return m


bg = gradient(S)
fg = piggy(S)
fg_with_shadow = Image.alpha_composite(shadow(fg, S), fg)
full = Image.alpha_composite(bg, fg_with_shadow)
rounded = full.copy()
rounded.putalpha(rounded_mask(S))
mono = piggy(S, body=WHITE, coin=True)

import os
import re

images = {"full": full.convert("RGB"), "rounded": rounded, "fg": fg_with_shadow, "mono": mono}


def save(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)


res = "android/app/src/main/res"
for dpi, mult in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
    save(images["rounded"], f"{res}/mipmap-{dpi}/ic_launcher.png", round(48 * mult))
    save(images["fg"], f"{res}/mipmap-{dpi}/ic_launcher_foreground.png", round(108 * mult))
    save(images["mono"], f"{res}/mipmap-{dpi}/ic_launcher_monochrome.png", round(108 * mult))
    # Ícone dos lembretes na barra de status: a silhueta branca, sem a margem do ícone adaptativo.
    os.makedirs(f"{res}/drawable-{dpi}", exist_ok=True)
    m = images["mono"].size[0]
    save(images["mono"].crop((m // 6, m // 6, m - m // 6, m - m // 6)), f"{res}/drawable-{dpi}/ic_notification.png", round(24 * mult))

# iOS: o tamanho sai do nome do arquivo (ex.: Icon-App-20x20@3x.png → 60 px). Sem transparência.
ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for name in os.listdir(ios):
    m = re.fullmatch(r"Icon-App-([\d.]+)x[\d.]+@(\d)x\.png", name)
    if m:
        save(images["full"], f"{ios}/{name}", round(float(m.group(1)) * int(m.group(2))))

save(images["rounded"], "web/favicon.png", 32)
save(images["rounded"], "web/icons/Icon-192.png", 192)
save(images["rounded"], "web/icons/Icon-512.png", 512)
save(images["full"], "web/icons/Icon-maskable-192.png", 192)
save(images["full"], "web/icons/Icon-maskable-512.png", 512)

# Mascote das telas de splash, apresentação e configuração (o mesmo cofrinho, sem fundo).
save(images["fg"], "assets/mascot.png", 512)
print("Ícones gerados.")
