#!/usr/bin/env python3
"""Generate tools/promo.html — the marketplace card — with the tab captures inlined.

The screenshots are embedded as data URIs so the page renders identically from
any working directory and needs nothing fetched at build time.
"""
import base64
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABS = ROOT / "assets" / "tabs"

# Every capture is 880 wide but its height follows its content, so crop them all
# to a common band from the top. That keeps the mastheads and tab rows aligned
# across the grid instead of letting the tall tabs tower over the short ones.
BAND = 680

PANELS = [
    ("schedule.png",  "SCHEDULE",  "circuit, countdown, local session times"),
    ("live.png",      "LIVE",      "running order and flags, mid-session"),
    ("grid.png",      "GRID",      "starting order, straight after qualifying"),
    ("drivers.png",   "STANDINGS", "points and gaps, by team color"),
]


def uri(name):
    src = TABS / name
    out = subprocess.run(
        ["magick", str(src), "-crop", f"880x{BAND}+0+0", "+repage", "png:-"],
        check=True, capture_output=True).stdout
    return "data:image/png;base64," + base64.b64encode(out).decode()


cards = "\n".join(
    f'''      <figure class="card">
        <div class="shot"><img src="{uri(f)}" alt="{label} tab"></div>
        <figcaption><b>{label}</b> {note}</figcaption>
      </figure>''' for f, label, note in PANELS)

HTML = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  body {{ width:1600px; height:1000px; background:#15161f; overflow:hidden;
         font-family:'JetBrainsMono Nerd Font','JetBrainsMono NF',monospace; position:relative; }}
  .watermark {{ position:absolute; left:-90px; bottom:-140px; opacity:0.045; }}
  .wrap {{ position:relative; display:flex; height:100%; padding:66px 60px; gap:52px; align-items:center; }}
  .left {{ width:566px; flex:none; }}
  .brand {{ display:flex; align-items:center; gap:13px; margin-bottom:30px; }}
  .brand .flag {{ color:#7aa2f7; font-size:24px; }}
  .brand .word {{ color:#565f89; font-size:15px; font-weight:700; letter-spacing:6px; }}
  h1 {{ color:#c0caf5; font-size:43px; line-height:1.16; font-weight:800; letter-spacing:-0.5px; }}
  h1 .acc {{ color:#7aa2f7; }}
  .sub {{ color:#7f88ad; font-size:17px; line-height:1.55; margin-top:19px; }}
  .feat {{ list-style:none; margin-top:32px; }}
  .feat li {{ color:#a9b1d6; font-size:15.5px; line-height:1.5; margin-bottom:13px;
              padding-left:22px; position:relative; }}
  .feat li::before {{ content:"\\25B8"; color:#7aa2f7; font-weight:700; position:absolute; left:0; }}
  .feat b {{ color:#c0caf5; }}
  .install {{ margin-top:34px; display:inline-block; background:#1a1b26; border:1px solid #333646;
             border-radius:9px; padding:13px 19px; color:#a9b1d6; font-size:14px; white-space:nowrap; }}
  .install .p {{ color:#565f89; }} .install .c {{ color:#9ece6a; }}
  .grid {{ flex:1; display:grid; grid-template-columns:1fr 1fr; gap:26px 24px; }}
  /* The captures are cut to a common band, so fade the cut edge rather than
     letting each card end on a half-drawn row. */
  .card .shot {{ border-radius:9px; border:1px solid #3d4259; overflow:hidden;
                box-shadow:0 18px 44px rgba(0,0,0,.5);
                -webkit-mask-image:linear-gradient(to bottom,#000 82%,transparent 100%);
                mask-image:linear-gradient(to bottom,#000 82%,transparent 100%); }}
  .card .shot img {{ display:block; width:100%; }}
  .card figcaption {{ margin-top:11px; color:#565f89; font-size:13px; letter-spacing:.3px; }}
  .card figcaption b {{ color:#7aa2f7; letter-spacing:2.2px; margin-right:9px; }}
</style></head><body>
  <svg class="watermark" width="620" height="760" viewBox="0 0 700 860">
    <polyline points="13,546 25,376 30,305 31,302 33,300 35,300 37,300 40,300 42,300 43,299 44,297 45,295 45,293 36,254 35,243 35,234 35,223 38,173 40,164 41,157 43,148 46,139 50,131 55,121 60,113 67,104 75,96 83,88 92,82 102,75 113,71 124,67 137,64 150,63 201,58 263,53 267,53 269,51 270,49 272,40 273,38 275,36 277,35 286,33 295,31 308,26 366,1 371,0 376,0 381,1 384,3 387,5 390,7 394,12 396,16 398,21 398,27 401,61 406,119 405,124 405,127 403,130 402,132 398,135 360,161 329,182 309,195 300,202 290,211 282,218 275,225 242,261 217,288 167,342 136,376 132,381 130,384 130,387 130,391 131,400 131,405 131,412 131,415 130,420 128,426 125,431 121,437 116,442 113,446 111,448 109,452 108,459 105,490 102,524 76,824 75,835 74,840 72,845 69,849 66,853 61,856 56,859 51,860 46,860 41,858 36,856 30,853 27,850 22,845 17,838 13,832 10,826 7,818 5,809 3,800 2,792 1,781 1,769 1,758 0,736 0,717 0,696 2,669 10,583 13,546" fill="none" stroke="#c0caf5" stroke-width="14"
      stroke-linecap="round" stroke-linejoin="round"/>
  </svg>
  <div class="wrap">
    <div class="left">
      <div class="brand"><span class="flag"></span><span class="word">FORMULA 1 &middot; FOR OMARCHY</span></div>
      <h1>The whole race weekend,<br><span class="acc">not just the countdown.</span></h1>
      <div class="sub">Six tabs of live Formula 1 in the Omarchy bar. No API key, no account, nothing to set up.</div>
      <ul class="feat">
        <li><b>Live timing</b> &mdash; running order and track flags while a session is on</li>
        <li><b>The starting grid</b> after qualifying, plus race results and both championships</li>
        <li><b>40 circuits as vector line-art</b>, recolored to your theme</li>
      </ul>
      <div class="install"><span class="p">$</span> omarchy plugin add <span class="c">github.com/Snackwrap/omarchy-f1</span></div>
    </div>
    <div class="grid">
{cards}
    </div>
  </div>
</body></html>"""

(ROOT / "tools" / "promo.html").write_text(HTML, encoding="utf-8")
print("tools/promo.html written")
