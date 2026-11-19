#!/usr/bin/env python3
import re, sys
from pathlib import Path
from picosvg.svg import SVG

STYLE = re.compile(r'<style id="current-color-scheme"[^>]*>\.([\w-]+)\{color:([^}]+)\}</style>')


def convert(path):
    src = path.read_text(encoding="utf-8")
    if 'stroke="currentColor"' not in src:
        return False
    m = STYLE.search(src)
    if not m:
        return False
    cls, default = m.group(1), m.group(2)
    plain = STYLE.sub("", src).replace(f' class="{cls}"', "").replace("currentColor", "#000000")
    pico = SVG.fromstring(plain).topicosvg()
    parts = []
    for shape in pico.shapes():
        d = shape.d
        if not d:
            continue
        op = shape.opacity * shape.fill_opacity
        attr = f' fill-opacity="{op:.3g}"' if op < 0.999 else ""
        parts.append(f'<path d="{d}"{attr}/>')
    if not parts:
        return False
    vb = pico.view_box()
    out = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{vb.w:g}" height="{vb.h:g}" viewBox="{vb.x:g} {vb.y:g} {vb.w:g} {vb.h:g}">'
           f'<style id="current-color-scheme" type="text/css">.{cls}{{color:{default}}}</style>'
           f'<g class="{cls}" fill="currentColor">{"".join(parts)}</g></svg>\n')
    path.write_text(out, encoding="utf-8", newline="\n")
    return True


def main():
    done = failed = 0
    for root in sys.argv[1:]:
        for p in sorted(Path(root).rglob("*-symbolic.svg")):
            if p.is_symlink():
                continue
            try:
                done += convert(p)
            except Exception as e:
                failed += 1
                print(f"skip {p}: {e}", file=sys.stderr)
    print(f"filled {done} symbolic icons, {failed} skipped")


if __name__ == "__main__":
    main()
