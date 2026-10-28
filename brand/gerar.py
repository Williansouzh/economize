"""Gera a identidade visual do Economizze a partir de uma única fonte.

    pip install -r brand/requirements.txt
    python brand/gerar.py

Saídas:
  brand/svg/  símbolo, logos e mascote em vetor
  brand/png/  prévias para documentação
  mobile/...  ícones do Android, iOS, web, notificação, splash e o mascote do app
"""

from pathlib import Path

import cairosvg
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
BRAND, MOBILE = ROOT / "brand", ROOT / "mobile"
RES = MOBILE / "android/app/src/main/res"

# ---------- Paleta (contrastes conferidos: ver brand/README.md) ----------
TINTA = "#0B2B2E"   # texto, fundo do ícone, tema escuro
MAR = "#0C7A68"     # cor principal no tema claro (botões, links)
LIMA = "#C5F04A"    # destaque: moeda, "zz", ação principal; nunca texto sobre fundo claro
NEVOA = "#F2F6F4"   # fundo do tema claro
BRANCO = "#FFFFFF"
AMBAR = "#FFB547"   # ícone "atenção" (só no ícone do app, RN-49)
CORAL = "#FF7A6B"   # ícone "no vermelho" (só no ícone do app, RN-49)

# ---------- Símbolo: moeda com "zz" (viewBox 100x100, centro 50,50) ----------
COIN_R = 33          # raio da moeda
RING_W = 6.5         # aro da versão contorno
ZW = 8               # traço do z
Z_W, Z_H, Z_GAP, Z_RISE = 14, 20, 6, 8   # cada z; espaço entre eles; quanto o segundo sobe


def _z(x, y, w, h):
    return f"M{x:.1f},{y:.1f} H{x + w:.1f} L{x:.1f},{y + h:.1f} H{x + w:.1f}"


def zz_path(rise=Z_RISE):
    """rise: quanto o segundo z sobe. 0 = os dois no mesmo nível; negativo = desce (ícones de status)."""
    x0 = 50 - (2 * Z_W + Z_GAP) / 2
    y_first = 50 - Z_H / 2 + rise / 2         # o par fica centrado verticalmente
    return _z(x0, y_first, Z_W, Z_H) + " " + _z(x0 + Z_W + Z_GAP, y_first - rise, Z_W, Z_H)


def symbol_outline(fg):
    return (f'<circle cx="50" cy="50" r="{COIN_R - RING_W / 2}" fill="none" stroke="{fg}" stroke-width="{RING_W}"/>'
            f'<path d="{zz_path()}" fill="none" stroke="{fg}" stroke-width="{ZW}" stroke-linecap="round" stroke-linejoin="round"/>')


def symbol_solid(coin, zz, rise=Z_RISE):
    return (f'<circle cx="50" cy="50" r="{COIN_R}" fill="{coin}"/>'
            f'<path d="{zz_path(rise)}" fill="none" stroke="{zz}" stroke-width="{ZW + 1}" stroke-linecap="round" stroke-linejoin="round"/>')


def symbol_cutout(color):
    """Moeda cheia com o zz vazado, em SVG (máscara). Para PNG use cutout_png: o cairosvg ignora máscaras."""
    return (f'<defs><mask id="zz"><rect width="100" height="100" fill="#fff"/>'
            f'<path d="{zz_path()}" fill="none" stroke="#000" stroke-width="{ZW + 1}" stroke-linecap="round" stroke-linejoin="round"/></mask></defs>'
            f'<circle cx="50" cy="50" r="{COIN_R}" fill="{color}" mask="url(#zz)"/>')


def cutout_png(path, canvas, coin_diameter, px, rise=Z_RISE):
    """Silhueta branca da moeda com o zz transparente (notificação e ícone monocromático)."""
    coin = render(svg(canvas, canvas, placed(f'<circle cx="50" cy="50" r="{COIN_R}" fill="#fff"/>', canvas, coin_diameter)), px)
    zz = render(svg(canvas, canvas, placed(
        f'<path d="{zz_path(rise)}" fill="none" stroke="#fff" stroke-width="{ZW + 1}" stroke-linecap="round" stroke-linejoin="round"/>',
        canvas, coin_diameter)), px)
    alpha = Image.eval(coin.getchannel("A"), lambda a: a).point(lambda a: a)
    alpha = Image.composite(Image.new("L", alpha.size, 0), alpha, zz.getchannel("A").point(lambda a: 255 if a > 127 else a * 2))
    out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    out.save(path)


def placed(inner, canvas, coin_diameter, cx=None, cy=None):
    """Põe o símbolo num canvas, com a moeda do diâmetro pedido, centrada."""
    s = coin_diameter / (2 * COIN_R)
    cx = canvas / 2 if cx is None else cx
    cy = canvas / 2 if cy is None else cy
    return f'<g transform="translate({cx - 50 * s:.3f},{cy - 50 * s:.3f}) scale({s:.5f})">{inner}</g>'


def svg(w, h, body, bg=None, rx=0):
    rect = f'<rect width="{w}" height="{h}" rx="{rx}" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">{rect}{body}</svg>'


# ---------- Logotipo: Nunito Black em contorno, "zz" em destaque ----------
FONT = TTFont(MOBILE / "assets/fonts/Nunito-Black.ttf")
GLYPHS, CMAP, UPM = FONT.getGlyphSet(), FONT.getBestCmap(), FONT["head"].unitsPerEm
TRACK = -0.01


def wordmark(text_color, accent, size=100):
    """Paths de 'economizze' com a linha de base em y=0. Devolve (svg, largura, altura-x)."""
    scale, x, parts = size / UPM, 0.0, []
    for i, ch in enumerate("economizze"):
        g = CMAP[ord(ch)]
        pen = SVGPathPen(GLYPHS)
        GLYPHS[g].draw(TransformPen(pen, (scale, 0, 0, -scale, x, 0)))
        parts.append(f'<path d="{pen.getCommands()}" fill="{accent if i in (7, 8) else text_color}"/>')
        x += GLYPHS[g].width * scale + TRACK * size
    bp = BoundsPen(GLYPHS)
    GLYPHS[CMAP[ord("x")]].draw(bp)
    return "".join(parts), x - TRACK * size, bp.bounds[3] * scale


def logo_horizontal(text_color, accent, coin, zz):
    size = 100
    body, width, xh = wordmark(text_color, accent, size)
    sym, pad, gap = 1.05 * size, 0.10 * size, 0.06 * size
    w, h = pad + sym + gap + width + pad, sym + 2 * pad
    baseline = pad + sym / 2 + xh / 2
    inner = (f'<g transform="translate({pad},{pad}) scale({sym / 100})">{symbol_solid(coin, zz)}</g>'
             f'<g transform="translate({pad + sym + gap:.1f},{baseline:.1f})">{body}</g>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.0f} {h:.0f}">{inner}</svg>'


# ---------- Mascote: o cofrinho recebendo a moeda Economizze ----------
def mascot_body(shadow=False, eye=None):
    """Cofrinho em 512x512, no mesmo enquadramento do mascote anterior (folga embaixo).
    eye: SVG do olho no lugar do círculo padrão (poses)."""
    white = "#BFC9C7" if shadow else BRANCO
    detail = "#BFC9C7" if shadow else TINTA
    slot = "#BFC9C7" if shadow else MAR
    return f'''
<circle cx="132" cy="262" r="15" fill="none" stroke="{white}" stroke-width="9"/>
<rect x="196" y="318" width="38" height="66" rx="14" fill="{white}"/>
<rect x="284" y="318" width="38" height="66" rx="14" fill="{white}"/>
<ellipse cx="258" cy="282" rx="128" ry="82" fill="{white}"/>
<ellipse cx="320" cy="214" rx="20" ry="34" transform="rotate(28 320 214)" fill="{white}"/>
<rect x="348" y="266" width="52" height="60" rx="18" fill="{white}"/>
<rect x="364" y="285" width="7" height="18" rx="3.5" fill="{slot}"/>
<rect x="380" y="285" width="7" height="18" rx="3.5" fill="{slot}"/>
{eye if eye and not shadow else f'<circle cx="318" cy="262" r="9" fill="{detail}"/>'}
<rect x="222" y="226" width="68" height="13" rx="6.5" fill="{slot}"/>'''


def _zletter(x, y, s, color, width=7):
    return (f'<path d="M{x},{y} h{s} l-{s},{s} h{s}" fill="none" stroke="{color}" stroke-width="{width}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


# Poses do Cofrinho (direção de arte, out/2026): só em momentos, nunca em telas de dados.
# Cada pose: (olho, desenho na frente do corpo, centro y da moeda ou None).
_EYE_HAPPY = f'<path d="M306,266 q12,-16 24,0" fill="none" stroke="{TINTA}" stroke-width="7" stroke-linecap="round"/>'
_EYE_CLOSED = f'<path d="M306,260 q12,12 24,0" fill="none" stroke="{TINTA}" stroke-width="7" stroke-linecap="round"/>'
MASCOT_POSES = {
    # acenando: apresentação
    "acenando": (None,
        f'<rect x="354" y="215" width="38" height="112" rx="19" transform="rotate(39 373 325)" fill="{BRANCO}"/>'
        f'<path d="M462,196 q18,14 16,38 M482,172 q28,24 24,62" fill="none" stroke="{LIMA}" stroke-width="9" stroke-linecap="round"/>',
        158),
    # pensando: IA carregando
    "pensando": (f'<circle cx="324" cy="254" r="9" fill="{TINTA}"/>',
        f'<circle cx="362" cy="190" r="9" fill="{LIMA}"/><circle cx="386" cy="152" r="14" fill="{LIMA}"/>'
        f'<ellipse cx="430" cy="96" rx="58" ry="42" fill="{LIMA}"/>'
        f'<circle cx="408" cy="96" r="7" fill="{TINTA}"/><circle cx="430" cy="96" r="7" fill="{TINTA}"/><circle cx="452" cy="96" r="7" fill="{TINTA}"/>',
        None),
    # comemorando: meta batida, primeiro lançamento
    "comemorando": (_EYE_HAPPY,
        f'<rect x="120" y="120" width="16" height="30" rx="5" transform="rotate(-25 128 135)" fill="{LIMA}"/>'
        f'<rect x="400" y="110" width="16" height="30" rx="5" transform="rotate(30 408 125)" fill="{LIMA}"/>'
        f'<circle cx="170" cy="190" r="9" fill="{BRANCO}"/><circle cx="430" cy="200" r="8" fill="{BRANCO}"/>'
        f'<rect x="352" y="72" width="14" height="26" rx="5" transform="rotate(-40 359 85)" fill="{BRANCO}"/>'
        f'<rect x="150" y="70" width="14" height="26" rx="5" transform="rotate(20 157 83)" fill="{BRANCO}"/>',
        112),
    # dormindo: estados vazios (o "zz" da marca saindo do sono)
    "dormindo": (_EYE_CLOSED,
        _zletter(372, 176, 26, LIMA) + _zletter(410, 120, 36, LIMA, 8),
        None),
    # segurando o celular: WhatsApp
    "celular": (f'<circle cx="312" cy="258" r="9" fill="{TINTA}"/>',
        f'<rect x="352" y="196" width="78" height="134" rx="14" fill="{TINTA}"/>'
        f'<rect x="361" y="210" width="60" height="100" rx="6" fill="{BRANCO}"/>'
        f'<rect x="368" y="220" width="40" height="16" rx="8" fill="{LIMA}"/>'
        f'<rect x="374" y="244" width="40" height="16" rx="8" fill="{MAR}"/>'
        f'<rect x="368" y="268" width="30" height="16" rx="8" fill="{LIMA}"/>'
        f'<rect x="334" y="290" width="40" height="30" rx="14" fill="{BRANCO}"/>',
        None),
    # preocupado-gentil: orçamento estourado
    "preocupado": (f'<circle cx="318" cy="264" r="10" fill="{TINTA}"/>'
        f'<path d="M300,240 l30,-6" fill="none" stroke="{TINTA}" stroke-width="7" stroke-linecap="round"/>',
        f'<path d="M372,176 q-14,22 0,30 q14,-8 0,-30 z" fill="#7CB8FF"/>',
        None),
}


def mascot_png(path, size=512, pose=None):
    """Corpo com sombra suave (como antes) e a moeda caindo no cofre. pose: uma de MASCOT_POSES."""
    eye, front, coin_y = MASCOT_POSES[pose] if pose else (None, "", 158)
    shadow = render(svg(512, 512, mascot_body(shadow=True)), size)
    shadow = shadow.filter(ImageFilter.GaussianBlur(size / 64))
    shadow.putalpha(shadow.getchannel("A").point(lambda a: int(a * 0.45)))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(shadow, (0, round(size * 0.012)))
    coin = placed(symbol_solid(LIMA, TINTA), 512, 76, cx=256, cy=coin_y) if coin_y else ""
    out.alpha_composite(render(svg(512, 512, mascot_body(eye=eye) + coin + front), size))
    out.save(path)


# ---------- Exportação ----------
def render(svg_text, w, h=None):
    from io import BytesIO
    png = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=w, output_height=h or w)
    return Image.open(BytesIO(png)).convert("RGBA")


def save(svg_text, path, w, h=None, rgb=False):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    im = render(svg_text, w, h)
    (im.convert("RGB") if rgb else im).save(path)


def main():
    # Fontes vetoriais
    (BRAND / "svg/simbolo.svg").write_text(svg(100, 100, symbol_solid(LIMA, TINTA)))
    (BRAND / "svg/simbolo-contorno.svg").write_text(svg(100, 100, symbol_outline(TINTA)))
    (BRAND / "svg/simbolo-silhueta.svg").write_text(svg(100, 100, symbol_cutout("#000")))
    (BRAND / "svg/icone-app.svg").write_text(svg(100, 100, placed(symbol_solid(LIMA, TINTA), 100, 64), TINTA, 22))
    (BRAND / "svg/logo-claro.svg").write_text(logo_horizontal(TINTA, MAR, MAR, BRANCO))
    (BRAND / "svg/logo-escuro.svg").write_text(logo_horizontal(BRANCO, LIMA, LIMA, TINTA))
    (BRAND / "svg/mascote.svg").write_text(svg(512, 512, mascot_body() + placed(symbol_solid(LIMA, TINTA), 512, 76, cx=256, cy=158)))

    # Prévias
    save((BRAND / "svg/logo-claro.svg").read_text(), BRAND / "png/logo-claro.png", 1200, 162)
    save((BRAND / "svg/logo-escuro.svg").read_text(), BRAND / "png/logo-escuro.png", 1200, 162)
    save((BRAND / "svg/icone-app.svg").read_text(), BRAND / "png/icone-app.png", 512)

    # Android: ícone antigo (até 7.1), camadas do adaptativo (8+), monocromático (13+) e notificação
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for d, k in dens.items():
        save(svg(48, 48, placed(symbol_solid(LIMA, TINTA), 48, 31), TINTA, 10.5), RES / f"mipmap-{d}/ic_launcher.png", round(48 * k))
        # 108dp com zona segura de 66dp: a moeda ocupa 60dp
        save(svg(108, 108, placed(symbol_solid(LIMA, TINTA), 108, 60)), RES / f"mipmap-{d}/ic_launcher_foreground.png", round(108 * k))
        cutout_png(RES / f"mipmap-{d}/ic_launcher_monochrome.png", 108, 60, round(108 * k))
        cutout_png(RES / f"drawable-{d}/ic_notification.png", 24, 21, round(24 * k))

    # iOS: quadrado sem transparência (o sistema arredonda)
    appicon = MOBILE / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for f in appicon.glob("Icon-App-*.png"):
        n = Image.open(f).size[0]
        save(svg(100, 100, placed(symbol_solid(LIMA, TINTA), 100, 62), TINTA), f, n, rgb=True)

    # Web: ícone arredondado, "maskable" com a moeda dentro da zona segura de 80%, e favicon
    web = MOBILE / "web"
    icon = svg(100, 100, placed(symbol_solid(LIMA, TINTA), 100, 64), TINTA, 22)
    maskable = svg(100, 100, placed(symbol_solid(LIMA, TINTA), 100, 52), TINTA)
    for n in (192, 512):
        save(icon, web / f"icons/Icon-{n}.png", n)
        save(maskable, web / f"icons/Icon-maskable-{n}.png", n)
    save(icon, web / "favicon.png", 32)

    # Ícones de status (RN-49): o app troca o ícone conforme o mês. Atenção = moeda âmbar com os dois
    # z no mesmo nível; no vermelho = moeda coral com o segundo z descendo o degrau.
    import json
    for name, coin, rise in (("atencao", AMBAR, 0), ("alerta", CORAL, -Z_RISE)):
        (BRAND / f"svg/icone-app-{name}.svg").write_text(svg(100, 100, placed(symbol_solid(coin, TINTA, rise), 100, 64), TINTA, 22))
        save((BRAND / f"svg/icone-app-{name}.svg").read_text(), BRAND / f"png/icone-app-{name}.png", 512)
        for d, k in dens.items():
            save(svg(48, 48, placed(symbol_solid(coin, TINTA, rise), 48, 31), TINTA, 10.5), RES / f"mipmap-{d}/ic_launcher_{name}.png", round(48 * k))
            save(svg(108, 108, placed(symbol_solid(coin, TINTA, rise), 108, 60)), RES / f"mipmap-{d}/ic_launcher_{name}_foreground.png", round(108 * k))
            cutout_png(RES / f"mipmap-{d}/ic_launcher_{name}_monochrome.png", 108, 60, round(108 * k), rise)
        (RES / f"mipmap-anydpi-v26/ic_launcher_{name}.xml").write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_{name}_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_{name}_monochrome" />
</adaptive-icon>
""")
        alt = MOBILE / f"ios/Runner/Assets.xcassets/AppIcon-{name.capitalize()}.appiconset"
        alt.mkdir(parents=True, exist_ok=True)
        contents = json.loads((appicon / "Contents.json").read_text())
        (alt / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
        for f in appicon.glob("Icon-App-*.png"):
            n = Image.open(f).size[0]
            save(svg(100, 100, placed(symbol_solid(coin, TINTA, rise), 100, 62), TINTA), alt / f.name, n, rgb=True)

    # Mascote do app (mesmo arquivo e enquadramento de antes)
    mascot_png(MOBILE / "assets/mascot.png")
    for pose, (eye, front, coin_y) in MASCOT_POSES.items():
        mascot_png(MOBILE / f"assets/mascot_{pose}.png", pose=pose)
        coin = placed(symbol_solid(LIMA, TINTA), 512, 76, cx=256, cy=coin_y) if coin_y else ""
        (BRAND / f"svg/mascote-{pose}.svg").write_text(svg(512, 512, mascot_body(eye=eye) + coin + front))
    print("ok")


if __name__ == "__main__":
    main()
