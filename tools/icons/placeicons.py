from icondesign import DD, DV, OBJECTS, XL, lg, mix, rg, shadow_stack


def o_docs(tone, c1, c2, d):
    defs = lg("o1", [(0, "#ffffff"), (1, "#dfe7f5")]) + lg("o2", [(0, mix(c1, "#ffffff", 0.15)), (1, c2)], d) + lg("o3", [(0, "#cfd9ec"), (1, "#aebbd6")])
    lines = "".join(f'<path d="M30 {y}h{w}" stroke="#b9c4da" stroke-width="3.6" stroke-linecap="round"/>' for y, w in ((50, 38), (61, 30), (72, 38)))
    body = (
        '<g transform="rotate(9 50 52)"><rect x="24" y="8" width="52" height="72" rx="6" fill="url(#o3)"/></g>'
        '<g transform="rotate(-5 50 52)"><rect x="22" y="10" width="54" height="74" rx="6" fill="#eef2fa"/></g>'
        '<rect x="20" y="14" width="58" height="76" rx="6" fill="url(#o1)"/>'
        '<path d="M20 20a6 6 0 0 1 6-6h46a6 6 0 0 1 6 6v14H20z" fill="url(#o2)"/>'
        + lines
        + '<rect x="20.5" y="14.5" width="57" height="75" rx="5.5" fill="none" stroke="#fff" stroke-opacity="0.9"/>'
    )
    return defs, body, '<rect x="18" y="12" width="62" height="78" rx="6" fill="S"/>'


def o_downloads(tone, c1, c2, d):
    defs = (
        lg("o1", [(0, mix(c1, "#ffffff", 0.25)), (1, c2)], d)
        + lg("o2", [(0, "#c4cee3"), (1, "#8d9bb8")])
        + lg("o3", [(0, "#ffffff"), (1, "#d6dff0")])
    )
    body = (
        '<rect x="10" y="56" width="80" height="30" rx="9" fill="url(#o2)"/>'
        '<path d="M41 12h18v28h15L50 70 26 40h15z" fill="url(#o1)" stroke="#fff" stroke-opacity="0.5" stroke-linejoin="round"/>'
        '<path d="M10 66h80v10a10 10 0 0 1-10 10H20a10 10 0 0 1-10-10z" fill="url(#o3)"/>'
        '<path d="M16 67h68" stroke="#fff" stroke-opacity="0.9" stroke-width="1.2" stroke-linecap="round"/>'
    )
    return defs, body, '<path d="M41 12h18v28h15L62 56h28v22a10 10 0 0 1-10 10H20a10 10 0 0 1-10-10V56h28L26 40h15z" fill="S"/>'


def o_disc(tone, c1, c2, d):
    defs = (
        rg("o2", [(0, "#4a5068"), (0.6, "#1e2130"), (1, "#0b0c14")], 0.35, 0.3, 0.85)
        + lg("o1", [(0, mix(c1, "#ffffff", 0.2)), (1, c2)], d)
        + lg("o4", [(0, "#fff", 0.35), (0.5, "#fff", 0)], DD)
    )
    ring = "".join(f'<circle cx="50" cy="50" r="{r}" fill="none" stroke="#fff" stroke-opacity="0.07"/>' for r in (24, 30, 36))
    body = (
        '<circle cx="50" cy="50" r="42" fill="url(#o2)"/>'
        + ring
        + '<path d="M50 50L82 20A42 42 0 0 1 90 50z" fill="#fff" fill-opacity="0.06"/>'
        '<circle cx="50" cy="50" r="42" fill="url(#o4)"/>'
        '<g transform="translate(26 16) scale(0.55)"><path d="M40 70V26l38-9v44" fill="none" stroke="url(#o1)" stroke-width="8" stroke-linejoin="round" stroke-linecap="round"/>'
        '<ellipse cx="32" cy="72" rx="12" ry="9.5" fill="url(#o1)" transform="rotate(-18 32 72)"/><ellipse cx="70" cy="64" rx="12" ry="9.5" fill="url(#o1)" transform="rotate(-18 70 64)"/></g>'
    )
    return defs, body, '<circle cx="50" cy="50" r="42" fill="S"/>'


def o_clapper(tone, c1, c2, d):
    defs = lg("o1", [(0, mix(c1, "#ffffff", 0.2)), (1, c2)], d) + lg("o2", [(0, "#4a4f66"), (1, "#1c1f2c")])
    stripes = "".join(f'<path d="M{x} 20h10l-8 20h-10z" fill="#fff" fill-opacity="0.92"/>' for x in (22, 46, 70))
    body = (
        '<rect x="10" y="40" width="80" height="46" rx="8" fill="url(#o1)"/>'
        '<rect x="10" y="40" width="80" height="12" fill="#000" fill-opacity="0.18"/>'
        '<g transform="rotate(-9 12 40)"><rect x="10" y="20" width="80" height="20" rx="4" fill="url(#o2)"/>' + stripes + '</g>'
        '<path d="M43 56v22l20-11z" fill="#fff" stroke="#fff" stroke-width="4" stroke-linejoin="round"/>'
        '<path d="M11 41h78" stroke="#fff" stroke-opacity="0.5"/>'
    )
    return defs, body, '<rect x="8" y="14" width="84" height="72" rx="8" fill="S"/>'


def o_house(tone, c1, c2, d):
    defs = lg("o1", [(0, "#ffffff"), (1, "#dce5f4")]) + lg("o2", [(0, mix(c1, "#ffffff", 0.2)), (1, c2)], d) + lg("o3", [(0, mix(c2, "#ffffff", 0.2)), (1, mix(c2, "#000000", 0.2))])
    body = (
        '<rect x="22" y="44" width="56" height="42" rx="4" fill="url(#o1)"/>'
        '<rect x="62" y="22" width="9" height="22" rx="2" fill="url(#o3)"/>'
        '<path d="M6 52L50 12l44 40-7 6L50 24 13 58z" fill="url(#o2)"/>'
        '<rect x="43" y="60" width="16" height="26" rx="3" fill="url(#o3)"/>'
        '<rect x="28" y="54" width="10" height="10" rx="2" fill="#9fc6f5"/>'
        '<rect x="22.5" y="44.5" width="55" height="41" rx="3.5" fill="none" stroke="#fff" stroke-opacity="0.8"/>'
    )
    return defs, body, '<path d="M6 52L50 12l44 40-7 6-9-8v36H22V50l-9 8z" fill="S"/>'


def o_template(tone, c1, c2, d):
    defs = lg("o1", [(0, "#ffffff"), (1, "#e1e8f5")]) + lg("o2", [(0, "#ffe27a"), (1, "#f2a81d")], d)
    ticks = "".join(f'<path d="M62 {y}h{w}" stroke="#7a5a10" stroke-opacity="0.55" stroke-width="1.6"/>' for y, w in ((30, 10), (38, 6), (46, 10), (54, 6), (62, 10), (70, 6), (78, 10)))
    body = (
        '<rect x="14" y="12" width="58" height="76" rx="6" fill="url(#o1)"/>'
        '<path d="M24 32h30M24 44h24M24 56h30M24 68h18" stroke="#b9c4da" stroke-width="3.6" stroke-linecap="round"/>'
        '<g transform="rotate(8 70 50)"><rect x="58" y="18" width="24" height="70" rx="4" fill="url(#o2)"/>' + ticks + '<rect x="58.5" y="18.5" width="23" height="69" rx="3.5" fill="none" stroke="#fff" stroke-opacity="0.6"/></g>'
    )
    return defs, body, '<rect x="14" y="12" width="70" height="78" rx="6" fill="S"/>'


def o_people(tone, c1, c2, d):
    defs = lg("o1", [(0, mix(c1, "#ffffff", 0.25)), (1, c2)], d) + lg("o2", [(0, mix(c1, "#ffffff", 0.55)), (1, mix(c2, "#ffffff", 0.3))], d)
    body = (
        '<circle cx="68" cy="30" r="13" fill="url(#o2)"/><path d="M44 80a24 24 0 0 1 48 0z" fill="url(#o2)"/>'
        '<circle cx="38" cy="36" r="16" fill="url(#o1)"/><path d="M8 88a30 30 0 0 1 60 0z" fill="url(#o1)"/>'
        '<path d="M26 28a16 16 0 0 1 22-2" fill="none" stroke="#fff" stroke-opacity="0.6" stroke-width="2" stroke-linecap="round"/>'
    )
    return defs, body, '<circle cx="38" cy="36" r="16" fill="S"/><path d="M8 88a30 30 0 0 1 60 0z" fill="S"/><circle cx="68" cy="30" r="13" fill="S"/><path d="M44 80a24 24 0 0 1 48 0z" fill="S"/>'


OBJECTS.update({"docs": o_docs, "downloads": o_downloads, "disc": o_disc, "clapper": o_clapper, "house": o_house, "template": o_template, "people": o_people})

PLACE_OBJ = {
    "folder-documents": ("docs", "blue"),
    "folder-download": ("downloads", "teal"),
    "folder-downloads": ("downloads", "teal"),
    "folder-pictures": ("image", "sky"),
    "folder-music": ("disc", "orange"),
    "folder-video": ("clapper", "violet"),
    "folder-videos": ("clapper", "violet"),
    "user-desktop": ("display", "blue"),
    "folder-desktop": ("display", "blue"),
    "user-home": ("house", "orange"),
    "folder-home": ("house", "orange"),
    "folder-templates": ("template", "gray"),
    "folder-publicshare": ("people", "sky"),
    "folder-public": ("people", "sky"),
    "folder-network": ("globe", "sky"),
    "folder-smb": ("globe", "sky"),
    "folder-remote-network": ("globe", "sky"),
    "network-workgroup": ("globe", "sky"),
    "network-server": ("globe", "sky"),
}


def place_svg(key, c1, c2, d):
    defs, body, sil = OBJECTS[key]("color", c1, c2, d)
    sh = shadow_stack(sil, ((7, 0.06, 0), (5, 0.08, 0), (3, 0.12, 0), (1.5, 0.16, 0)))
    return f'<svg {XL} width="128" height="128" viewBox="0 0 128 128"><defs>{defs}</defs><g transform="translate(7 5) scale(1.14)">{sh}{body}</g></svg>\n'
