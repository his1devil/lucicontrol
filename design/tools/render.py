"""Renders the design canvas (../LuciControl.dc.html) to PNGs in ../reference.

    python3 design/tools/render.py

Needs node and Google Chrome. The canvas runtime is not used: vals.js runs the file's own
logic class for each page state, expand.py fills the templates, headless Chrome takes the
picture.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DESIGN = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from expand import expand  # noqa: E402

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
src = open(os.path.join(DESIGN, 'LuciControl.dc.html'), encoding='utf-8').read()
style = re.search(r'<style>(.*?)</style>', src, re.S).group(1)


def artboard(option):
    i = src.find('<div class="dv-opt" id="%s"' % option)
    j = src.find('<div class="dv-opt"', i + 10)
    k = src.find('</section>', i)
    end = j if 0 < j < k else k
    seg = src[i:end]
    art = seg[seg.find('</div>', seg.find('dv-olabel')) + 6:].strip()
    for _ in range(2 if end == k else 1):  # the closing tags of dv-opt (and dv-opts)
        art = art[:art.rfind('</div>')].strip()
    return art


def shot(html, png, w, h, scale=2):
    with tempfile.NamedTemporaryFile('w', suffix='.html', delete=False, encoding='utf-8') as f:
        f.write(html)
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                    '--force-device-scale-factor=%s' % scale, '--window-size=%d,%d' % (w, h),
                    '--virtual-time-budget=6000', '--screenshot=' + png, 'file://' + f.name],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    os.unlink(f.name)
    print(os.path.relpath(png, DESIGN), os.path.getsize(png) if os.path.exists(png) else 'MISSING')


def page(body, pad=24, flex=False):
    layout = 'display:flex;gap:20px;padding:16px;' if flex else 'display:inline-block;padding:%dpx;' % pad
    return ('<!DOCTYPE html><html><head><meta charset="utf-8"><base href="file://%s/"><style>%s body{%s}</style></head><body>%s</body></html>'
            % (DESIGN, style, layout, body))


def main():
    out = os.path.join(DESIGN, 'reference')
    os.makedirs(out, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        names = subprocess.run(['node', os.path.join(HERE, 'vals.js'), tmp], check=True, capture_output=True, text=True).stdout.split()
        vals = {n: json.load(open(os.path.join(tmp, n + '.json'))) for n in names}
    for option, theme in (('9a', 'light'), ('9b', 'dark')):
        art = artboard(option)
        for n in names:
            shot(page(expand(art, vals[n])), os.path.join(out, '%s-%s.png' % (theme, n)), 508, 868)
        for k in range(0, len(names), 3):
            group = names[k:k + 3]
            body = ''.join('<div><div style="font:600 12px -apple-system;color:#555;margin:0 0 6px 2px">%s</div>%s</div>' % (n, expand(art, vals[n])) for n in group)
            shot(page(body, flex=True), os.path.join(out, 'sheet-%s-%d.png' % (theme, k // 3 + 1)), 32 + len(group) * 480 - 20, 880, 1.5)
    shot(page(expand(artboard('14b'), {})), os.path.join(out, 'icon.png'), 448, 560)


if __name__ == '__main__':
    main()
