"""Check renderer contours while allowing each platform's edge antialiasing."""
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter
import sys
import json

directory = Path(sys.argv[1])
result = []

def mask(name):
    im = Image.open(name).convert("RGB")
    out = Image.new("L", im.size)
    out.putdata([255 if g > 100 and g > r * 1.1 and g > b * 1.2 else 0
                 for r, g, b in im.getdata()])
    return out

def count(im):
    return sum(im.histogram()[1:])

for frame in json.loads((directory / "parity-frames.json").read_text()):
    name = frame["label"]
    qt = mask(directory / ("qt-" + name + ".png"))
    ref = mask(directory / ("browser-" + name + ".png"))
    union = count(ImageChops.lighter(qt, ref))
    intersection = count(ImageChops.darker(qt, ref))
    missed = count(ImageChops.subtract(qt, ref.filter(ImageFilter.MaxFilter(5))))
    missed += count(ImageChops.subtract(ref, qt.filter(ImageFilter.MaxFilter(5))))
    pixels = count(qt) + count(ref)
    row = dict(frame=name, iou=intersection / max(1, union),
               within_two_pixels=1 - missed / max(1, pixels),
               qt_pixels=count(qt), browser_pixels=count(ref))
    result.append(row)
    assert row["iou"] > .92 and row["within_two_pixels"] > .995, row
(directory / "renderer-parity.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
