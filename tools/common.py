"""Shared helpers for the D-Tector build pipeline (tools/pack_*.py).

DT_SRC points at a checkout of kaisadilla/D-Tector-v2. Override with the
DTECTOR_SRC env var; defaults to the session scratchpad checkout used
throughout the wayfinder map.
"""
import os
from PIL import Image

DT_SRC = os.environ.get(
    "DTECTOR_SRC",
    "/private/tmp/claude-502/-Users-tiscomacnb2227-Workspace-garmin-d-tector/"
    "2cfbef5b-836a-439a-b7ec-c70531a6572c/scratchpad/dtector")

APP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")

# ADR 3: colours are baked into the atlas palette, not tinted at draw time.
LCD_BG = (0x81, 0x93, 0x76)   # Preferences.BackgroundColor default
INK = (0x00, 0x00, 0x00)      # Preferences.ActiveColor default
LUMA_ON = 128


def src(*parts):
    return os.path.join(DT_SRC, *parts)


def app(*parts):
    return os.path.join(APP_DIR, *parts)


def load_mask(path, box=None):
    """1-bit mask: on where alpha>0 and luma>128 (ticket 05's threshold rule).

    Covers both plain sprites (colour + alpha) and font sheets (solid white,
    shape carried in alpha) with the same rule.
    """
    im = Image.open(path).convert("RGBA")
    if box:
        im = im.crop(box)
    w, h = im.size
    mask = Image.new("1", (w, h), 0)
    mp, px = mask.load(), im.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            luma = (r * 299 + g * 587 + b * 114) // 1000
            mp[x, y] = 1 if (a > 0 and luma > LUMA_ON) else 0
    return mask


def bake(mask):
    """1-bit mask -> a 2-colour P-mode image: index 0 = LCD_BG, index 1 = INK."""
    w, h = mask.size
    out = Image.new("P", (w, h), 0)
    out.putpalette(list(LCD_BG) + list(INK) + [0, 0, 0] * 254)
    op, mp = out.load(), mask.load()
    for y in range(h):
        for x in range(w):
            op[x, y] = 1 if mp[x, y] else 0
    return out


def unbake_to_mask(baked):
    """Inverse of bake(): read palette indices directly (index 1 = ink)."""
    w, h = baked.size
    out = Image.new("1", (w, h), 0)
    op, bp = out.load(), baked.load()
    for y in range(h):
        for x in range(w):
            op[x, y] = 1 if bp[x, y] == 1 else 0
    return out
