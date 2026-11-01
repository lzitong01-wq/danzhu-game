#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《！？珠珠？！》像素风程序化美术生成脚本（v1.3，可重复运行）。

设计约束：
  * 先用低分辨率逐像素绘制，再用 NEAREST 放大到目标尺寸（路径/尺寸不变）；
  * 限定调色板（深靛 / 命途紫 / 鎏金 / 幽玉 / 白 / 黑），无平滑渐变；
  * 渐变使用 4×4 Bayer 有序抖动；1px 明暗边；不使用抗锯齿模糊。

用法：python tools/gen_art.py
"""

from __future__ import annotations

import math
import random
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets" / "art"
ICONS = ART / "icons"
FONTS = ROOT / "assets" / "fonts"

W, H = 1280, 720

# ------------------------------------------------------------------ 调色板

COL = {
    "void": "05030a",
    "bg_deep": "0a0713",
    "bg_mid": "121021",
    "bg_mid2": "161028",
    "bg_low": "1e1536",
    "panel": "221838",
    "panel2": "2b2438",
    "edge": "3a2a52",
    "edge2": "5b4a86",
    "violet_dim": "5c45a8",
    "violet": "9a7bff",
    "violet_hi": "c9b6ff",
    "violet_pale": "e6dcff",
    "gold_dark": "6b5424",
    "gold_dim": "a98b45",
    "gold": "e8c36a",
    "gold_hi": "ffe9a8",
    "gold_pale": "fff6d8",
    "jade_dark": "1f5c48",
    "jade_dim": "2f8f6b",
    "jade": "6fe0b0",
    "jade_hi": "bfffe6",
    "crimson_dark": "7a2b3a",
    "crimson": "ff5d6c",
    "crimson_hi": "ffb3a8",
    "text": "f3e9d2",
    "text_dim": "b6aec9",
    "white": "ffffff",
}

# 低对比环纹专用色（≈25% 透明度混入底色；不加入全局调色板，避免影响其他图）
RING_GOLD = "#221a17"
RING_VIOLET = "#241a44"


def rgb(hex_str: str) -> tuple[int, int, int]:
    hex_str = hex_str.lstrip("#")
    return tuple(int(hex_str[i:i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def rgba(hex_str: str, alpha: int = 255) -> tuple[int, int, int, int]:
    return (*rgb(hex_str), alpha)


# ImageDraw 需要 "#rrggbb" 形式；统一加前缀，rgb()/rgba() 会去掉它。
COL = {key: "#" + value for key, value in COL.items()}

_PALETTE_HEX = list(dict.fromkeys(COL.values()))
PAL_ARR = np.array([rgb(h) for h in _PALETTE_HEX], dtype=np.float32)

BAYER4 = np.array([
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
], dtype=np.float32) / 16.0 - 0.5


# ------------------------------------------------------------------ 基础工具

def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)
    print(f"  -> {path.relative_to(ROOT)}  {img.size[0]}x{img.size[1]}  {path.stat().st_size // 1024} KB")


def upscale(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    return img.resize(size, Image.NEAREST)


def vertical_gradient(w: int, h: int,
                      stops: list[tuple[float, str]]) -> np.ndarray:
    pos = np.array([s[0] for s in stops], dtype=np.float32)
    cols = np.array([rgb(s[1]) for s in stops], dtype=np.float32)
    ys = np.linspace(0.0, 1.0, h, dtype=np.float32)
    channels = [np.interp(ys, pos, cols[:, i]) for i in range(3)]
    return np.repeat(np.stack(channels, axis=1)[:, None, :], w, axis=1)


def dither_to_palette(arr: np.ndarray) -> Image.Image:
    """把浮点 RGB 用 Bayer 抖动量化到限定调色板，输出低分辨率 RGB 图。"""
    h, w, _ = arr.shape
    tile = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w][..., None]
    work = arr + tile * 16.0
    dist = ((work[..., None, :] - PAL_ARR[None, None, :, :]) ** 2).sum(axis=-1)
    idx = dist.argmin(axis=-1)
    return Image.fromarray(PAL_ARR[idx].astype(np.uint8), "RGB")


def apply_vignette(arr: np.ndarray, strength: float = 0.55,
                   inner: float = 0.42) -> np.ndarray:
    h, w, _ = arr.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (xx - w / 2) / (w / 2)
    ny = (yy - h / 2) / (h / 2)
    d = np.sqrt(nx * nx * 0.85 + ny * ny)
    v = 1.0 - strength * np.clip((d - inner) / (1.3 - inner), 0, 1) ** 1.4
    return arr * v[..., None]


def scatter_stars(draw: ImageDraw.ImageDraw, rng: random.Random, count: int,
                  region: tuple[float, float, float, float],
                  colors: list[str], big_chance: float = 0.16) -> None:
    x0, y0, x1, y1 = region
    for _ in range(count):
        x = int(rng.uniform(x0, x1))
        y = int(rng.uniform(y0, y1))
        color = COL[rng.choice(colors)]
        if rng.random() < big_chance:
            draw.rectangle((x, y, x + 1, y + 1), fill=color)
        else:
            draw.point((x, y), fill=color)


def pixel_ring(draw: ImageDraw.ImageDraw, cx: int, cy: int, radius: int,
               color: str) -> None:
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius),
                 outline=COL[color], width=1)


def centered_rect(w: int, h: int) -> tuple[int, int, int, int]:
    return 0, 0, w - 1, h - 1


# ------------------------------------------------------------------ 背景

def gen_bg_menu() -> None:
    print("[bg_menu] 像素风命运回廊背景")
    lw, lh = 320, 180
    rng = random.Random(20260228)
    arr = vertical_gradient(lw, lh, [
        (0.00, COL["void"]),
        (0.32, COL["bg_mid"]),
        (0.62, COL["bg_mid2"]),
        (0.84, COL["bg_low"]),
        (1.00, COL["bg_deep"]),
    ])
    arr = apply_vignette(arr, 0.62, 0.34)
    img = dither_to_palette(arr)
    d = ImageDraw.Draw(img)

    # 巨型弹珠台拱/环（低透明度 -> 暗金/暗紫）
    for i, radius in enumerate((150, 122, 96, 72, 50)):
        color = "gold_dark" if i % 2 == 0 else "edge2"
        pixel_ring(d, 160, 190, radius, color)

    # 透视立柱剪影（越往下越大）
    for row in range(9):
        y = 30 + row * 16
        scale = 0.55 + row * 0.09
        for col in range(15):
            x = 160 + int((col - 7) * 21 * scale)
            radius = int(1 + scale * 1.4)
            if 0 <= x < lw:
                d.ellipse((x - radius, y - radius, x + radius, y + radius),
                          outline=COL["edge2"])

    # 斜向引轨
    for x0 in (40, 90, 230, 280):
        d.line((x0, 0, x0 + (x0 - 160) * 0.25, lh), fill=COL["violet_dim"])

    # 裂纹（琉璃裂痕）：暗金描边 + 亮金核心
    crack = [(232, 6), (226, 22), (216, 30), (220, 44), (208, 56), (212, 72),
             (200, 84), (204, 100), (190, 114), (194, 132), (182, 148), (186, 172)]
    d.line(crack, fill=COL["gold_dark"], width=3)
    d.line(crack, fill=COL["gold"], width=1)
    for branch in (
        [(216, 30), (200, 26), (190, 18)],
        [(208, 56), (192, 52), (182, 44)],
        [(212, 72), (228, 76), (238, 86)],
        [(200, 84), (186, 90), (176, 88)],
        [(204, 100), (218, 106), (228, 116)],
    ):
        d.line(branch, fill=COL["gold_dim"], width=1)

    # 星尘与鎏金粒子
    scatter_stars(d, rng, 190, (0, 0, lw, lh * 0.82),
                  ["text", "violet", "jade", "gold", "gold_hi"], 0.10)
    for _ in range(46):
        x = rng.randint(0, lw - 1)
        y = rng.randint(6, int(lh * 0.9))
        d.point((x, y), fill=COL[rng.choice(["gold", "gold_hi"])])
    # 底部压暗
    d.rectangle((0, 156, lw, lh), fill=COL["void"])

    save(upscale(img, (W, H)), ART / "bg_menu.png")


def gen_bg_board() -> None:
    """安静的像素台面背景：暗、低对比，立柱/绿连线才是主体。"""
    print("[bg_board] 像素风弹珠台背景（低对比）")
    lw, lh = 320, 180
    rng = random.Random(731915)
    arr = vertical_gradient(lw, lh, [
        (0.00, COL["void"]),
        (0.16, COL["bg_deep"]),
        (0.55, COL["bg_mid"]),
        (0.82, COL["bg_mid2"]),
        (1.00, COL["void"]),
    ])
    # 整体再压暗（约 -35%）
    arr = arr * 0.72
    arr = apply_vignette(arr, 0.72, 0.30)
    img = dither_to_palette(arr)
    d = ImageDraw.Draw(img)

    # 极淡的像素网格（保留像素台面质感）
    for gx in range(0, lw, 8):
        for gy in range(0, lh, 8):
            d.point((gx, gy), fill=COL["bg_deep"])

    # 中央神殿纹样：只留 3 圈低对比同心环（≈25% 透明度深紫/暗金）
    cx, cy = 160, 84
    for radius, color in ((38, RING_VIOLET), (62, RING_GOLD), (86, RING_VIOLET)):
        d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius),
                  outline=color, width=1)

    # 稀疏星点
    scatter_stars(d, rng, 60, (0, 8, lw, lh * 0.9),
                  ["text_dim", "edge2"], 0.06)
    # 顶部 HUD / 底部槽位压暗
    d.rectangle((0, 0, lw, 8), fill=COL["void"])
    d.rectangle((0, 150, lw, lh), fill=COL["void"])

    save(upscale(img, (W, H)), ART / "bg_board.png")


def gen_bg_corridor() -> None:
    """640×180 像素走廊，周期 160px，可左右无缝平铺。"""
    print("[bg_corridor] 像素风 2D 走廊背景")
    lw, lh = 640, 180
    period = 160
    floor_y = 141
    rng = random.Random(112358)
    arr = vertical_gradient(lw, lh, [
        (0.00, COL["void"]),
        (0.28, COL["bg_mid"]),
        (0.62, COL["bg_mid2"]),
        (0.78, COL["bg_low"]),
        (1.00, COL["void"]),
    ])
    arr = apply_vignette(arr, 0.44, 0.5)
    img = dither_to_palette(arr)
    d = ImageDraw.Draw(img)

    # 立柱（周期 160，x=0/160/320/480/640 同时绘制保证接缝）
    for x0 in range(0, lw + 1, period):
        d.rectangle((x0 - 7, 18, x0 + 7, floor_y), fill=COL["panel"])
        d.rectangle((x0 - 7, 18, x0 - 4, floor_y), fill=COL["edge2"])
        d.rectangle((x0 + 5, 18, x0 + 7, floor_y), fill=COL["void"])
        d.rectangle((x0 - 10, 14, x0 + 10, 20), fill=COL["panel2"])
        d.rectangle((x0 - 9, floor_y - 4, x0 + 9, floor_y), fill=COL["panel2"])
        d.rectangle((x0 - 7, 24, x0 + 7, 25), fill=COL["gold_dim"])
        d.rectangle((x0 - 7, 108, x0 + 7, 109), fill=COL["gold_dark"])

    # 拱门 + 命灯（每个开间中央）
    for cx in range(period // 2, lw, period):
        d.arc((cx - 60, 12, cx + 60, 132), 180, 360,
              fill=COL["gold_dim"], width=2)
        d.arc((cx - 52, 20, cx + 52, 124), 180, 360,
              fill=COL["edge2"], width=1)
        # 命灯：吊线 + 阶梯光点
        d.line((cx, 14, cx, 30), fill=COL["gold_dark"])
        d.rectangle((cx - 2, 31, cx + 2, 35), fill=COL["gold"])
        d.rectangle((cx - 1, 32, cx + 1, 34), fill=COL["gold_hi"])
        d.point((cx, 33), fill=COL["white"])
        # 极淡光柱（用像素列抖动）
        for yy in range(38, floor_y - 2):
            if (yy % 4) < 2:
                d.point((cx - 3, yy), fill=COL["bg_low"])
                d.point((cx + 3, yy), fill=COL["bg_low"])

    # 地砖
    d.rectangle((0, floor_y, lw, lh), fill=COL["bg_deep"])
    d.rectangle((0, floor_y, lw, floor_y + 1), fill=COL["gold_dim"])
    for y in (floor_y + 9, floor_y + 20, floor_y + 33):
        d.line((0, y, lw, y), fill=COL["edge"])
    for x in range(0, lw + 1, 20):
        d.line((x, floor_y + 1, x, lh), fill=COL["edge"])
    # 地面反光
    for x0 in range(0, lw + 1, period):
        d.rectangle((x0 - 8, floor_y - 2, x0 + 8, floor_y - 1),
                    fill=COL["gold_dark"])

    scatter_stars(d, rng, 170, (0, 14, lw, floor_y - 6),
                  ["text", "violet", "jade"], 0.07)
    save(upscale(img, (2560, 720)), ART / "bg_corridor.png")


# ------------------------------------------------------------------ 珠子 / 门 / 守卫

def orb_low(base: str, mid: str, light: str, dark: str, rim: str) -> Image.Image:
    """16×16 像素玻璃珠：1px 描边 + 四档明暗 + 左上高光。"""
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    for y in range(16):
        for x in range(16):
            dx = (x - 7.5) / 7.4
            dy = (y - 7.5) / 7.4
            r = math.hypot(dx, dy)
            if r > 1.02:
                continue
            shade = -(dx + dy) * 0.38 + (1.0 - r) * 0.55
            if r > 0.88:
                color = rim
            elif shade > 0.62:
                color = light
            elif shade > 0.18:
                color = mid
            elif shade > -0.30:
                color = base
            else:
                color = dark
            px[x, y] = rgba(COL[color])
    # 左上高光 2px
    for (hx, hy) in ((4, 3), (5, 3), (4, 4)):
        px[hx, hy] = rgba(COL["white"])
    # 右下 1px 暗边
    for (ox, oy) in ((11, 12), (12, 11), (10, 13), (13, 10)):
        if px[ox, oy][3] > 0:
            px[ox, oy] = rgba(COL[dark])
    return img


def gen_orbs() -> None:
    print("[pegs/balls] 像素玻璃珠")
    specs = {
        "peg_normal.png": ("edge2", "text_dim", "white", "panel2", "text_dim"),
        "peg_yellow.png": ("gold_dim", "gold", "gold_hi", "gold_dark", "gold_hi"),
        "peg_green.png": ("jade_dim", "jade", "jade_hi", "jade_dark", "jade_hi"),
        "peg_black.png": ("panel2", "edge", "violet", "void", "violet"),
        "peg_white.png": ("text_dim", "text", "white", "edge2", "white"),
        "ball_normal.png": ("edge2", "violet_hi", "white", "violet_dim", "violet_pale"),
        "ball_advanced.png": ("gold_dim", "gold", "gold_pale", "gold_dark", "gold_hi"),
    }
    for name, spec in specs.items():
        low = orb_low(*spec)
        save(upscale(low, (48, 48)), ART / name)


def gen_guardian() -> None:
    print("[guardian] 像素命运之眼")
    lw, lh = 32, 32
    img = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 阶梯式红紫灵光（抖动像素）
    for radius, color in ((15, "crimson_dark"), (13, "crimson_dark"),
                          (10, "edge2"), (7, "violet_dim")):
        d.ellipse((16 - radius, 17 - radius, 16 + radius, 17 + radius),
                  outline=COL[color])

    # 斗篷黑影
    hood = [(16, 3), (10, 6), (7, 11), (7, 18), (5, 24), (4, 30), (12, 31),
            (16, 31), (20, 31), (28, 30), (27, 24), (25, 18), (25, 11),
            (22, 6)]
    d.polygon(hood, fill=COL["void"])
    d.polygon([(16, 7), (12, 12), (12, 22), (16, 27), (20, 22), (20, 12)],
              fill=COL["bg_mid"])
    # 肩部紫光边
    d.line((8, 27, 3, 31), fill=COL["violet_dim"])
    d.line((24, 27, 29, 31), fill=COL["violet_dim"])

    # 命运之眼
    d.rectangle((10, 14, 21, 15), fill=COL["crimson_dark"])
    d.rectangle((11, 13, 20, 16), fill=COL["crimson"])
    d.rectangle((13, 13, 18, 16), fill=COL["crimson_hi"])
    d.rectangle((14, 12, 17, 17), fill=COL["violet_hi"])
    d.rectangle((15, 12, 16, 17), fill=COL["void"])
    d.point((15, 13), fill=COL["white"])
    # 眼部暗金描边
    d.line((10, 13, 10, 16), fill=COL["gold_dark"])
    d.line((21, 13, 21, 16), fill=COL["gold_dark"])
    # 下方触须
    d.line((12, 29, 10, 31), fill=COL["violet_dim"])
    d.line((20, 29, 22, 31), fill=COL["violet_dim"])

    save(upscale(img, (128, 128)), ART / "guardian.png")


def gen_particle_dot() -> None:
    print("[particle_dot] 像素柔光点")
    low = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    levels = {
        (3, 1): 70, (4, 1): 70, (2, 2): 110, (3, 2): 200, (4, 2): 200,
        (5, 2): 110, (1, 3): 70, (2, 3): 200, (3, 3): 255, (4, 3): 255,
        (5, 3): 200, (6, 3): 70, (1, 4): 70, (2, 4): 200, (3, 4): 255,
        (4, 4): 255, (5, 4): 200, (6, 4): 70, (2, 5): 110, (3, 5): 200,
        (4, 5): 200, (5, 5): 110, (3, 6): 70, (4, 6): 70,
    }
    px = low.load()
    for (x, y), alpha in levels.items():
        px[x, y] = (255, 255, 255, alpha)
    save(upscale(low, (16, 16)), ART / "particle_dot.png")


def gen_door() -> None:
    print("[door] 像素命运之门")
    lw, lh = 50, 80
    img = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 外发光（阶梯紫）
    d.rectangle((4, 10, 45, 79), fill=COL["violet_dim"])
    d.ellipse((4, 4, 45, 45), fill=COL["violet_dim"])

    # 门框
    d.rectangle((7, 13, 42, 79), fill=COL["gold_dim"])
    d.ellipse((7, 7, 42, 42), fill=COL["gold_dim"])
    # 右侧阴影 / 左侧高光
    d.rectangle((7, 13, 10, 79), fill=COL["gold"])
    d.rectangle((39, 13, 42, 79), fill=COL["gold_dark"])
    d.arc((7, 7, 42, 42), 180, 360, fill=COL["gold_hi"], width=2)

    # 门内暗腔
    d.rectangle((13, 20, 36, 79), fill=COL["void"])
    d.ellipse((13, 14, 36, 37), fill=COL["void"])
    # 门内幽光（阶梯紫 + 底部暖金）
    for radius, color in ((9, "violet_dim"), (6, "violet_dim"),
                          (4, "violet"), (2, "violet_hi")):
        d.ellipse((25 - radius, 42 - radius, 25 + radius, 42 + radius),
                  outline=COL[color])
    d.rectangle((23, 50, 27, 59), fill=COL["gold_dark"])
    d.rectangle((24, 48, 26, 56), fill=COL["gold_dim"])
    d.point((25, 52), fill=COL["gold_hi"])

    # 门框细节：内圈金线、横向铁条、铆钉、门槛
    d.rectangle((11, 20, 38, 21), fill=COL["gold_dark"])
    for y in (30, 44, 58, 72):
        d.rectangle((12, y, 37, y), fill=COL["gold_dark"])
    for y in (28, 60):
        d.rectangle((8, y, 9, y + 1), fill=COL["gold_hi"])
        d.rectangle((40, y, 41, y + 1), fill=COL["gold_hi"])
    d.rectangle((5, 77, 44, 79), fill=COL["gold_dark"])
    d.rectangle((5, 77, 44, 78), fill=COL["gold_dim"])
    # 中缝
    d.rectangle((24, 22, 25, 76), fill=COL["gold_dark"])

    save(upscale(img, (200, 320)), ART / "door.png")


# ------------------------------------------------------------------ 图标（16×16 → 64×64）

def icon_canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def card_base(d: ImageDraw.ImageDraw) -> None:
    d.rectangle((1, 0, 14, 15), fill=COL["bg_mid2"])
    d.rectangle((1, 0, 14, 0), fill=COL["gold_dim"])
    d.rectangle((1, 15, 14, 15), fill=COL["gold_dim"])
    d.rectangle((1, 0, 1, 15), fill=COL["gold_dim"])
    d.rectangle((14, 0, 14, 15), fill=COL["gold_dim"])
    d.rectangle((2, 1, 13, 1), fill=COL["edge2"])
    d.rectangle((2, 14, 13, 14), fill=COL["edge2"])


def icon_coin() -> None:
    img, d = icon_canvas()
    d.ellipse((2, 2, 13, 13), fill=COL["gold"])
    d.ellipse((2, 2, 13, 13), outline=COL["gold_dark"])
    d.ellipse((4, 4, 11, 11), fill=COL["gold_hi"])
    d.rectangle((7, 5, 8, 10), fill=COL["gold_dark"])
    d.rectangle((5, 7, 10, 8), fill=COL["gold_dark"])
    d.point((4, 3), fill=COL["white"])
    save(upscale(img, (64, 64)), ICONS / "coin.png")


def icon_shard() -> None:
    img, d = icon_canvas()
    d.polygon([(8, 1), (12, 7), (10, 14), (8, 15), (6, 14), (4, 7)],
              fill=COL["violet"])
    d.polygon([(8, 1), (8, 15), (6, 14), (4, 7)], fill=COL["violet_dim"])
    d.line((8, 2, 8, 14), fill=COL["violet_pale"])
    d.line((5, 7, 8, 9), fill=COL["jade"])
    d.line((8, 9, 11, 7), fill=COL["jade"])
    save(upscale(img, (64, 64)), ICONS / "shard.png")


def icon_reflector() -> None:
    img, d = icon_canvas()
    d.arc((2, 1, 13, 12), 180, 360, fill=COL["text_dim"], width=3)
    d.arc((3, 2, 12, 11), 200, 340, fill=COL["white"], width=1)
    d.line((3, 8, 1, 14), fill=COL["violet"])
    d.line((12, 8, 14, 14), fill=COL["violet_dim"])
    d.line((1, 10, 0, 10), fill=COL["text_dim"])
    d.line((14, 10, 15, 10), fill=COL["text_dim"])
    save(upscale(img, (64, 64)), ICONS / "reflector.png")


def icon_sticky() -> None:
    img, d = icon_canvas()
    d.ellipse((3, 5, 12, 14), fill=COL["jade_dim"])
    d.ellipse((4, 6, 11, 13), fill=COL["jade"])
    d.polygon([(8, 1), (10, 6), (8, 8), (6, 6)], fill=COL["jade"])
    d.rectangle((6, 8, 7, 9), fill=COL["jade_hi"])
    d.rectangle((9, 10, 10, 11), fill=COL["jade_hi"])
    save(upscale(img, (64, 64)), ICONS / "sticky.png")


def icon_powercard() -> None:
    img, d = icon_canvas()
    card_base(d)
    d.polygon([(9, 3), (5, 8), (8, 8), (7, 12), (11, 7), (8, 7)],
              fill=COL["gold"])
    save(upscale(img, (64, 64)), ICONS / "powercard.png")


def icon_splitcard() -> None:
    img, d = icon_canvas()
    card_base(d)
    d.rectangle((7, 7, 8, 8), fill=COL["violet"])
    d.rectangle((4, 3, 5, 4), fill=COL["violet_hi"])
    d.rectangle((10, 3, 11, 4), fill=COL["violet_hi"])
    d.line((6, 5, 7, 6), fill=COL["violet_pale"])
    d.line((9, 5, 8, 6), fill=COL["violet_pale"])
    d.line((4, 5, 4, 7), fill=COL["violet_dim"])
    d.line((11, 5, 11, 7), fill=COL["violet_dim"])
    d.point((4, 3), fill=COL["white"])
    d.point((10, 3), fill=COL["white"])
    save(upscale(img, (64, 64)), ICONS / "splitcard.png")


def icon_masscard() -> None:
    img, d = icon_canvas()
    card_base(d)
    d.ellipse((5, 2, 10, 7), fill=COL["text_dim"])
    d.ellipse((5, 2, 10, 7), outline=COL["white"])
    d.rectangle((7, 8, 8, 11), fill=COL["gold"])
    d.polygon([(5, 10), (10, 10), (7, 13)], fill=COL["gold"])
    save(upscale(img, (64, 64)), ICONS / "masscard.png")


def icon_shrinkcard() -> None:
    img, d = icon_canvas()
    card_base(d)
    d.rectangle((3, 3, 12, 12), outline=COL["violet_dim"])
    d.rectangle((5, 5, 10, 10), outline=COL["violet"])
    d.rectangle((7, 7, 8, 8), fill=COL["violet_hi"])
    d.line((7, 1, 7, 3), fill=COL["jade"])
    d.line((7, 12, 7, 14), fill=COL["jade"])
    d.line((1, 7, 3, 7), fill=COL["jade"])
    d.line((12, 7, 14, 7), fill=COL["jade"])
    save(upscale(img, (64, 64)), ICONS / "shrinkcard.png")


def icon_gold_eye() -> None:
    img, d = icon_canvas()
    d.polygon([(1, 8), (5, 5), (10, 5), (14, 8), (10, 11), (5, 11)],
              fill=COL["gold"])
    d.polygon([(3, 8), (6, 6), (9, 6), (12, 8), (9, 10), (6, 10)],
              fill=COL["bg_deep"])
    d.rectangle((6, 6, 9, 9), fill=COL["violet"])
    d.rectangle((7, 6, 8, 9), fill=COL["void"])
    d.point((6, 6), fill=COL["white"])
    save(upscale(img, (64, 64)), ICONS / "gold_eye.png")


def icon_advanced_ball() -> None:
    img, d = icon_canvas()
    d.ellipse((2, 2, 13, 13), fill=COL["gold"])
    d.ellipse((4, 4, 11, 11), fill=COL["gold_hi"])
    d.arc((1, 5, 14, 12), 200, 340, fill=COL["violet"])
    d.rectangle((7, 1, 8, 4), fill=COL["gold_pale"])
    d.point((7, 2), fill=COL["white"])
    save(upscale(img, (64, 64)), ICONS / "advanced_ball.png")


def gen_icons() -> None:
    print("[icons] 像素道具图标")
    icon_coin()
    icon_shard()
    icon_reflector()
    icon_sticky()
    icon_powercard()
    icon_splitcard()
    icon_masscard()
    icon_shrinkcard()
    icon_gold_eye()
    icon_advanced_ball()


# ------------------------------------------------------------------ 新手引导小手

def gen_hand() -> None:
    """32×32 像素手指指针（新手引导用）。"""
    print("[ui_hand] 像素小手")
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 手指
    d.rectangle((7, 2, 8, 8), fill=COL["text"])
    d.rectangle((7, 2, 7, 8), fill=COL["white"])
    d.rectangle((6, 1, 9, 2), fill=COL["text_dim"])
    # 手掌
    d.rectangle((5, 7, 10, 12), fill=COL["text"])
    d.rectangle((4, 8, 5, 10), fill=COL["text"])
    d.rectangle((10, 8, 11, 9), fill=COL["text_dim"])
    d.rectangle((6, 12, 9, 13), fill=COL["text_dim"])
    # 金色像素描边
    for (x, y) in ((6, 1), (9, 1), (6, 13), (11, 8), (11, 10), (3, 8), (3, 11),
                   (5, 14), (10, 14), (12, 11)):
        d.point((x, y), fill=COL["gold"])
    save(upscale(img, (32, 32)), ART / "ui_hand.png")


# ------------------------------------------------------------------ 字体

def copy_fonts() -> None:
    print("[fonts] 复制中文字体")
    FONTS.mkdir(parents=True, exist_ok=True)
    pairs = [
        (Path(r"C:\Windows\Fonts\simhei.ttf"), FONTS / "FateBody.ttf"),
        (Path(r"C:\Windows\Fonts\simkai.ttf"), FONTS / "FateTitle.ttf"),
    ]
    for src, dst in pairs:
        if not src.exists():
            print(f"  !! 缺少字体源文件：{src}")
            continue
        shutil.copy2(src, dst)
        print(f"  -> {dst.relative_to(ROOT)}  {dst.stat().st_size // 1024} KB")


# ------------------------------------------------------------------ main

def main() -> None:
    ART.mkdir(parents=True, exist_ok=True)
    ICONS.mkdir(parents=True, exist_ok=True)
    print("=== 《！？珠珠？！》像素风美术资源生成 ===")
    gen_bg_menu()
    gen_bg_board()
    gen_bg_corridor()
    gen_door()
    gen_orbs()
    gen_guardian()
    gen_particle_dot()
    gen_hand()
    gen_icons()
    copy_fonts()
    print("=== 完成 ===")


if __name__ == "__main__":
    main()
