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
from PIL import Image, ImageChops, ImageDraw, ImageFilter

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

def orb_low(base: str, mid: str, light: str, dark: str, rim: str,
            glow: str | None = None) -> Image.Image:
    """16×16 像素玻璃珠：1px 描边 + 四档明暗 + 左上高光（可选外圈荧光）。"""
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
    # 外圈荧光（v1.5：命核/命源的金色辉光）
    if glow is not None:
        for y in range(16):
            for x in range(16):
                dx = (x - 7.5) / 7.4
                dy = (y - 7.5) / 7.4
                r = math.hypot(dx, dy)
                if 1.0 < r <= 1.24 and px[x, y][3] == 0:
                    alpha = int(140 * (1.0 - (r - 1.0) / 0.24))
                    px[x, y] = rgba(COL[glow], max(24, alpha))
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
        # v1.5 三阶琉璃珠：命运=透明偏白 / 命核=白+金色荧光 / 命源=纯金
        "ball_normal.png": ("text_dim", "violet_pale", "white", "edge2", "white"),
        "ball_advanced.png": ("gold_pale", "white", "white", "gold_dim", "gold",
                              "gold_hi"),
        "ball_source.png": ("gold_dim", "gold", "gold_pale", "gold_dark",
                            "gold_hi", "gold"),
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


# ------------------------------------------------------------------ 占星师角色（行走/待机精灵）

CHAR = {
    "cloak_edge": "#2b241f",
    "cloak_dark": "#3e342e",
    "cloak": "#5a4b40",
    "cloak_light": "#7a6857",
    "hood_dark": "#322a25",
    "hood": "#4a3e35",
    "skin": "#c9a98f",
    "skin_shadow": "#a4866d",
    "hair": "#3a2c22",
    "hair_light": "#55412f",
    "eye": "#241a14",
    "boot_dark": "#3a2414",
    "boot": "#5a3a1c",
    "boot_light": "#7a5228",
    "belt": "#2b241f",
    "pouch": "#6b4a2a",
    "shard_v": "#9a7bff",
    "shard_c": "#6fe0b0",
    "shard_w": "#e6dcff",
    "orb_glow": "#3b3770",
    "orb_edge": "#6f7fe0",
    "orb": "#a8b8ff",
    "orb_core": "#eef4ff",
}


def _astrologer_frame(walk_frame: int = -1, idle_frame: int = 0) -> Image.Image:
    """32×40 像素占星师单帧（朝右）。walk_frame>=0 为走路帧，否则为待机帧。"""
    img = Image.new("RGBA", (32, 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if walk_frame >= 0:
        idx = walk_frame % 6
        bob = [0, -1, -1, -1, 0, 0][idx]
        stride = [0, 1, 2, 0, -1, -2][idx]
        cape = [0, -1, -2, -1, 0, 1][idx]
        orb_dy = [0, -1, 0, 1, 0, -1][idx]
        front_lift = [0, 1, 0, 0, 0, 0][idx]
        back_lift = [0, 0, 0, 0, 0, 1][idx]
        glow = 0
    else:
        idx = idle_frame % 4
        bob = [0, -1, 0, 0][idx]
        stride = 0
        cape = [0, 0, -1, -1][idx]
        orb_dy = [0, -1, -1, 0][idx]
        front_lift = 0
        back_lift = 0
        glow = [0, 1, 1, 0][idx]

    # 整体下移 2px：让靴底贴住 64×80 帧底边（corridor/player.gd 以帧底为脚底）
    oy = bob + 2

    def rect(x0: int, y0: int, x1: int, y1: int, color: str) -> None:
        d.rectangle((x0, y0 + oy, x1, y1 + oy), fill=CHAR[color])

    def point(x: int, y: int, color: str) -> None:
        d.point((x, y + oy), fill=CHAR[color])

    def line(points: list[tuple[int, int]], color: str, width: int = 1) -> None:
        d.line([(px, py + oy) for px, py in points], fill=CHAR[color], width=width)

    # 后摆斗篷（左后方飘动）
    cape_pts = [
        (11 + cape, 10), (15, 9), (16, 13), (15, 33), (13, 35), (10, 33),
        (7 + cape, 30), (8 + cape, 23), (8 + cape, 15),
    ]
    d.polygon([(px, py + oy) for px, py in cape_pts], fill=CHAR["cloak_dark"])
    line([(11 + cape, 11), (9 + cape, 18), (9 + cape, 26)], "cloak")

    # 身体斗篷
    body_pts = [
        (14, 10), (20, 9), (22, 13), (21, 27), (19, 33), (16, 34),
        (14, 31), (13, 22),
    ]
    d.polygon([(px, py + oy) for px, py in body_pts], fill=CHAR["cloak"])
    d.polygon([(18, 12 + oy), (20, 14 + oy), (19, 26 + oy), (17, 31 + oy),
               (16, 27 + oy), (16, 17 + oy)], fill=CHAR["cloak_light"])
    line([(14, 12), (14, 28)], "cloak_edge")

    # 双腿（交替迈步）+ 棕靴
    front_x = 17 + stride * 2
    back_x = 13 - stride * 2
    rect(back_x, 28 + back_lift, back_x + 2, 33 + back_lift, "cloak_dark")
    rect(front_x, 28 + front_lift, front_x + 2, 33 + front_lift, "cloak_dark")
    rect(back_x - 1, 34 - back_lift, back_x + 3, 37 - back_lift, "boot_dark")
    rect(front_x - 1, 34 - front_lift, front_x + 3, 37 - front_lift, "boot")
    point(front_x + 1, 35 - front_lift, "boot_light")
    point(back_x, 35 - back_lift, "boot_light")

    # 兜帽 + 头部（朝右）
    hood_pts = [
        (12, 6), (14, 2), (19, 1), (22, 4), (23, 9), (21, 11), (19, 10),
        (17, 9), (15, 11), (13, 10),
    ]
    d.polygon([(px, py + oy) for px, py in hood_pts], fill=CHAR["hood"])
    line([(13, 4), (15, 2), (18, 2)], "hood_dark")
    rect(18, 4, 21, 8, "skin")
    rect(18, 7, 20, 8, "skin_shadow")
    rect(17, 3, 21, 5, "hair")
    point(18, 2, "hair_light")
    point(21, 4, "hair")
    point(20, 6, "eye")
    line([(17, 4), (17, 9)], "hood_dark")

    # 腰带与小袋
    rect(17, 24, 20, 25, "belt")
    rect(21, 24, 23, 27, "pouch")
    point(22, 25, "shard_v")

    # 斗篷下摆的琉璃碎片饰边
    for i, x in enumerate(range(11, 21, 2)):
        yy = 29 + ((i + idx) % 2)
        color = ["shard_v", "shard_c", "shard_w"][i % 3]
        point(x, yy, color)
    point(16, 9, "shard_v")
    point(17, 9, "shard_c")

    # 前伸手臂 + 星辉法球
    rect(20, 12, 23, 15, "cloak_light")
    rect(23, 13, 25, 15, "skin")
    ocx, ocy = 27, 12 + orb_dy + oy
    if glow > 0:
        d.ellipse((ocx - 4, ocy - 4, ocx + 4, ocy + 4), fill=CHAR["orb_glow"])
    else:
        d.ellipse((ocx - 3, ocy - 3, ocx + 3, ocy + 3), fill=CHAR["orb_glow"])
    d.ellipse((ocx - 2, ocy - 2, ocx + 2, ocy + 2), fill=CHAR["orb_edge"])
    d.ellipse((ocx - 1, ocy - 1, ocx + 1, ocy + 1), fill=CHAR["orb"])
    d.point((ocx, ocy), fill=CHAR["orb_core"])
    if glow > 0:
        d.point((ocx, ocy - 3), fill=CHAR["orb_core"])
        d.point((ocx - 3, ocy), fill=CHAR["orb"])

    return img


def gen_portrait() -> None:
    """角色面板用像素立绘：160×200 → NEAREST ×2 = 320×400。"""
    print("[portrait] 流浪占星师像素立绘")
    lw, lh = 160, 200
    img = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def c(name: str, alpha: int = 255) -> tuple[int, int, int, int]:
        hex_value = COL.get(name, CHAR.get(name))
        return rgba(hex_value, alpha)

    def p(x: int, y: int, name: str, alpha: int = 255) -> None:
        d.point((x, y), fill=c(name, alpha))

    # 背景星尘
    rng = random.Random(5150)
    for _ in range(46):
        x = rng.randint(4, lw - 5)
        y = rng.randint(4, 120)
        p(x, y, rng.choice(["violet_dim", "edge2", "text_dim"]),
          rng.randint(40, 140))

    # 兜帽外轮廓
    d.polygon([(56, 34), (70, 16), (98, 18), (112, 42), (110, 84), (92, 100),
               (64, 98), (52, 74)], fill=c("hood_dark"))
    d.polygon([(52, 74), (56, 34), (70, 16), (78, 22), (64, 56), (60, 88)],
              fill=c("hood"))
    # 兜帽边缘高光
    d.line([(55, 38), (66, 20), (80, 17)], fill=c("cloak"), width=2)

    # 面部（右脸受光，左脸阴影）
    d.polygon([(68, 52), (93, 50), (95, 84), (86, 90), (72, 85), (66, 68)],
              fill=c("skin_shadow"))
    d.polygon([(77, 51), (94, 50), (93, 82), (84, 87), (79, 72)],
              fill=c("skin"))
    d.polygon([(88, 55), (94, 56), (92, 82), (85, 85)],
              fill=c("skin_shadow"))
    # 头发刘海（不规则）
    d.polygon([(65, 44), (96, 41), (97, 52), (90, 48), (84, 54), (78, 49),
               (72, 55), (65, 53)], fill=c("hair"))
    d.point((70, 38), fill=c("hair_light"))
    d.point((88, 40), fill=c("hair"))
    d.point((94, 48), fill=c("hair"))
    # 眼睛（淡紫微光）+ 眉/鼻/唇
    d.rectangle((81, 63, 86, 65), fill=c("violet_hi"))
    d.point((84, 64), fill=c("white"))
    d.line([(79, 60), (87, 59)], fill=c("hair"))
    d.point((90, 70), fill=c("skin_shadow"))
    d.point((91, 71), fill=c("skin_shadow"))
    d.rectangle((85, 78, 89, 79), fill=c("skin_shadow"))
    # 兜帽内沿阴影
    d.line([(67, 45), (66, 68), (72, 87)], fill=c("hood_dark"))
    d.line([(96, 44), (97, 62)], fill=c("hood_dark"))

    # 围巾/领口
    d.polygon([(62, 92), (88, 98), (104, 92), (109, 108), (86, 118), (58, 108)],
              fill=c("cloak_edge"))
    # 身体斗篷
    d.polygon([(22, 200), (28, 132), (52, 104), (88, 100), (116, 108),
               (136, 136), (142, 200)], fill=c("cloak_dark"))
    d.polygon([(92, 108), (116, 112), (128, 138), (128, 200), (86, 200),
               (88, 130)], fill=c("cloak"))
    d.polygon([(96, 116), (114, 122), (120, 142), (120, 200), (96, 200),
               (94, 136)], fill=c("cloak_light"))
    # 斗篷褶皱
    for (x0, y0, x1, y1) in ((72, 130, 70, 200), (106, 132, 108, 200),
                             (120, 142, 122, 200)):
        d.line([(x0, y0), (x1, y1)], fill=c("cloak_edge"))
    # 琉璃碎片饰边
    for i, x in enumerate(range(60, 98, 6)):
        y = 106 + (i % 2) * 4
        p(x, y, ["shard_v", "shard_c", "shard_w"][i % 3])
    for i, x in enumerate(range(98, 134, 7)):
        p(x, 112 + (i % 2) * 3, ["shard_v", "shard_w"][i % 2])
    # 腰带
    d.rectangle((76, 168, 108, 174), fill=c("belt"))
    d.rectangle((110, 170, 122, 184), fill=c("pouch"))
    p(116, 176, "shard_v")

    # 举起的左手 + 星辉法球
    d.polygon([(104, 122), (122, 112), (132, 122), (124, 136), (110, 140)],
              fill=c("cloak"))
    d.rectangle((124, 124, 136, 132), fill=c("skin"))
    # 法球（阶梯式光晕）
    for radius, name in ((22, "orb_glow"), (18, "violet_dim"), (14, "orb_edge"),
                         (10, "orb"), (6, "violet_hi"), (3, "white")):
        d.ellipse((132 - radius, 116 - radius, 132 + radius, 116 + radius),
                  fill=c(name))
    d.point((128, 110), fill=c("white"))
    d.point((136, 112), fill=c("violet_pale"))

    save(upscale(img, (320, 400)), ART / "player_portrait.png")


def gen_app_icon() -> None:
    """512×512 游戏图标：命核琉璃珠居中偏左 + 右侧一点主角侧脸剪影。"""
    print("[app_icon] 游戏图标（命核珠 + 主角侧脸）")
    lw, lh = 128, 128
    arr = vertical_gradient(lw, lh, [
        (0.00, COL["void"]),
        (0.35, COL["bg_deep"]),
        (0.72, COL["bg_mid"]),
        (1.00, COL["void"]),
    ])
    arr = apply_vignette(arr, 0.55, 0.35)
    img = dither_to_palette(arr).convert("RGBA")
    d = ImageDraw.Draw(img)

    def c(name: str, alpha: int = 255) -> tuple[int, int, int, int]:
        hex_value = COL.get(name, CHAR.get(name))
        return rgba(hex_value, alpha)

    # 星尘
    rng = random.Random(9917)
    for _ in range(40):
        x = rng.randint(4, lw - 5)
        y = rng.randint(4, lh - 5)
        d.point((x, y), fill=rgba(COL[rng.choice(["text_dim", "edge2",
                                                 "violet_dim"])],
                rng.randint(60, 170)))

    # 右侧主角侧脸剪影（只露一点）
    d.polygon([(100, 128), (96, 88), (102, 54), (114, 34), (128, 26),
               (128, 128)], fill=c("hood_dark"))
    d.polygon([(104, 128), (102, 92), (108, 62), (118, 44), (128, 38),
               (128, 128)], fill=c("hood"))
    # 侧脸露出的鼻/唇轮廓与眼睛微光
    d.polygon([(108, 60), (116, 58), (120, 68), (116, 78), (110, 82),
               (106, 74)], fill=c("skin"))
    d.polygon([(114, 60), (120, 68), (116, 78), (112, 74)],
              fill=c("skin_shadow"))
    d.rectangle((116, 66, 120, 68), fill=c("violet_hi"))
    d.point((118, 67), fill=c("white"))
    # 兜帽边缘金线
    d.line([(100, 96), (104, 66), (114, 42), (128, 30)],
           fill=rgba(COL["gold"], 255), width=1)
    d.line([(101, 94), (105, 66), (115, 43)], fill=rgba(COL["gold_hi"], 255),
           width=1)

    # 主体命核琉璃珠（居中偏左）
    cx, cy = 58, 64
    for radius, name in ((42, "gold_dark"), (38, "gold_dim"), (34, "gold"),
                         (30, "gold_hi"), (26, "gold_pale"), (22, "white")):
        d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius),
                  fill=rgba(COL[name], 255))
    # 高光与暗部
    d.ellipse((cx - 18, cy - 22, cx - 2, cy - 6), fill=rgba(COL["white"], 255))
    d.arc((cx - 34, cy - 34, cx + 34, cy + 34), 20, 120,
          fill=rgba(COL["gold_dark"], 255), width=4)
    # 金色荧光点
    for (px_, py_) in ((cx - 40, cy - 24), (cx + 32, cy - 34), (cx - 36, cy + 30)):
        d.rectangle((px_, py_, px_ + 1, py_ + 1),
                    fill=rgba(COL["gold_hi"], 255))

    save(upscale(img, (512, 512)), ART / "app_icon.png")


def gen_player_sprites() -> None:
    """64×80 × 6 帧走路 / × 4 帧待机，横向 sprite sheet，透明底。"""
    print("[player] 像素占星师走路/待机 sprite sheet")
    walk_frames = [upscale(_astrologer_frame(walk_frame=i), (64, 80))
                   for i in range(6)]
    idle_frames = [upscale(_astrologer_frame(idle_frame=i), (64, 80))
                   for i in range(4)]

    def make_sheet(frames: list[Image.Image], name: str) -> None:
        sheet = Image.new("RGBA", (64 * len(frames), 80), (0, 0, 0, 0))
        for i, frame in enumerate(frames):
            sheet.alpha_composite(frame, (64 * i, 0))
        save(sheet, ART / name)

    make_sheet(walk_frames, "player_walk.png")
    make_sheet(idle_frames, "player_idle.png")


def gen_player_sprites_from_cutout() -> None:
    """v1.6：严格基于用户原图抠图 char_cutout.png 生成动画（不重绘人物）。
    72×222 × 6 帧走路 / × 4 帧待机，透明底，脚底贴帧底。
    动画仅做：整体上下 bob（底部锚定缩放）、轻微前倾/后仰、斗篷下摆 1~2px
    摆动、法球光晕呼吸。
    """
    print("[player] 基于 char_cutout 生成走路/待机 sprite sheet（不重绘）")
    src = Image.open(ART / "char_cutout.png").convert("RGBA")
    # 原图 320×986，与 72×222 比例一致（0.3245）
    base = src.resize((72, 222), Image.LANCZOS)

    def make_frame(height: int, angle: float, cape_shift: int,
                   glow_amt: float) -> Image.Image:
        img = base.resize((72, height), Image.LANCZOS)
        canvas = Image.new("RGBA", (72, 222), (0, 0, 0, 0))
        canvas.alpha_composite(img, (0, 222 - height))
        # 轻微前倾/后仰：绕脚底中心旋转
        if abs(angle) > 0.01:
            canvas = canvas.rotate(angle, resample=Image.BICUBIC,
                                   center=(36.0, 222.0))
        # 斗篷下摆局部 1~2px 摆动（只作用于左下摆，羽化遮罩）
        if cape_shift != 0:
            box = (0, 108, 30, 222)
            region = canvas.crop(box)
            w, h = region.size
            mask = Image.new("L", (w, h), 0)
            mp = mask.load()
            for yy in range(h):
                fy = min(1.0, yy / 22.0)
                for xx in range(w):
                    fx = max(0.0, 1.0 - xx / 24.0)
                    mp[xx, yy] = int(255.0 * fx * fy)
            mask = mask.filter(ImageFilter.GaussianBlur(2))
            shifted = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            shifted.alpha_composite(region, (cape_shift, 0))
            shifted.putalpha(ImageChops.multiply(
                    shifted.getchannel("A"), mask))
            canvas.alpha_composite(shifted, (box[0], box[1]))
        # 法球光晕呼吸（只叠加光，不改人物像素）
        if glow_amt > 0.01:
            glow = Image.new("RGBA", (72, 222), (0, 0, 0, 0))
            gd = ImageDraw.Draw(glow)
            cx, cy = 60.0, 54.0
            gd.ellipse((cx - 13, cy - 13, cx + 13, cy + 13),
                       fill=(150, 120, 255, int(70 * glow_amt)))
            gd.ellipse((cx - 7, cy - 7, cx + 7, cy + 7),
                       fill=(205, 235, 255, int(80 * glow_amt)))
            glow = glow.filter(ImageFilter.GaussianBlur(4))
            canvas.alpha_composite(glow)
        return canvas

    # 走路：高度（底部锚定 bob）/ 倾角 / 斗篷摆幅 / 光晕
    walk_params = [
        (222, 0.0, 0, 0.10),
        (221, 0.55, -1, 0.30),
        (220, 0.20, -2, 0.45),
        (221, 0.00, -1, 0.30),
        (222, -0.45, 0, 0.15),
        (221, -0.10, 1, 0.20),
    ]
    idle_params = [
        (222, 0.00, 0, 0.18),
        (221, 0.15, -1, 0.42),
        (222, 0.00, 0, 0.32),
        (220, -0.10, 1, 0.18),
    ]
    walk_frames = [make_frame(*p) for p in walk_params]
    idle_frames = [make_frame(*p) for p in idle_params]

    def make_sheet(frames: list[Image.Image], name: str) -> None:
        sheet = Image.new("RGBA", (72 * len(frames), 222), (0, 0, 0, 0))
        for i, frame in enumerate(frames):
            sheet.alpha_composite(frame, (72 * i, 0))
        save(sheet, ART / name)

    make_sheet(walk_frames, "player_walk.png")
    make_sheet(idle_frames, "player_idle.png")


def gen_portrait_from_cutout() -> None:
    """v1.6：角色面板立绘 = 用户原图抠图的半身裁切（不重绘）。"""
    print("[portrait] 基于 char_cutout 半身裁切")
    src = Image.open(ART / "char_cutout.png").convert("RGBA")
    # 头部到腰胯、含法球（原图 320×986 -> 取上半 0..620）
    portrait = src.crop((0, 0, 320, 620))
    save(portrait, ART / "player_portrait.png")


def gen_corridor_bg_v2() -> None:
    """v1.8：回廊远景 —— 无尽琉璃/暗石长廊、透视柱列拱券、两侧黯淡命珠。"""
    print("[corridor_bg_v2] 无尽琉璃回廊远景 1280×720")
    lw, lh = 320, 180
    arr = vertical_gradient(lw, lh, [
        (0.00, COL["void"]),
        (0.30, COL["bg_deep"]),
        (0.66, COL["bg_mid"]),
        (1.00, COL["void"]),
    ])
    arr = apply_vignette(arr, 0.52, 0.34)
    img = dither_to_palette(arr).convert("RGBA")
    d = ImageDraw.Draw(img)
    cx = 160
    vp_y = 80

    # 远端幽光（压低亮度，给中部上方旋转珠留空间）
    glow = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for radius, color, alpha in ((40, "violet_dim", 26), (26, "edge2", 30),
                                 (14, "violet_dim", 36)):
        gd.ellipse((cx - radius, vp_y - 16 - radius, cx + radius,
                    vp_y - 16 + radius), fill=rgba(COL[color], alpha))
    img.alpha_composite(glow)

    # 远端门洞（长廊尽头一点希望之光）
    d.rectangle((cx - 14, 54, cx + 14, 114), fill=COL["panel2"])
    d.arc((cx - 18, 40, cx + 18, 96), 180, 360, fill=COL["edge2"], width=2)
    d.rectangle((cx - 7, 66, cx + 7, 110), fill=COL["edge"])
    d.rectangle((cx - 4, 74, cx + 4, 108), fill=COL["panel2"])
    door_glow = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    dgd = ImageDraw.Draw(door_glow)
    for radius, color, alpha in ((30, "violet_dim", 26), (17, "edge2", 34),
                                 (8, "violet_dim", 40)):
        dgd.ellipse((cx - radius, 92 - radius, cx + radius, 92 + radius),
                    fill=rgba(COL[color], alpha))
    img.alpha_composite(door_glow)

    # 地面（透视）
    floor_y = 118
    d.rectangle((0, floor_y, lw, lh), fill=COL["bg_deep"])
    d.polygon([(cx - 22, floor_y), (cx + 22, floor_y),
               (cx + 96, lh), (cx - 96, lh)], fill=COL["panel2"])
    for x in range(-240, 561, 38):
        d.line((cx, floor_y, x, lh), fill=COL["edge"])
    for i in range(1, 8):
        t = i / 8.0
        y = int(floor_y + (lh - floor_y) * (t * t))
        d.line((0, y, lw, y), fill=COL["edge"])
    # 地面黯淡珠光
    rng = random.Random(7788)
    for _ in range(46):
        x = rng.randint(0, lw - 1)
        y = rng.randint(floor_y + 4, lh - 1)
        if abs(x - cx) < 70 and y > lh - 34:
            continue
        d.point((x, y), fill=COL[rng.choice(
                ["violet_dim", "edge2", "gold_dark", "jade_dim"])])

    # 透视拱券柱列（由远及近）
    for t in (0.16, 0.32, 0.50, 0.70, 0.92):
        half_w = int(30 + 118 * t)
        top = int(74 - 50 * t)
        bottom = int(120 + 42 * t)
        if t < 0.35:
            col = "violet_dim"
        elif t < 0.65:
            col = "edge2"
        else:
            col = "edge"
        width = max(1, int(1 + 2.4 * t))
        left = cx - half_w
        right = cx + half_w
        d.rectangle((left, top, left + width, bottom), fill=COL[col])
        d.rectangle((right - width, top, right, bottom), fill=COL[col])
        arch_h = int(24 + 34 * t)
        d.arc((left, top - arch_h, right, top + arch_h), 180, 360,
              fill=COL[col], width=width)
        # 拱券内沿暗线
        if t > 0.4:
            d.line((left + width + 1, top + 4, left + width + 1, bottom - 3),
                   fill=COL["panel2"])
            d.line((right - width - 2, top + 4, right - width - 2, bottom - 3),
                   fill=COL["panel2"])
        # 柱础
        d.rectangle((left - 2, bottom - 3, left + width + 2, bottom),
                    fill=COL["panel2"])
        d.rectangle((right - width - 2, bottom - 3, right + 2, bottom),
                    fill=COL["panel2"])

    # 天花板拱肋
    for i in range(4):
        y = int(8 + i * 13)
        d.arc((cx - 150 + i * 18, y, cx + 150 - i * 18, y + 54),
              200, 340, fill=COL["edge"], width=1)

    # 两侧柱列上镶嵌的黯淡命运珠（小珠 + 微光）
    for x in (42, 62, 88, 232, 258, 278):
        for y in range(28, 152, 17):
            if rng.random() < 0.72:
                d.point((x, y), fill=COL["violet_dim"])
                d.point((x, y + 1), fill=COL["edge2"])
                if rng.random() < 0.45:
                    d.point((x - 1, y), fill=COL["text_dim"])
                if rng.random() < 0.22:
                    d.point((x + 1, y + 1), fill=COL["gold_dim"])

    # 两侧镶嵌的黯淡命运珠（微光点，避开中央可读区）
    for _ in range(150):
        side = rng.choice([-1, 1])
        dist = rng.uniform(34, 150)
        x = int(cx + side * dist)
        y = rng.randint(14, 170)
        if abs(x - cx) < 30:
            continue
        col = rng.choice(["violet_dim", "text_dim", "gold_dark", "jade_dim",
                          "edge2"])
        if rng.random() < 0.72:
            d.point((x, y), fill=COL[col])
        else:
            d.rectangle((x, y, x + 1, y + 1), fill=COL[col])
            if rng.random() < 0.3:
                d.point((x - 1, y), fill=COL["edge2"])

    # 近景暗柱画框（左右各一，避免抢中央）
    for x0 in (0, lw - 26):
        d.rectangle((x0, 0, x0 + 25, lh), fill=COL["void"])
        d.rectangle((x0 + 20, 0, x0 + 25, lh), fill=COL["panel2"])
        for _ in range(16):
            sx = x0 + rng.randint(3, 20)
            sy = rng.randint(6, lh - 6)
            d.point((sx, sy), fill=COL[rng.choice(
                    ["violet_dim", "gold_dark", "edge2"])])

    # 暗角
    vig = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vig)
    for i in range(10):
        vd.rectangle((i * 2, i * 2, lw - 1 - i * 2, lh - 1 - i * 2),
                     outline=rgba(COL["void"], 18), width=1)
    img.alpha_composite(vig)
    save(upscale(img, (1280, 720)), ART / "corridor_bg_v2.png")


def gen_orb_glow() -> None:
    """v1.8：明亮琉璃珠 + 淡蓝/淡紫多层辉光（gameplay 旋转/脉动）。"""
    print("[orb_glow] 明亮命源珠辉光 256×256")
    size = 128
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = (size - 1) / 2.0
    r = np.hypot(xx - cx, yy - cy) / (size / 2.0)
    white = np.array(rgb("#ffffff"), dtype=np.float32)
    pale = np.array(rgb("#bfd8ff"), dtype=np.float32)
    violet = np.array(rgb("#9a7bff"), dtype=np.float32)
    deep = np.array(rgb("#5c45a8"), dtype=np.float32)
    color = np.zeros((size, size, 3), dtype=np.float32)
    stops = [0.0, 0.10, 0.26, 0.58, 0.92]
    for c in range(3):
        color[..., c] = np.interp(r, stops,
                [white[c], white[c], pale[c], violet[c], deep[c]])
    alpha = np.clip((np.clip(1.0 - r, 0.0, None) ** 1.9) * 300.0, 0, 255)
    alpha = np.maximum(alpha, np.where(r < 0.085, 255.0, 0.0))
    # 外圈淡紫光晕
    halo = np.clip((1.0 - np.abs(r - 0.46) / 0.5), 0, 1) * 34.0
    alpha = np.clip(alpha + halo, 0, 255)
    arr = np.zeros((size, size, 4), dtype=np.uint8)
    arr[..., :3] = color.astype(np.uint8)
    arr[..., 3] = alpha.astype(np.uint8)
    low = Image.fromarray(arr, "RGBA")
    save(upscale(low, (256, 256)), ART / "orb_glow.png")


def gen_guardian_silhouette() -> None:
    """v1.8：右侧偏下高大守命者剪影（上半身清晰、下半身渐隐）。"""
    print("[guardian_silhouette] 守命者高大剪影 420×720")
    lw, lh = 105, 180
    img = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 斗篷/巨大身躯
    d.polygon([(56, 12), (68, 5), (82, 11), (88, 27), (85, 40), (95, 46),
               (104, 66), (104, 180), (26, 180), (33, 122), (40, 72),
               (48, 45), (52, 27)], fill=COL["panel2"])
    # 兜帽内里/面部阴影
    d.polygon([(60, 18), (71, 13), (80, 20), (81, 34), (72, 43), (63, 36)],
              fill=COL["void"])
    # 幽光勾勒轮廓
    d.line([(52, 29), (46, 52), (38, 96), (33, 142), (30, 178)],
           fill=COL["violet_dim"])
    d.line([(56, 12), (68, 5), (82, 11)], fill=COL["edge2"])
    d.line([(85, 40), (95, 46), (104, 66), (104, 120)], fill=COL["violet_dim"])
    # 双眼微光（低对比）
    d.point((68, 28), fill=COL["violet_hi"])
    d.point((75, 28), fill=COL["violet_dim"])
    # 衣褶
    d.line([(58, 54), (54, 92), (50, 140)], fill=COL["void"])
    d.line([(82, 54), (86, 96), (90, 142)], fill=COL["void"])

    # 画面右侧偏下：整体下移，使守命者更贴近右下
    shifted = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    shifted.alpha_composite(img, (0, 22))
    img = shifted

    # 下半身渐隐
    mask = Image.new("L", (lw, lh), 255)
    mp = mask.load()
    for y in range(lh):
        if y <= 66:
            a = 255.0
        else:
            t = (y - 66) / float(lh - 66)
            a = 255.0 * max(0.0, 1.0 - t) ** 1.5
        for x in range(lw):
            mp[x, y] = int(a)
    img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    img = img.filter(ImageFilter.GaussianBlur(0.7))
    save(upscale(img, (420, 720)), ART / "guardian_silhouette.png")


def gen_bag_icon() -> None:
    """v1.8：回廊右上「行囊」像素图标 64×64。"""
    print("[bag_icon] 行囊像素图标 64×64")
    low = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(low)
    # 包身
    d.rectangle((2, 5, 13, 14), fill=COL["gold_dark"])
    d.rectangle((3, 6, 12, 13), fill=COL["gold_dim"])
    d.rectangle((3, 10, 12, 13), fill=COL["gold_dark"])
    # 包盖
    d.rectangle((2, 4, 13, 7), fill=COL["gold"])
    d.rectangle((2, 4, 13, 4), fill=COL["edge"])
    d.line((2, 6, 13, 6), fill=COL["gold_dim"])
    # 背带
    d.line((4, 4, 2, 1), fill=COL["edge2"])
    d.line((11, 4, 13, 1), fill=COL["edge2"])
    # 扣子
    d.rectangle((7, 7, 8, 9), fill=COL["edge"])
    d.point((7, 8), fill=COL["gold_hi"])
    # 侧袋 + 命珠挂饰
    d.rectangle((2, 11, 4, 13), fill=COL["gold_dark"])
    d.point((12, 14), fill=COL["violet"])
    d.point((12, 13), fill=COL["violet_hi"])
    # 轮廓
    d.rectangle((1, 4, 14, 15), outline=COL["edge"])
    save(upscale(low, (64, 64)), ART / "bag_icon.png")


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
    icon_rift_note()
    icon_recall_pouch()
    icon_spindle_nail()
    icon_pass_chisel()
    icon_fate_gift()
    icon_fate_reward()


# ---- v1.4 新道具图标 ----

def icon_rift_note() -> None:
    img, d = icon_canvas()
    # 卷轴
    d.rectangle((3, 1, 12, 14), fill=COL["text_dim"])
    d.rectangle((3, 1, 12, 2), fill=COL["text"])
    d.rectangle((3, 13, 12, 14), fill=COL["gold_dark"])
    d.line((5, 8, 8, 5), fill=COL["violet"])
    d.line((5, 8, 8, 11), fill=COL["violet"])
    d.line((5, 8, 10, 8), fill=COL["violet_hi"])
    d.point((8, 5), fill=COL["violet_pale"])
    d.point((8, 11), fill=COL["violet_pale"])
    save(upscale(img, (64, 64)), ICONS / "rift_note.png")


def icon_recall_pouch() -> None:
    img, d = icon_canvas()
    # 布袋
    d.rectangle((4, 6, 11, 14), fill=COL["gold_dark"])
    d.rectangle((4, 6, 11, 7), fill=COL["gold_dim"])
    d.line((5, 4, 10, 4), fill=COL["gold"])
    d.line((5, 4, 5, 6), fill=COL["gold"])
    d.line((10, 4, 10, 6), fill=COL["gold"])
    d.rectangle((7, 8, 9, 10), fill=COL["violet"])
    d.point((8, 9), fill=COL["violet_hi"])
    # 回收箭头
    d.line((2, 11, 2, 8), fill=COL["jade"])
    d.line((2, 8, 4, 8), fill=COL["jade"])
    save(upscale(img, (64, 64)), ICONS / "recall_pouch.png")


def icon_spindle_nail() -> None:
    img, d = icon_canvas()
    d.line((8, 1, 8, 13), fill=COL["gold"])
    d.point((8, 14), fill=COL["gold_hi"])
    d.rectangle((6, 1, 10, 2), fill=COL["gold_dim"])
    # 纺锤螺纹
    d.line((5, 5, 8, 4), fill=COL["violet"])
    d.line((8, 6, 11, 5), fill=COL["violet_dim"])
    d.line((5, 9, 8, 8), fill=COL["violet"])
    d.line((8, 10, 11, 9), fill=COL["violet_dim"])
    save(upscale(img, (64, 64)), ICONS / "spindle_nail.png")


def icon_pass_chisel() -> None:
    img, d = icon_canvas()
    # 凿子（斜向）
    d.line((3, 13, 11, 3), fill=COL["text_dim"], width=3)
    d.line((4, 12, 10, 4), fill=COL["text"], width=1)
    d.line((11, 3, 14, 1), fill=COL["gold"])
    d.line((3, 13, 1, 15), fill=COL["gold_dim"])
    d.point((14, 1), fill=COL["white"])
    # 穿透微光
    d.point((5, 7), fill=COL["jade"])
    d.point((8, 9), fill=COL["jade_hi"])
    save(upscale(img, (64, 64)), ICONS / "pass_chisel.png")


def icon_fate_gift() -> None:
    img, d = icon_canvas()
    d.rectangle((3, 6, 12, 14), fill=COL["violet_dim"])
    d.rectangle((2, 3, 13, 6), fill=COL["violet"])
    d.rectangle((7, 3, 8, 14), fill=COL["gold"])
    d.rectangle((2, 3, 13, 3), fill=COL["gold_dim"])
    d.line((5, 1, 7, 3), fill=COL["gold_hi"])
    d.line((10, 1, 8, 3), fill=COL["gold_hi"])
    d.point((7, 1), fill=COL["white"])
    save(upscale(img, (64, 64)), ICONS / "fate_gift.png")


def icon_fate_reward() -> None:
    img, d = icon_canvas()
    d.rectangle((2, 6, 13, 14), fill=COL["gold_dark"])
    d.rectangle((2, 6, 13, 8), fill=COL["gold_dim"])
    d.rectangle((4, 9, 11, 13), fill=COL["panel2"])
    # 五角星芒
    d.line((7, 9, 7, 13), fill=COL["gold_hi"])
    d.line((4, 11, 11, 11), fill=COL["gold"])
    d.point((7, 11), fill=COL["white"])
    d.point((6, 10), fill=COL["white"])
    d.rectangle((2, 14, 13, 14), fill=COL["gold"])
    save(upscale(img, (64, 64)), ICONS / "fate_reward.png")


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
    gen_player_sprites_from_cutout()
    gen_portrait_from_cutout()
    gen_app_icon()
    gen_corridor_bg_v2()
    gen_orb_glow()
    gen_guardian_silhouette()
    gen_bag_icon()
    gen_particle_dot()
    gen_hand()
    gen_icons()
    copy_fonts()
    print("=== 完成 ===")


if __name__ == "__main__":
    main()
