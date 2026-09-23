#!/usr/bin/env python3
import sys
import pathlib
import re
import json

args = list(map(pathlib.Path, sys.argv[1:]))
index_path, bridge_path, out_path, cf_dir, dy_dir = args[:5]
beam_dir = args[5] if len(args) > 5 else None
html = index_path.read_text(encoding='utf-8')
bridge = bridge_path.read_text(encoding='utf-8')
m = re.search(r'<script\s+src=["\']bridge\.js["\']\s*>\s*</script>', html, flags=re.I)
if not m:
    raise SystemExit('bridge.js script tag not found in preview index.html')
inline = '<script>\n/* inlined bridge.js — offline, no fetch */\n' + bridge + '\n</script>'
html = html[: m.start()] + inline + html[m.end():]


def collect(dirpath, patterns):
    if dirpath is None or not dirpath.is_dir():
        return []
    files = []
    for pat in patterns:
        files.extend(sorted(dirpath.glob(pat)))
    seen, out = set(), []
    for f in files:
        if f.name in seen:
            continue
        seen.add(f.name)
        out.append(f)
    return out


cf_files = collect(
    cf_dir,
    [
        '00-boot.cf',
        '01-desktop.cf',
        '02-workbench.cf',
        '03-termux.cf',
        '04-agent.cf',
        '05-screen-termux-agent.cf',
        'blocks.cf',
        'desktop.cf',
        'workbench.cf',
        'termux.cf',
        'agent.cf',
        'screen-termux-agent.cf',
        'workplace.cf',
    ],
)
prefer = {
    '00-boot.cf',
    '01-desktop.cf',
    '02-workbench.cf',
    '03-termux.cf',
    '04-agent.cf',
    '05-screen-termux-agent.cf',
    'blocks.cf',
}
cf_files = [f for f in cf_files if f.name in prefer] or cf_files
dy_files = collect(dy_dir, ['*.lid', '*.dylan'])
catalog = {'colorforth': {}, 'dylan': {}, 'beam': {}}
for f in cf_files:
    catalog['colorforth'][f.name] = f.read_text(encoding='utf-8')
for f in dy_files:
    catalog['dylan'][f.name] = f.read_text(encoding='utf-8')
if beam_dir and beam_dir.is_dir():
    for f in sorted(beam_dir.rglob('*')):
        if f.is_file() and (
            f.suffix in {'.ex', '.exs', '.md'} or f.name in {'mix.exs', '.formatter.exs'}
        ):
            rel = str(f.relative_to(beam_dir))
            try:
                catalog['beam'][rel] = f.read_text(encoding='utf-8')
            except Exception:
                pass
parts = [
    '\n<!-- offline embedded raw sources (no fetch) -->\n',
    '<script id="raw-sources" type="application/json">\n',
    json.dumps(catalog, ensure_ascii=False, indent=2),
    '\n</script>\n',
    '<script>\nwindow.EVOKE_RAW = JSON.parse(document.getElementById("raw-sources").textContent);\n</script>\n',
]
if '</body>' in html:
    html = html.replace('</body>', ''.join(parts) + '</body>', 1)
else:
    html += ''.join(parts)
html = html.replace(
    '<title>Visual Workplace · ColorForth + Dylan</title>',
    '<title>Visual Workplace · ColorForth + Dylan + BEAM (offline evoke)</title>',
    1,
)
out_path.write_text(html, encoding='utf-8')
print(f'wrote standalone: {out_path} ({out_path.stat().st_size} bytes)')
if re.search(r'<script[^>]+src=["\']https?://', html, re.I):
    sys.exit('standalone still has external script src')
if 'src="bridge.js"' in html or "src='bridge.js'" in html:
    sys.exit('bridge.js not inlined')
