from icondesign import DD, DV, OBJECTS, XL, lg, mix, shadow_stack
import placeicons
import settingsicons

BOX = {
    "folder": (8, 22, 92, 80), "folderfill": (8, 22, 92, 80), "terminal": (8, 16, 92, 84), "gear": (9, 9, 91, 91),
    "pencilpage": (14, 8, 92, 92), "bag": (16, 16, 84, 90), "image": (10, 16, 90, 84), "book": (14, 10, 86, 88),
    "archive": (8, 18, 92, 88), "screenshot": (8, 18, 92, 82), "camera": (8, 18, 92, 82), "calc": (18, 8, 82, 92),
    "pulse": (8, 14, 92, 83), "display": (8, 14, 92, 83), "mail": (8, 22, 92, 80), "calendar": (13, 12, 87, 88),
    "music": (20, 14, 80, 82), "video": (8, 20, 92, 80), "search": (14, 14, 86, 86), "globe": (12, 12, 88, 88),
    "docs": (20, 8, 80, 90), "downloads": (10, 12, 90, 86), "disc": (8, 8, 92, 92), "clapper": (8, 14, 92, 86),
    "house": (6, 12, 94, 86), "template": (14, 12, 84, 90), "people": (8, 18, 92, 88),
}

BOX.update(settingsicons.BOX)
FILL = 112.0


def fit(box):
    x0, y0, x1, y1 = box
    sc = FILL / max(x1 - x0, y1 - y0)
    tx = 64 - (x0 + x1) / 2 * sc
    ty = 64 - (y0 + y1) / 2 * sc - 1
    return sc, tx, ty


def free_icon(glyph, colors, pal, markup, d):
    c1, c2 = colors[pal]
    offs = ((7, 0.06, 0), (5, 0.08, 0), (3, 0.12, 0), (1.5, 0.16, 0))
    if glyph in OBJECTS:
        defs, body, sil = OBJECTS[glyph]("color", mix(c1, "#ffffff", 0.08), c2, d)
        sh = shadow_stack(sil, offs)
        sc, tx, ty = fit(BOX.get(glyph, (8, 8, 92, 92)))
        inner = f'<g transform="translate({tx:.2f} {ty:.2f}) scale({sc:.3f})">{sh}{body}</g>'
    else:
        defs, body, sil = settingsicons.glyph_disc(markup, glyph, mix(c1, "#ffffff", 0.08), c2)
        sh = shadow_stack(sil, offs)
        sc, tx, ty = fit((8, 8, 92, 92))
        inner = f'<g transform="translate({tx:.2f} {ty:.2f}) scale({sc:.3f})">{sh}{body}</g>'
    return f'<svg {XL} width="128" height="128" viewBox="0 0 128 128"><defs>{defs}</defs>{inner}</svg>\n'
