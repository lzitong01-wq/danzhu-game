#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《！？珠珠？！》前台像素插画生成脚本（v1.5，可重复运行）。

产出（像素图均为低分辨率绘制 → NEAREST 放大 4 倍，路径稳定）：
  assets/art/splash_logo.png        启动页 studio logo（平行四边形色块 + 金色像素描边 + 像素字）
  assets/art/menu_emblem.png        小徽记（像素徽记，透明底，备用）
  assets/art/menu_bg.png            星空原图 1280×720（深靛回廊 / 星尘 / 命运符环）
  assets/art/menu_bg_blur.png       主菜单虚化星空背景 1280×720（由 menu_bg 预模糊 + 压暗 + 冷紫调）
  assets/art/menu_hero_faceless.png 主菜单右侧无脸主角剪影 560×720（参考 ref_astrologer.png）
  assets/art/hall_bg.png            教程大厅背景 1280×720（备用）

设计约束与 tools/gen_art.py 一致：
  * 限定调色板（深靛 / 命途紫 / 鎏金 / 幽玉 / 白 / 黑），无平滑渐变；
  * 渐变用 4×4 Bayer 有序抖动；线条 1px、硬色块、无抗锯齿；
  * 固定随机种子，重复运行结果一致。

用法：python tools/gen_art_front.py
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets" / "art"
FONTS = ROOT / "assets" / "fonts"

SCALE = 4
SEED = 20260410

# ------------------------------------------------------------------ 调色板
# 取值与 scripts/core/fate_config.gd 的主题色一致（去掉 '#' 方便 ImageDraw 使用）。
PAL_DEF = {
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
    "text": "f3e9d2",
    "text_dim": "b6aec9",
    "white": "ffffff",
}

PAL_HEX = {key: "#" + value for key, value in PAL_DEF.items()}
_PALETTE = list(dict.fromkeys(PAL_HEX.values()))
PAL_ARR = np.array(
    [tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) for h in _PALETTE],
    dtype=np.float32,
)

BAYER4 = np.array([
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
], dtype=np.float32) / 16.0 - 0.5

# 低对比环纹专用色（≈25% 混入底色，避免背景抢 UI）
RING_FAINT = "#201a33"
FRAME_FAINT = "#2a2140"


def rgb(hex_str: str) -> tuple[int, int, int]:
    hex_str = hex_str.lstrip("#")
    return tuple(int(hex_str[i:i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


# ------------------------------------------------------------------ 基础工具

def save(img: Image.Image, path: Path, scale: int = SCALE) -> None:
    """NEAREST 放大到目标尺寸后保存。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    big = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    big.save(path, "PNG", optimize=True)
    print(f"  -> {path.relative_to(ROOT)}  {big.width}x{big.height}  "
          f"{path.stat().st_size // 1024} KB")


def vertical_gradient(w: int, h: int, stops: list[tuple[float, str]]) -> np.ndarray:
    pos = np.array([s[0] for s in stops], dtype=np.float32)
    cols = np.array([rgb(s[1]) for s in stops], dtype=np.float32)
    ys = np.linspace(0.0, 1.0, h, dtype=np.float32)
    channels = [np.interp(ys, pos, cols[:, i]) for i in range(3)]
    return np.repeat(np.stack(channels, axis=1)[:, None, :], w, axis=1)


def quantize(arr: np.ndarray) -> Image.Image:
    """浮点 RGB 用 Bayer 抖动量化到限定调色板，返回低分辨率 RGB 图。"""
    h, w, _ = arr.shape
    tile = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w][..., None]
    work = arr + tile * 16.0
    dist = ((work[..., None, :] - PAL_ARR[None, None, :, :]) ** 2).sum(axis=-1)
    idx = dist.argmin(axis=-1)
    return Image.fromarray(PAL_ARR[idx].astype(np.uint8), "RGB")


def vignette(img: Image.Image, strength: float = 0.34) -> Image.Image:
    """四角压暗（二次径向），再做一次抖动量化，保持像素颗粒。"""
    arr = np.asarray(img, dtype=np.float32).copy()
    h, w, _ = arr.shape
    ys, xs = np.indices((h, w))
    nx = (xs - (w - 1) * 0.5) / (w * 0.5)
    ny = (ys - (h - 1) * 0.5) / (h * 0.5)
    edge = np.clip(np.sqrt(nx * nx + ny * ny) - 0.45, 0.0, 1.0) / 0.75
    arr *= (1.0 - strength * edge * edge)[..., None]
    return quantize(arr)


def star(d: ImageDraw.ImageDraw, x: int, y: int, color: str,
         size: int = 1, diagonal: bool = False) -> None:
    d.rectangle([x, y, x + size - 1, y + size - 1], fill=color)
    if diagonal:
        d.point((x - 1, y), fill=color)
        d.point((x + size, y), fill=color)
        d.point((x, y - 1), fill=color)
        d.point((x, y + size), fill=color)


def dashed_line(d: ImageDraw.ImageDraw, p0: tuple[float, float],
                p1: tuple[float, float], color: str, dash: int = 3,
                gap: int = 3, width: int = 1) -> None:
    x0, y0 = p0
    x1, y1 = p1
    length = math.hypot(x1 - x0, y1 - y0)
    if length <= 0.0:
        return
    steps = int(length // (dash + gap)) + 1
    for i in range(steps):
        t0 = (i * (dash + gap)) / length
        t1 = min(1.0, (i * (dash + gap) + dash) / length)
        if t0 >= 1.0:
            break
        d.line([x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0,
                x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1],
               fill=color, width=width)


# ------------------------------------------------------------------ 徽记

def draw_insignia(d: ImageDraw.ImageDraw, ox: int, oy: int, w: int,
                  ghost: bool = False) -> None:
    """平行四边形徽记：金色描边 + 命途紫内芯 + 鎏金菱形。"""
    # 后方两层错位"幽灵"平行四边形，做出层叠色块（平台发行 logo 常见排版）
    d.polygon([(ox + 12, oy + 12), (ox + 42, oy + 12),
               (ox + 34, oy + 44), (ox + 4, oy + 44)],
              outline=PAL_HEX["gold_dark"], width=1)
    d.polygon([(ox + 7, oy + 8), (ox + 46, oy + 8),
               (ox + 38, oy + 46), (ox - 1, oy + 46)],
              outline=PAL_HEX["gold_dark"], width=1)
    front = [(ox + 2, oy + 4), (ox + 50, oy + 4),
             (ox + 42, oy + 48), (ox - 6, oy + 48)]
    d.polygon(front, fill=PAL_HEX["violet_dim"])
    d.polygon(front, outline=PAL_HEX["gold"], width=1)
    # 顶部 1px 高光
    d.line([(ox + 3, oy + 5), (ox + 49, oy + 5)], fill=PAL_HEX["gold_hi"])
    # 内芯：更大一块深靛，再叠鎏金菱形与星点
    d.polygon([(ox + 8, oy + 10), (ox + 45, oy + 10),
               (ox + 38, oy + 42), (ox + 1, oy + 42)],
              fill=PAL_HEX["bg_mid2"])
    d.polygon([(ox + 22, oy + 14), (ox + 33, oy + 26),
               (ox + 22, oy + 38), (ox + 11, oy + 26)],
              outline=PAL_HEX["gold"], width=1)
    d.point((ox + 22, oy + 26), fill=PAL_HEX["gold_hi"])
    d.point((ox + 21, oy + 25), fill=PAL_HEX["gold_hi"])
    if not ghost:
        # 四角小方块，强化"像素描边"
        for cx, cy in [(ox + 2, oy + 4), (ox + 50, oy + 4),
                       (ox + 42, oy + 48), (ox - 6, oy + 48)]:
            d.rectangle([cx - 1, cy - 1, cx + 1, cy + 1], fill=PAL_HEX["gold_hi"])


def build_splash_logo() -> None:
    """启动页 studio logo：徽记 + 「琉璃回廊工作室」像素字（透明底）。"""
    w, h = 200, 56
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    draw_insignia(d, 2, 2, 52)

    title_font = ImageFont.truetype(str(FONTS / "FateTitle.ttf"), 19)
    text = "琉璃回廊工作室"
    tx, ty = 66, h // 2
    # 先画 2px 硬阴影（深靛），再画鎏金描边字 —— 无模糊，纯像素描边感
    d.text((tx + 2, ty + 2), text, font=title_font, fill=PAL_HEX["void"],
           anchor="lm", stroke_width=1, stroke_fill=PAL_HEX["void"])
    d.text((tx, ty), text, font=title_font, fill=PAL_HEX["gold"],
           anchor="lm", stroke_width=1, stroke_fill=PAL_HEX["gold_dark"])
    # 字上方 1px 高光（像素字顶部反光）
    d.line([(tx, ty - 10), (tx + 108, ty - 10)], fill=PAL_HEX["gold_dark"])
    d.line([(tx, ty + 11), (tx + 122, ty + 11)], fill=PAL_HEX["gold_dark"])
    save(img, ART / "splash_logo.png")


def build_menu_emblem() -> None:
    """主菜单左上角小徽记（透明底）。"""
    img = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_insignia(d, 0, 0, 40)
    # 裁掉超出 40 的部分（draw_insignia 允许少量出血）
    save(img, ART / "menu_emblem.png")


# ------------------------------------------------------------------ 背景

def build_menu_bg() -> None:
    """主菜单背景：深靛回廊透视 + 命运符环 + 星尘 / 金屑。"""
    w, h = 320, 180
    arr = vertical_gradient(w, h, [
        (0.00, PAL_HEX["void"]),
        (0.22, PAL_HEX["bg_deep"]),
        (0.50, PAL_HEX["bg_mid2"]),
        (0.74, PAL_HEX["bg_low"]),
        (0.90, PAL_HEX["bg_mid"]),
        (1.00, PAL_HEX["bg_deep"]),
    ])
    img = quantize(arr)
    d = ImageDraw.Draw(img)

    # ---- 透视回廊：一圈圈向消失点收缩的方框 ----
    vx, vy = 214.0, 96.0
    for i in range(1, 8):
        half_w = 8.0 * i * i * 0.55
        half_h = 5.0 * i * i * 0.55
        alpha_col = PAL_HEX["edge"] if i < 4 else RING_FAINT
        d.rectangle([vx - half_w, vy - half_h, vx + half_w, vy + half_h],
                    outline=alpha_col)
    # 地面透视斜线（消失点 → 底部两角）
    for x in (0, 40, 96, 320, 280, 224):
        d.line([(vx, vy + 6), (x, h)], fill=RING_FAINT)
    d.line([(0, 156), (320, 156)], fill=FRAME_FAINT)

    # ---- 命运符环 ----
    cx, cy, r = 214, 96, 46
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=RING_FAINT)
    d.ellipse([cx - r + 2, cy - r + 2, cx + r - 2, cy + r - 2],
              outline=FRAME_FAINT)
    d.ellipse([cx - 24, cy - 24, cx + 24, cy + 24], outline=RING_FAINT)
    for i in range(12):
        ang = math.radians(i * 30.0)
        x0 = cx + math.cos(ang) * (r - 5)
        y0 = cy + math.sin(ang) * (r - 5)
        x1 = cx + math.cos(ang) * r
        y1 = cy + math.sin(ang) * r
        d.line([x0, y0, x1, y1], fill=RING_FAINT)
    # 符环中心的鎏金菱形（低亮度）
    d.polygon([(cx, cy - 15), (cx + 12, cy), (cx, cy + 15), (cx - 12, cy)],
              outline=PAL_HEX["gold_dark"])
    star(d, cx, cy, PAL_HEX["gold_dim"], size=1)

    # ---- 远景门洞剪影（左右两侧，营造纵深）----
    for door_x in (36, 170, 286):
        d.rectangle([door_x - 12, 96, door_x + 12, 158],
                    fill=PAL_HEX["bg_mid"])
        d.rectangle([door_x - 12, 96, door_x + 12, 158],
                    outline=RING_FAINT)
        d.line([(door_x - 12, 96), (door_x, 96 - 9)], fill=RING_FAINT)
        d.line([(door_x + 12, 96), (door_x, 96 - 9)], fill=RING_FAINT)
        d.rectangle([door_x - 3, 120, door_x + 3, 158],
                    fill=PAL_HEX["bg_low"])
    # 地面尽头的一点暖光（回廊深处的命运之光）
    for i in range(6):
        d.line([(120 + i, 155), (200 - i, 155)], fill=PAL_HEX["gold_dark"])

    # ---- 星尘 ----
    rng = random.Random(SEED)
    star_cols = [PAL_HEX["violet_pale"], PAL_HEX["text_dim"],
                 PAL_HEX["gold_pale"], PAL_HEX["white"], PAL_HEX["violet"]]
    for _ in range(120):
        x = rng.randrange(2, w - 2)
        y = rng.randrange(2, h - 12)
        c = rng.choice(star_cols)
        size = 2 if rng.random() < 0.10 else 1
        star(d, x, y, c, size=size, diagonal=size == 1 and rng.random() < 0.25)
    # 金屑（偏下侧，像回廊浮尘）
    for _ in range(40):
        x = rng.randrange(2, w - 2)
        y = rng.randrange(60, h - 2)
        star(d, x, y, PAL_HEX["gold_dim"] if rng.random() < 0.7
             else PAL_HEX["gold"], size=1)

    # ---- 四角鎏金角饰 ----
    for ox, oy, sx, sy in [(4, 4, 1, 1), (w - 5, 4, -1, 1),
                           (4, h - 5, 1, -1), (w - 5, h - 5, -1, -1)]:
        d.line([(ox, oy), (ox + 12 * sx, oy)], fill=PAL_HEX["gold_dark"])
        d.line([(ox, oy), (ox, oy + 8 * sy)], fill=PAL_HEX["gold_dark"])
        d.point((ox, oy), fill=PAL_HEX["gold_dim"])

    save(vignette(img, 0.30), ART / "menu_bg.png")


def build_menu_bg_blur() -> None:
    """主菜单虚化星空背景 1280×720：基于 menu_bg 星空预模糊 + 压暗 + 冷紫调。"""
    src = ART / "menu_bg.png"
    if not src.exists():
        build_menu_bg()
    img = Image.open(src).convert("RGB")
    # 直接在 1280 上做小半径模糊：保留星点的柔光晕，而不是糊成一片
    blur = img.filter(ImageFilter.GaussianBlur(radius=2.4))

    arr = np.asarray(blur, np.float32).copy()
    hh, ww, _ = arr.shape
    ys, xs = np.indices((hh, ww)).astype(np.float32)

    # 压暗 + 冷紫调（保留星点亮度）
    arr *= 0.74
    arr[..., 0] *= 0.95
    arr[..., 1] *= 0.90
    arr[..., 2] *= 1.06

    # 右侧主角身后的柔光（帮助无脸剪影融入星空）
    gx, gy, gr = 0.72 * ww, 0.52 * hh, 0.44 * ww
    d = np.sqrt(((xs - gx) / gr) ** 2 + ((ys - gy) / (gr * 0.72)) ** 2)
    glow = np.clip(1.0 - d, 0.0, 1.0) ** 2
    arr += glow[..., None] * np.array([26.0, 16.0, 46.0], np.float32)

    # 左上更暗，让标题/按钮区更安静
    left_dark = np.clip(1.0 - xs / (ww * 0.62), 0.0, 1.0) ** 1.4
    arr *= (1.0 - 0.20 * left_dark[..., None])

    # 四角柔和压暗
    edge = np.clip(np.sqrt(((xs - ww * 0.5) / (ww * 0.62)) ** 2
                           + ((ys - hh * 0.5) / (hh * 0.66)) ** 2) - 0.55, 0.0, 1.0)
    arr *= (1.0 - 0.42 * edge * edge)[..., None]

    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    save(out, ART / "menu_bg_blur.png", scale=1)


def _load_ref_figure() -> Image.Image | None:
    """从 ref_astrologer.png 提取角色剪影（原图是白/灰棋盘格背景，非透明 alpha）。

    做法：棋盘格 = 亮且低饱和；用 RGB 图像从四角 flood fill 去掉「与边缘连通」的背景，
    再按行/列像素密度裁掉散落噪点，得到角色外接框。
    """
    ref_path = ART / "ref_astrologer.png"
    if not ref_path.exists():
        return None
    ref = Image.open(ref_path).convert("RGBA")
    arr = np.asarray(ref)
    rgb = arr[..., :3].astype(np.int16)
    mx = rgb.max(axis=-1)
    mn = rgb.min(axis=-1)
    loose_bg = (mx - mn <= 12) & (mn >= 185)
    mask = np.where(loose_bg, 255, 0).astype(np.uint8)
    mask_rgb = Image.fromarray(np.stack([mask, mask, mask], axis=-1), "RGB")
    w, h = mask_rgb.size
    for corner in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if mask_rgb.getpixel(corner)[0] == 255:
            ImageDraw.floodfill(mask_rgb, corner, (128, 0, 0))
    filled = np.asarray(mask_rgb)
    outside = (filled[..., 0] == 128) & (filled[..., 1] == 0)
    figure_mask = ~outside
    if int(figure_mask.sum()) < 1000:
        print("[gen_art_front] 角色背景提取失败，回退 alpha 模式")
        figure_mask = arr[..., 3] > 16
    else:
        # 按行/列密度裁掉棋盘格残留噪点
        cols = np.where(figure_mask.sum(axis=0) > 8)[0]
        rows = np.where(figure_mask.sum(axis=1) > 8)[0]
        if len(cols) > 0 and len(rows) > 0:
            clean = np.zeros_like(figure_mask)
            clean[rows.min():rows.max() + 1, cols.min():cols.max() + 1] = True
            figure_mask = figure_mask & clean
    ys, xs = np.where(figure_mask)
    if len(xs) == 0:
        return None
    out = np.zeros_like(arr)
    out[..., :3] = arr[..., :3]
    out[..., 3] = np.where(figure_mask, 255, 0).astype(np.uint8)
    fig = Image.fromarray(out, "RGBA")
    return fig.crop((int(xs.min()), int(ys.min()),
                     int(xs.max()) + 1, int(ys.max()) + 1))


def build_menu_hero_faceless() -> None:
    """主菜单右侧无脸主角剪影 560×720（低分辨率剪影 → NEAREST ×4）。

    参考 assets/art/ref_astrologer.png：取角色剪影，压成深靛紫剪影（头部压平 → 无面部），
    保留命核琉璃球的紫辉与斗篷上的琉璃饰边，加 1px 轮廓冷光与星尘。
    """
    fig = _load_ref_figure()
    if fig is None:
        print("[gen_art_front] 缺少 ref_astrologer.png 或无法提取角色剪影，跳过无脸主角")
        return

    target_h = 166
    target_w = max(1, round(fig.width * target_h / fig.height))
    if target_w > 134:
        target_w = 134
        target_h = max(1, round(fig.height * target_w / fig.width))
    fig = fig.resize((target_w, target_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (140, 180), (0, 0, 0, 0))
    ox = (140 - target_w) // 2
    oy = 180 - target_h - 6
    canvas.alpha_composite(fig, (ox, oy))

    arr = np.asarray(canvas).astype(np.float32)
    alpha = arr[..., 3].copy()
    opaque = alpha > 12
    hh, ww = alpha.shape
    gy, gx = np.indices((hh, ww)).astype(np.float32)
    lum = (0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]) / 255.0
    lum = np.clip(lum, 0.0, 1.0)

    # ---- 1) 剪影底色：深靛紫 + 极弱亮度响应 ----
    base = np.zeros((hh, ww, 3), np.float32)
    base[..., 0] = 20.0
    base[..., 1] = 14.0
    base[..., 2] = 36.0
    base += np.array([30.0, 22.0, 52.0], np.float32) * (lum ** 1.6)[..., None]
    base += (gy / float(hh))[..., None] * np.array([16.0, 10.0, 26.0], np.float32)

    # ---- 2) 头部压平 → 无面部（平滑过渡，不留硬横线）----
    head_top = float(oy)
    head_bottom = float(oy) + float(target_h) * 0.30
    head_f = np.clip((head_bottom - gy) / max(1.0, head_bottom - head_top), 0.0, 1.0)
    head_f = head_f ** 0.8
    flat = np.array([12.0, 9.0, 22.0], np.float32)
    base = base * (1.0 - 0.82 * head_f)[..., None] + flat * (0.82 * head_f)[..., None]

    # ---- 3) 命核琉璃球 / 斗篷琉璃饰边：保留蓝紫辉光 ----
    blue = arr[..., 2]
    red = arr[..., 0]
    crystal = opaque & (blue > 100.0) & (blue > red + 22.0)
    inten = np.clip((blue - 90.0) / 130.0, 0.0, 1.0)
    glow = np.zeros((hh, ww, 3), np.float32)
    glow[..., 0] = 92.0 + 150.0 * inten
    glow[..., 1] = 64.0 + 118.0 * inten
    glow[..., 2] = 168.0 + 80.0 * inten
    base = np.where(crystal[..., None], glow, base)

    # ---- 4) 柔光包边（模糊 alpha 得到贴边光晕，避免 1px 描边出现「虚线轮廓」）----
    mask_img = Image.fromarray(np.clip(alpha, 0, 255).astype(np.uint8), "L")
    blur_np = np.asarray(mask_img.filter(ImageFilter.GaussianBlur(radius=1.8)),
                         np.float32) / 255.0
    a_norm = np.clip(alpha, 0.0, 255.0) / 255.0
    halo = np.clip(blur_np - a_norm, 0.0, 1.0) * (1.0 - a_norm)
    base += halo[..., None] * np.array([58.0, 38.0, 108.0], np.float32)
    alpha = np.clip(alpha + halo * 150.0, 0.0, 255.0)

    # ---- 5) 命核球柔光（透明区域外发光，并抬升 alpha）----
    orb_x, orb_y = -1.0, -1.0
    if crystal.any():
        orb_y = float(gy[crystal].mean())
        orb_x = float(gx[crystal].mean())
        dist = np.sqrt((gx - orb_x) ** 2 + (gy - orb_y) ** 2)
        halo = np.clip(1.0 - dist / 22.0, 0.0, 1.0) ** 2
        halo *= (1.0 - opaque.astype(np.float32))
        base += halo[..., None] * np.array([52.0, 32.0, 112.0], np.float32)
        alpha = np.clip(alpha + halo * 120.0, 0.0, 255.0)

    out = np.zeros((hh, ww, 4), np.uint8)
    out[..., :3] = np.clip(base, 0.0, 255.0).astype(np.uint8)
    out[..., 3] = alpha.astype(np.uint8)
    figure = Image.fromarray(out, "RGBA")

    # ---- 6) 合成：地面阴影 → 剪影（不再画大块气晕，直接融进虚化星空）----
    img = Image.new("RGBA", (140, 180), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([ox + 16, 170, ox + target_w - 16, 179], fill=(4, 3, 9, 110))
    img.alpha_composite(figure)

    # ---- 7) 星尘 + 命核球星芒 ----
    d = ImageDraw.Draw(img)
    rng = random.Random(SEED + 31)
    for _ in range(20):
        x = rng.randrange(6, 134)
        y = rng.randrange(18, 172)
        col = rng.choice([PAL_HEX["violet_pale"], PAL_HEX["gold_pale"],
                          PAL_HEX["violet"], PAL_HEX["text_dim"]])
        size = 1 if rng.random() < 0.25 else 0
        d.rectangle([x, y, x + size, y + size], fill=col)
    if orb_x > 0.0:
        scx, scy = int(orb_x), int(orb_y)
        d.rectangle([scx, scy - 4, scx, scy + 4], fill=PAL_HEX["violet_pale"])
        d.rectangle([scx - 4, scy, scx + 4, scy], fill=PAL_HEX["violet_pale"])
        d.point((scx, scy), fill=PAL_HEX["white"])

    save(img, ART / "menu_hero_faceless.png")


def build_hall_bg() -> None:
    """新手教程大厅背景：深靛蓝图网格 + 大几何符阵 + 鎏金角饰。"""
    w, h = 320, 180
    arr = vertical_gradient(w, h, [
        (0.00, PAL_HEX["bg_deep"]),
        (0.30, PAL_HEX["bg_mid"]),
        (0.62, PAL_HEX["bg_mid2"]),
        (0.86, PAL_HEX["bg_low"]),
        (1.00, PAL_HEX["bg_deep"]),
    ])
    img = quantize(arr)
    d = ImageDraw.Draw(img)

    # ---- 蓝图网格（细线，低对比）----
    for x in range(0, w, 16):
        d.line([(x, 0), (x, h)], fill=RING_FAINT)
    for y in range(0, h, 16):
        d.line([(0, y), (w, y)], fill=RING_FAINT)
    for x in range(0, w, 64):
        d.line([(x, 0), (x, h)], fill=FRAME_FAINT)
    for y in range(0, h, 64):
        d.line([(0, y), (w, y)], fill=FRAME_FAINT)

    # ---- 中央大符阵：平行四边形 + 同心方框 + 斜向排线 ----
    cx, cy = 160, 92
    quad = [(cx - 78, cy - 42), (cx + 62, cy - 42),
            (cx + 78, cy + 42), (cx - 62, cy + 42)]
    d.polygon(quad, outline=PAL_HEX["gold_dark"])
    d.polygon([(cx - 66, cy - 34), (cx + 50, cy - 34),
               (cx + 66, cy + 34), (cx - 50, cy + 34)],
              outline=FRAME_FAINT)
    d.rectangle([cx - 34, cy - 26, cx + 34, cy + 26],
                outline=RING_FAINT)
    for i in range(-3, 4):
        d.line([(cx - 34, cy + i * 8), (cx + 34, cy + i * 8)],
               fill=RING_FAINT)
    # 四角小菱形
    for dx, dy in [(-78, -42), (62, -42), (78, 42), (-62, 42)]:
        d.polygon([(cx + dx, cy + dy - 3), (cx + dx + 3, cy + dy),
                   (cx + dx, cy + dy + 3), (cx + dx - 3, cy + dy)],
                  fill=PAL_HEX["gold_dark"])

    # ---- 立柱阵的暗示：底排小点（像 P1 台面）----
    rng = random.Random(SEED + 7)
    for row in range(5):
        for col in range(11):
            x = 46 + col * 22 + (11 if row % 2 else 0)
            y = 116 + row * 11
            c = PAL_HEX["gold_dark"] if rng.random() < 0.25 else FRAME_FAINT
            d.rectangle([x, y, x + 1, y + 1], fill=c)

    # ---- 星尘与金屑 ----
    for _ in range(70):
        x = rng.randrange(2, w - 2)
        y = rng.randrange(2, h - 2)
        star(d, x, y, rng.choice([PAL_HEX["violet_pale"], PAL_HEX["text_dim"],
                                  PAL_HEX["gold_pale"]]),
             diagonal=rng.random() < 0.2)

    # ---- 顶部/底部鎏金横线 + 角饰 ----
    d.line([(8, 8), (w - 8, 8)], fill=PAL_HEX["gold_dark"])
    d.line([(8, h - 9), (w - 8, h - 9)], fill=PAL_HEX["gold_dark"])
    for ox, oy, sx, sy in [(6, 6, 1, 1), (w - 7, 6, -1, 1),
                           (6, h - 7, 1, -1), (w - 7, h - 7, -1, -1)]:
        d.line([(ox, oy), (ox + 16 * sx, oy)], fill=PAL_HEX["gold_dim"])
        d.line([(ox, oy), (ox, oy + 10 * sy)], fill=PAL_HEX["gold_dim"])
        d.rectangle([ox - 1, oy - 1, ox + 1, oy + 1], fill=PAL_HEX["gold_hi"])

    save(vignette(img, 0.26), ART / "hall_bg.png")


def main() -> None:
    print("[gen_art_front] 《！？珠珠？！》前台像素插画 v1.5")
    print("[gen_art_front] splash / menu")
    build_splash_logo()
    build_menu_emblem()
    build_menu_bg()
    build_menu_bg_blur()
    build_menu_hero_faceless()
    print("[gen_art_front] hall（教程大厅备用）")
    build_hall_bg()
    print("[gen_art_front] done")


if __name__ == "__main__":
    main()
