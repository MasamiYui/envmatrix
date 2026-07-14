import urllib.parse, urllib.request, pathlib

prompt = (
    "macOS app icon squircle shape, flat design, 3x3 grid of rounded color "
    "tiles representing programming language runtimes, center tile glowing "
    "with a soft highlight like an active selection, balanced primary colors "
    "node-green python-blue swift-orange rust-red, subtle inner shadow, clean "
    "white background inside the squircle, crisp edges, Apple Human Interface "
    "Guidelines, high resolution, centered, no text"
)
url = (
    "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt="
    + urllib.parse.quote(prompt)
    + "&image_size=square"
)
out = pathlib.Path("tools/icon-picker/generated/AppIcon-1024.png")
out.parent.mkdir(parents=True, exist_ok=True)
print("URL:", url)
req = urllib.request.Request(url, headers={"User-Agent": "EnvMatrix-IconGen/1.0"})
with urllib.request.urlopen(req, timeout=60) as r:
    out.write_bytes(r.read())
print("Saved:", out, out.stat().st_size, "bytes")
