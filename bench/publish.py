"""Render bench/results/summary.json into the README, the site, docs/BENCHMARKS.md and docs/img/comparison.png.

Usage: uv run --with matplotlib bench/publish.py

summary.json is the only place the published numbers live. Every value in it names the raw output file in bench/results/
it comes from. Edit summary.json after a new measurement, run this script, and commit everything it touched.
"""

import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = json.loads((ROOT / "bench/results/summary.json").read_text(encoding="utf-8"))

BG = "#0d1117"
PANEL = "#121820"
GRID = "#232b36"
INK = "#e6edf3"
INK2 = "#8b98a8"
OTHERS = ["#556378", "#475569", "#64748b", "#3d4a5c"]
KWICK_TOP = "#22e5dc"
KWICK_BOTTOM = "#8a48d6"


def replace_block(path, name, body):
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    pat = re.compile(r"(<!-- bench:%s -->\n)(?:.*?\n)??([ \t]*<!-- /bench:%s -->)" % (name, name), re.S)
    if not pat.search(text):
        sys.exit(f"{path}: missing <!-- bench:{name} --> block")
    text = pat.sub(lambda m: m.group(1) + body + "\n" + m.group(2), text)
    p.write_text(text, encoding="utf-8", newline="\n")


def html_inline(s):
    s = html.escape(s, quote=False)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", s)


def rows(where):
    return [r for r in DATA["summary"] if where in r.get("show", ["readme", "site", "benchmarks"])]


def cells(r, bold, plain=lambda s: s):
    a, k = plain(r["alpine"]), plain(r["kwickos"])
    if r.get("winner") == "alpine":
        a = bold(a)
    elif r.get("winner") == "kwickos":
        k = bold(k)
    return a, k


def md_bold(s):
    return f"**{s}**"


def html_bold(s):
    return f"<strong>{s}</strong>"


def readme_table():
    v = DATA["versions"]
    out = [f"| | Alpine {v['alpine']} | KwickOS {v['kwickos']} |", "|---|---:|---:|"]
    for r in rows("readme"):
        a, k = cells(r, md_bold)
        out.append(f"| {r['what']} | {a} | {k} |")
    out.append("")
    out.append(f"The better result of each row is in bold. Measured {DATA['measured']}.")
    return "\n".join(out)


def benchmarks_table():
    v = DATA["versions"]
    out = [f"| | Alpine {v['alpine']} | KwickOS {v['kwickos']} | conditions | raw output |", "|---|---:|---:|---|---|"]
    for r in DATA["summary"]:
        a, k = cells(r, md_bold)
        src = ", ".join(f"[{s}](../bench/results/{s})" for s in r["source"])
        cond = r["conditions"].replace("|", "\\|")
        out.append(f"| {r['what']} | {a} | {k} | {cond} | {src} |")
    return "\n".join(out)


def site_table(indent):
    out = []
    for r in rows("site"):
        a, k = cells(r, html_bold, html_inline)
        what = html_inline(r["what"][0].upper() + r["what"][1:])
        out.append(f"{indent}<tr><th scope=\"row\">{what}</th><td>{a}</td><td>{k}</td></tr>")
    return "\n".join(out)


def site_stats(indent):
    out = []
    for s in DATA["headline"]:
        unit = f"<small>&nbsp;{s['unit']}</small>" if s.get("unit") else ""
        out.append(f"{indent}<li class=\"reveal\"><strong>{s['value']}{unit}</strong><span>{html_inline(s['label'])}</span></li>")
    return "\n".join(out)


def chart():
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import LinearSegmentedColormap
    import numpy as np

    panels = DATA["chart"]["panels"]
    cols = 3
    nrows = (len(panels) + cols - 1) // cols
    fig = plt.figure(figsize=(30, 8.6 * nrows + 2.2), dpi=100, facecolor=BG)
    plt.rcParams.update({"font.family": "DejaVu Sans"})
    fig.text(0.04, 1 - 0.55 / (8.6 * nrows + 2.2), DATA["chart"]["title"], color=INK, fontsize=50, weight="bold", va="top")
    fig.text(0.04, 1 - 1.45 / (8.6 * nrows + 2.2), DATA["chart"]["subtitle"], color=INK2, fontsize=24, va="top")
    grad = LinearSegmentedColormap.from_list("kwick", [KWICK_BOTTOM, KWICK_TOP])
    top = 1 - 3.7 / (8.6 * nrows + 2.2)
    gs = fig.add_gridspec(nrows, cols, left=0.05, right=0.975, top=top, bottom=0.07, hspace=0.62, wspace=0.18)
    for i, p in enumerate(panels):
        ax = fig.add_subplot(gs[i // cols, i % cols])
        ax.set_facecolor(PANEL)
        names = [b[0] for b in p["bars"]]
        vals = [b[1] for b in p["bars"]]
        ymax = max(vals) * 1.22
        ax.set_ylim(0, ymax)
        ax.set_xlim(-0.6, len(vals) - 0.4)
        other = 0
        for x, b in enumerate(p["bars"]):
            v = b[1]
            if b[0].startswith("KwickOS"):
                ax.imshow(
                    np.linspace(1, 0, 256).reshape(-1, 1),
                    extent=(x - 0.31, x + 0.31, 0, v),
                    cmap=grad,
                    aspect="auto",
                    zorder=3,
                    vmin=0,
                    vmax=1,
                )
                color, weight = KWICK_TOP, "bold"
            else:
                ax.bar(x, v, width=0.62, color=OTHERS[other % len(OTHERS)], zorder=3)
                other += 1
                color, weight = INK, "normal"
            label = b[2] if len(b) > 2 else f"{v:g}"
            ax.text(x, v + ymax * 0.025, label, ha="center", va="bottom", color=color, fontsize=21, weight=weight, zorder=4)
        ax.set_xticks(range(len(vals)))
        ax.set_xticklabels(names, color=INK2, fontsize=19)
        ax.tick_params(axis="y", colors=INK2, labelsize=17, length=0)
        ax.tick_params(axis="x", length=0, pad=10)
        ax.grid(axis="y", color=GRID, linewidth=1.2, zorder=0)
        for s in ax.spines.values():
            s.set_visible(False)
        ax.axhline(0, color="#2d3643", linewidth=1.5, zorder=4)
        ax.set_title(p["title"], loc="left", color=INK, fontsize=26, weight="bold", pad=58)
        ax.text(0, 1.04, p["unit"], transform=ax.transAxes, color=INK2, fontsize=19, va="bottom")
    out = ROOT / "docs/img/comparison.png"
    fig.savefig(out, facecolor=BG, dpi=100)
    print(f"wrote {out.relative_to(ROOT)}")


def main():
    replace_block("README.md", "summary", readme_table())
    replace_block("docs/BENCHMARKS.md", "summary", benchmarks_table())
    replace_block("site/index.html", "stats", site_stats("      "))
    replace_block("site/index.html", "table", site_table("          "))
    chart()


if __name__ == "__main__":
    main()
