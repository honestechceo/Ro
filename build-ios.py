"""Build the iPhone app's files (www/) from index.html, the same page GitHub Pages serves.

The iPhone app is the website plus: Capacitor's runtime (camera text reader, Files folder,
share sheet), and the libraries it loads kept inside the app so it works with no signal.
Run:  python3 build-ios.py      then the workflow downloads the vendor files and runs `npx cap sync ios`.
"""
import re, shutil
from pathlib import Path

ROOT = Path(__file__).parent
VENDOR = {
    "https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js": "vendor/jspdf.umd.min.js",
    "https://cdn.jsdelivr.net/npm/@zxing/library@0.21.3/umd/index.min.js": "vendor/zxing.min.js",
}
www = ROOT / "www"
if www.exists():
    shutil.rmtree(www)
(www / "vendor").mkdir(parents=True)
html = (ROOT / "index.html").read_text(encoding="utf-8")
for url, local in VENDOR.items():
    assert url in html, f"{url} not found in index.html"
    html = html.replace(url, local)
html = html.replace("<head>", '<head><script src="capacitor.js"></script>', 1)
html = re.sub(r'<link rel="manifest"[^>]*>', "", html)
html = re.sub(r'<link rel="apple-touch-startup-image"[^>]*>', "", html)
(www / "index.html").write_text(html, encoding="utf-8")
for f in ["privacy.html", "icon-192.png", "icon-512.png", "apple-touch-icon.png"]:
    shutil.copy(ROOT / f, www / f)
(www / "vendor" / "SOURCES.txt").write_text("\n".join(f"{u} -> {l}" for u, l in VENDOR.items()) + "\n", encoding="utf-8")
print("www/ built")
