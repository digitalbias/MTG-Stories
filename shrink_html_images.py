#!/usr/bin/env python3
"""Downscale/recompress base64-embedded images in a Typst HTML export
before handing it to pandoc for EPUB packaging. Typst embeds source
images at full resolution; e-readers don't need more than ~1600px on
the long edge, and JPEG at quality 85 is plenty for story art."""
import sys
import re
import base64
import io
from PIL import Image

MAX_DIM = 1600
JPEG_QUALITY = 85

IMG_RE = re.compile(rb'data:image/(png|jpeg|jpg);base64,([A-Za-z0-9+/=]+)')

def shrink(match):
    raw = base64.b64decode(match.group(2))
    try:
        im = Image.open(io.BytesIO(raw))
        im.load()
    except Exception:
        return match.group(0)  # leave unrecognized data alone

    if im.mode in ("RGBA", "P", "LA"):
        bg = Image.new("RGB", im.size, (255, 255, 255))
        im = im.convert("RGBA")
        bg.paste(im, mask=im.split()[-1])
        im = bg
    elif im.mode != "RGB":
        im = im.convert("RGB")

    w, h = im.size
    if max(w, h) > MAX_DIM:
        scale = MAX_DIM / max(w, h)
        im = im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)

    out = io.BytesIO()
    im.save(out, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    new_b64 = base64.b64encode(out.getvalue())
    return b'data:image/jpeg;base64,' + new_b64

def main():
    in_path, out_path = sys.argv[1], sys.argv[2]
    with open(in_path, "rb") as f:
        data = f.read()
    before = len(data)
    data = IMG_RE.sub(shrink, data)
    after = len(data)
    with open(out_path, "wb") as f:
        f.write(data)
    print(f"{before/1e6:.1f}MB -> {after/1e6:.1f}MB", file=sys.stderr)

if __name__ == "__main__":
    main()
