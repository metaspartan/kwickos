import sys
cls, shader, defdur, extra = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else ""
open(sys.argv[5] if len(sys.argv) > 5 else "main.js", "w", newline="\n").write(open(__file__.replace("mkfx.py", "oc.js.tpl")).read().replace("@CLS@", cls).replace("@SHADER@", shader).replace("@DUR@", defdur).replace("@EXTRA@", extra).replace("@SEEDED@", "false" if "uStyle" in extra else "true"))
