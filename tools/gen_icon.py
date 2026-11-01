"""生成《？！珠珠！？》应用图标 icon.png（512x512，命运琉璃珠 + 裂纹 + 星尘）。
运行： python tools/gen_icon.py
"""
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W = H = 512
random.seed(7)
rng = np.random.default_rng(7)

# ---------- 背景：深靛径向渐变 + 星尘 ----------
yy, xx = np.mgrid[0:H, 0:W]
cx, cy = W / 2, H / 2
dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (W * 0.65)
base = 1.0 - np.clip(dist, 0, 1)
bg = np.zeros((H, W, 3), dtype=np.float32)
inner = np.array([0.16, 0.10, 0.30], dtype=np.float32)   # 紫
outer = np.array([0.035, 0.025, 0.075], dtype=np.float32)  # 深靛
for c in range(3):
    bg[..., c] = outer[c] + (inner[c] - outer[c]) * (base ** 1.6)
bg += rng.normal(0, 0.006, (H, W, 1)).astype(np.float32)
# 星点
for _ in range(220):
    x, y = random.randint(0, W - 1), random.randint(0, H - 1)
    r = random.choice([0, 0, 1])
    v = random.uniform(0.35, 0.95)
    bg[max(0, y - r):y + r + 1, max(0, x - r):x + r + 1] += np.array([v, v * 0.95, v * 0.8], dtype=np.float32) * 0.5
img = Image.fromarray(np.clip(bg * 255, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

# ---------- 光环 ----------
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
for i, (rad, alpha, col) in enumerate([
    (206, 26, (154, 123, 255)),
    (188, 34, (232, 195, 106)),
    (168, 22, (111, 224, 176)),
]):
    gd.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], outline=col + (alpha,), width=2)
glow = glow.filter(ImageFilter.GaussianBlur(3))
img.alpha_composite(glow)

# ---------- 命运琉璃珠 ----------
marble = Image.new("RGBA", (W, H), (0, 0, 0, 0))
md = ImageDraw.Draw(marble)
R = 150
# 外发光
for i in range(20, 0, -1):
    a = int(18 * (i / 20) ** 2)
    md.ellipse([cx - R - i * 3, cy - R - i * 3, cx + R + i * 3, cy + R + i * 3],
               fill=(140, 200, 255, a))
# 珠体径向渐变
for r in range(R, 0, -1):
    t = r / R
    col = (
        int(226 * (1 - t) ** 1.5 + 70 * t),
        int(240 * (1 - t) ** 1.3 + 150 * t),
        int(255 * (1 - t) ** 1.2 + 220 * t),
        int(255 * (1 - t) ** 2.4 + 70 * t * 0.7),
    )
    md.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
marble = marble.filter(ImageFilter.GaussianBlur(1))

# 裂纹（金色，递归分叉）
cracks = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(cracks)


def branch(x, y, ang, length, width, depth):
    if depth <= 0 or length < 6:
        return
    step = 7.0
    n = int(length / step)
    px, py = x, y
    a = ang
    for i in range(n):
        a += random.uniform(-0.42, 0.42)
        nx, ny = px + math.cos(a) * step, py + math.sin(a) * step
        t = i / max(n - 1, 1)
        alpha = int(255 * (1 - t * 0.55))
        cd.line([(px, py), (nx, ny)], fill=(255, 214, 130, alpha), width=max(1, int(width * (1 - t * 0.5))))
        px, py = nx, ny
        if random.random() < 0.16 and depth > 1:
            branch(px, py, a + random.uniform(-1.1, 1.1), length * random.uniform(0.35, 0.6), width * 0.7, depth - 1)
    if depth > 1:
        branch(px, py, a + random.uniform(-0.9, 0.9), length * random.uniform(0.3, 0.5), width * 0.65, depth - 1)


for k in range(4):
    ang = -0.6 + k * 1.55 + random.uniform(-0.3, 0.3)
    branch(cx + math.cos(ang) * 26, cy + math.sin(ang) * 26, ang, R * random.uniform(0.85, 1.15), 2.6, 3)
cracks_glow = cracks.filter(ImageFilter.GaussianBlur(4))
cracks = Image.alpha_composite(cracks_glow, cracks)

img.alpha_composite(marble)
# 裂纹裁剪在珠内
clip = Image.new("L", (W, H), 0)
ImageDraw.Draw(clip).ellipse([cx - R + 2, cy - R + 2, cx + R - 2, cy + R - 2], fill=255)
cracks.putalpha(Image.composite(cracks.getchannel("A"), Image.new("L", (W, H), 0), clip))
img.alpha_composite(cracks)
# 高光
hi = Image.new("RGBA", (W, H), (0, 0, 0, 0))
hd = ImageDraw.Draw(hi)
hd.ellipse([cx - 96, cy - 112, cx + 6, cy - 44], fill=(255, 255, 255, 92))
hd.ellipse([cx - 40, cy - 104, cx - 8, cy - 72], fill=(255, 255, 255, 150))
hi = hi.filter(ImageFilter.GaussianBlur(6))
img.alpha_composite(hi)

# 圆角遮罩
mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], radius=96, fill=255)
out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
out.paste(img, (0, 0), mask)
out.save("G:/GoDot/？！珠珠！？/icon.png")
print("saved icon.png")
