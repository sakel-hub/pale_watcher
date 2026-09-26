import os
import zlib
import struct
import math
import random

TEXTURES_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "textures"))
os.makedirs(TEXTURES_DIR, exist_ok=True)

def write_png(filename, width, height, rgba_data):
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    raw_lines = bytearray()
    for y in range(height):
        raw_lines.append(0)
        raw_lines.extend(rgba_data[y * width * 4 : (y + 1) * width * 4])
    idat = chunk(b'IDAT', zlib.compress(bytes(raw_lines)))
    iend = chunk(b'IEND', b'')
    with open(filename, 'wb') as f:
        f.write(header + ihdr + idat + iend)
    print(f"Generated {filename}")

def set_pixel(buf, width, x, y, r, g, b, a):
    if 0 <= x < width and 0 <= y < (len(buf) // (width * 4)):
        idx = (y * width + x) * 4
        buf[idx] = max(0, min(255, int(r)))
        buf[idx + 1] = max(0, min(255, int(g)))
        buf[idx + 2] = max(0, min(255, int(b)))
        buf[idx + 3] = max(0, min(255, int(a)))

def generate_vignette():
    # 256x256 smooth dark radial vignette
    w, h = 256, 256
    buf = bytearray(w * h * 4)
    cx, cy = w / 2.0, h / 2.0
    max_dist = math.sqrt(cx * cx + cy * cy)

    for y in range(h):
        for x in range(w):
            dx = (x - cx) / cx
            dy = (y - cy) / cy
            dist = math.sqrt(dx * dx + dy * dy)
            # Inner circle clear (up to dist 0.45), outer edges smoothly fade to pitch black
            if dist <= 0.4:
                alpha = 0
            else:
                factor = (dist - 0.4) / 0.85
                factor = max(0.0, min(1.0, factor))
                # Smooth cosine curve
                smooth = (1.0 - math.cos(factor * math.pi)) / 2.0
                alpha = int(smooth * 255)
            set_pixel(buf, w, x, y, 0, 0, 0, alpha)

    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_hud_vignette.png"), w, h, buf)

def generate_hud_flash():
    # 32x32 radial white flash
    w, h = 32, 32
    buf = bytearray(w * h * 4)
    cx, cy = 15.5, 15.5
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy) / 16.0
            if d >= 1.0:
                alpha = 0
            else:
                alpha = int((1.0 - d ** 1.5) * 255)
            set_pixel(buf, w, x, y, 255, 255, 255, alpha)
    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_hud_flash.png"), w, h, buf)

def generate_flash_camera():
    # 16x16 Vintage Flash Camera
    w, h = 16, 16
    buf = bytearray(w * h * 4)

    # Palette
    C_OUTLINE = (18, 18, 20, 255)
    C_BODY_DARK = (45, 45, 50, 255)
    C_BODY_MID = (70, 70, 78, 255)
    C_CHROME = (180, 185, 195, 255)
    C_CHROME_HI = (240, 245, 255, 255)
    C_LENS_DARK = (15, 25, 40, 255)
    C_LENS_BLUE = (40, 90, 160, 255)
    C_LENS_SPEC = (180, 220, 255, 255)
    C_BULB_OFF = (220, 230, 240, 220)
    C_BULB_FIL = (255, 200, 100, 255)

    # Camera body (x=2..13, y=5..13)
    for y in range(6, 14):
        for x in range(2, 14):
            set_pixel(buf, w, x, y, *C_BODY_DARK)

    # Chrome top plate (y=5)
    for x in range(2, 14):
        set_pixel(buf, w, x, 5, *C_CHROME)
    set_pixel(buf, w, 3, 5, *C_CHROME_HI)
    set_pixel(buf, w, 4, 5, *C_CHROME_HI)

    # Viewfinder & shutter button (y=3..4)
    set_pixel(buf, w, 4, 4, *C_CHROME) # Shutter button
    set_pixel(buf, w, 4, 3, *C_CHROME_HI)
    set_pixel(buf, w, 6, 4, *C_BODY_DARK) # Viewfinder
    set_pixel(buf, w, 7, 4, *C_LENS_BLUE)

    # Flash reflector fan / dish on right side (x=10..13, y=1..5)
    for y in range(1, 5):
        for x in range(10, 14):
            set_pixel(buf, w, x, y, *C_CHROME)
    set_pixel(buf, w, 11, 2, *C_BULB_OFF)
    set_pixel(buf, w, 12, 2, *C_BULB_FIL)
    set_pixel(buf, w, 11, 3, *C_BULB_OFF)

    # Central lens barrel (circle at x=6..9, y=7..11)
    for y in range(7, 12):
        for x in range(5, 11):
            set_pixel(buf, w, x, y, *C_CHROME)
    for y in range(8, 11):
        for x in range(6, 10):
            set_pixel(buf, w, x, y, *C_LENS_DARK)
    set_pixel(buf, w, 7, 9, *C_LENS_BLUE)
    set_pixel(buf, w, 8, 9, *C_LENS_SPEC)

    # Outline accents
    for x in range(2, 14):
        set_pixel(buf, w, x, 14, *C_OUTLINE)
    for y in range(5, 14):
        set_pixel(buf, w, 1, y, *C_OUTLINE)
        set_pixel(buf, w, 14, y, *C_OUTLINE)

    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_flash_camera.png"), w, h, buf)

def generate_dimensional_cloth():
    # 16x16 Torn Dimensional Cloth (Suit & Red Tie Scrap with Void Glow)
    w, h = 16, 16
    buf = bytearray(w * h * 4)

    # Dark charcoal suit fabric
    suit_pattern = [
        "....111111......",
        "...12222221.....",
        "..1233RR3321....",
        "..123RRRR321....",
        ".1233RRRR3321...",
        ".12333RR33321...",
        ".12233RR33221...",
        "..1233RR3321....",
        "..1233333321....",
        "...12333321.....",
        "...12333321.....",
        "....123321......",
        "....12321.......",
        ".....121........",
        ".....11.........",
        "................",
    ]

    colormap = {
        '.': (0, 0, 0, 0),
        '1': (10, 10, 14, 255),    # Void edge
        '2': (25, 25, 30, 255),    # Suit dark
        '3': (45, 45, 52, 255),    # Suit grey
        'R': (160, 20, 25, 255),   # Crimson tie thread
    }

    for y in range(16):
        for x in range(16):
            char = suit_pattern[y][x]
            set_pixel(buf, w, x, y, *colormap[char])

    # Ethereal quantum specks
    set_pixel(buf, w, 8, 4, 240, 70, 70, 255)
    set_pixel(buf, w, 5, 5, 140, 120, 255, 220)
    set_pixel(buf, w, 10, 6, 180, 150, 255, 220)
    set_pixel(buf, w, 7, 9, 200, 40, 50, 255)

    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_dimensional_cloth.png"), w, h, buf)

def generate_shroud_of_stalking():
    # 16x16 Shroud of Stalking (Void-woven cowl with glowing eye slit)
    w, h = 16, 16
    buf = bytearray(w * h * 4)

    shroud_pattern = [
        ".....111111.....",
        "...1122222211...",
        "..122333333221..",
        ".12334444443321.",
        ".12344000044321.",
        "1234000000004321",
        "12340VV00VV04321",
        "1234000000004321",
        "1233440000443321",
        ".12334444443321.",
        ".12233333333221.",
        "..122333333221..",
        "..112233332211..",
        "...1122222211...",
        "....11222211....",
        ".....111111.....",
    ]

    colormap = {
        '.': (0, 0, 0, 0),
        '1': (12, 10, 20, 255),
        '2': (24, 20, 36, 255),
        '3': (42, 35, 60, 255),
        '4': (60, 50, 85, 255),
        '0': (10, 8, 16, 255),
        'V': (180, 220, 255, 255), # Shimmering void eyes
    }

    for y in range(16):
        for x in range(16):
            c = shroud_pattern[y][x]
            set_pixel(buf, w, x, y, *colormap[c])

    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_shroud_of_stalking.png"), w, h, buf)

def generate_cursed_page_item():
    # 16x16 Cursed Page inventory item
    w, h = 16, 16
    buf = bytearray(w * h * 4)

    page_pattern = [
        "....1111111.....",
        "...122222221....",
        "..12333333321...",
        "..123X333X321...",
        "..1233X3X3321...",
        "..12333X33321...",
        "..1233X3X3321...",
        "..123X333X321...",
        "..12333333321...",
        "..123BBBBB321...",
        "..12333333321...",
        "..123BBBBB321...",
        "..12233333221...",
        "...122222221....",
        "....1111111.....",
        "................",
    ]

    colormap = {
        '.': (0, 0, 0, 0),
        '1': (80, 70, 50, 255),   # Aged burnt rim
        '2': (185, 175, 145, 255),# Aged parchment border
        '3': (225, 215, 185, 255),# Parchment paper
        'X': (40, 15, 15, 255),   # Cryptic ink symbol (X mark of the Watcher)
        'B': (70, 45, 35, 255),   # Scribbled handwritten notes
    }

    for y in range(16):
        for x in range(16):
            c = page_pattern[y][x]
            set_pixel(buf, w, x, y, *colormap[c])

    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_cursed_page_item.png"), w, h, buf)

def generate_ritual_pyre_textures():
    # 1. Pyre top: stone altar with charcoal logs
    w, h = 16, 16
    top_buf = bytearray(w * h * 4)
    for y in range(16):
        for x in range(16):
            # Base stone altar border
            if x in (0, 15) or y in (0, 15):
                val = 60 + random.randint(-8, 8)
                set_pixel(top_buf, w, x, y, val, val, val + 5, 255)
            elif (x == y or x == 15 - y) and (2 <= x <= 13):
                # Crossed burnt oak logs
                set_pixel(top_buf, w, x, y, 40, 25, 18, 255)
            else:
                # Charcoal / ember pit
                r = 25 + random.randint(0, 15)
                g = 15 + random.randint(0, 8)
                b = 15
                set_pixel(top_buf, w, x, y, r, g, b, 255)
    # Glowing ember center
    set_pixel(top_buf, w, 7, 7, 220, 80, 20, 255)
    set_pixel(top_buf, w, 8, 7, 240, 120, 30, 255)
    set_pixel(top_buf, w, 7, 8, 200, 60, 15, 255)
    set_pixel(top_buf, w, 8, 8, 255, 140, 40, 255)
    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_ritual_pyre_top.png"), w, h, top_buf)

    # 2. Pyre side: dark carved stone hearth with wooden struts
    side_buf = bytearray(w * h * 4)
    for y in range(16):
        for x in range(16):
            if y < 4:
                # Wood log rim
                val = 45 + ((x * 7 + y * 3) % 15)
                set_pixel(side_buf, w, x, y, val, val - 12, val - 20, 255)
            elif x in (0, 1, 14, 15):
                # Stone pillars
                val = 70 + ((x + y * 5) % 12)
                set_pixel(side_buf, w, x, y, val, val, val + 4, 255)
            else:
                # Carved glyph panel
                val = 50 + ((x * 3 + y * 7) % 10)
                # Carved occult rune in center
                if (x == 7 or x == 8) and (6 <= y <= 13):
                    set_pixel(side_buf, w, x, y, 160, 40, 40, 255) # Crimson glowing rune
                elif (y == 8 or y == 11) and (5 <= x <= 10):
                    set_pixel(side_buf, w, x, y, 160, 40, 40, 255)
                else:
                    set_pixel(side_buf, w, x, y, val, val, val + 5, 255)
    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_ritual_pyre_side.png"), w, h, side_buf)

    # 3. Animated Pyre Flame: 16 wide by 128 high (8 vertical frames of 16x16)
    flame_h = 128
    flame_buf = bytearray(w * flame_h * 4)

    for frame in range(8):
        y_offset = frame * 16
        t = frame / 8.0 * math.pi * 2.0
        for y in range(16):
            for x in range(16):
                # Flame shape centered at x=8, tapering upward towards y=0
                dx = abs(x - 7.5)
                flame_width = (y / 15.0) * 6.0 + 1.0
                sway = math.sin(t + y * 0.4) * 1.5

                if dx <= flame_width + sway:
                    # Fire gradient: yellow/white center, orange mid, violet/dark edges
                    heat = 1.0 - (y / 15.0) * 0.4 - (dx / (flame_width + 0.1)) * 0.6
                    heat = max(0.0, min(1.0, heat))
                    if heat > 0.7:
                        r, g, b = 255, 240, 180
                    elif heat > 0.4:
                        r, g, b = 240, 130, 20
                    elif heat > 0.15:
                        r, g, b = 180, 40, 80 # Eldritch purple-crimson
                    else:
                        r, g, b = 60, 20, 70
                    alpha = int(heat * 240 + 15)
                else:
                    r, g, b, alpha = 0, 0, 0, 0
                set_pixel(flame_buf, w, x, y_offset + y, r, g, b, alpha)

    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_ritual_pyre_flame.png"), w, flame_h, flame_buf)

def generate_pages_hud_bg():
    # 288x32 Gothic Plaque HUD Overlay Background
    w, h = 288, 32
    buf = bytearray(w * h * 4)

    # 1. Base translucent dark obsidian fill
    for y in range(h):
        for x in range(w):
            lum = int(14 - (y / float(h)) * 6)
            set_pixel(buf, w, x, y, lum, lum + 1, lum + 6, 230)

    # 2. Beveled rounded corners (transparent corner pixels)
    corners = [
        (0, 0), (1, 0), (0, 1),
        (w - 1, 0), (w - 2, 0), (w - 1, 1),
        (0, h - 1), (1, h - 1), (0, h - 2),
        (w - 1, h - 1), (w - 2, h - 1), (w - 1, h - 2),
    ]
    for cx, cy in corners:
        set_pixel(buf, w, cx, cy, 0, 0, 0, 0)

    # 3. Outer metallic iron rim
    C_OUTER = (48, 50, 62, 255)
    C_OUTER_HI = (75, 78, 96, 255)
    C_OUTER_SHADOW = (22, 24, 30, 255)
    for x in range(2, w - 2):
        set_pixel(buf, w, x, 0, *C_OUTER_HI)
        set_pixel(buf, w, x, h - 1, *C_OUTER_SHADOW)
    for y in range(2, h - 2):
        set_pixel(buf, w, 0, y, *C_OUTER)
        set_pixel(buf, w, w - 1, y, *C_OUTER_SHADOW)

    # 4. Inner crimson occult hairline border
    C_CRIMSON = (110, 26, 38, 255)
    C_CRIMSON_DIM = (70, 18, 26, 220)
    for x in range(2, w - 2):
        set_pixel(buf, w, x, 1, *C_CRIMSON)
        set_pixel(buf, w, x, h - 2, *C_CRIMSON_DIM)
    for y in range(2, h - 2):
        set_pixel(buf, w, 1, y, *C_CRIMSON)
        set_pixel(buf, w, w - 2, y, *C_CRIMSON_DIM)

    # 5. Silver filigree corner brackets (4x4 in each corner)
    C_SILVER = (195, 205, 220, 255)
    C_SILVER_HI = (240, 245, 255, 255)
    C_SILVER_DARK = (110, 115, 130, 255)
    corner_offsets = [
        (2, 2, 1, 1),
        (w - 6, 2, -1, 1),
        (2, h - 6, 1, -1),
        (w - 6, h - 6, -1, -1),
    ]
    for ox, oy, dx, dy in corner_offsets:
        set_pixel(buf, w, ox, oy, *C_SILVER_HI)
        set_pixel(buf, w, ox + 1, oy, *C_SILVER)
        set_pixel(buf, w, ox + 2, oy, *C_SILVER_DARK)
        set_pixel(buf, w, ox, oy + 1, *C_SILVER)
        set_pixel(buf, w, ox + 1, oy + 1, *C_SILVER_HI)
        set_pixel(buf, w, ox, oy + 2, *C_SILVER_DARK)

    # 6. Left Icon: Miniature Cursed Page (12x15, centered at x=8..19, y=8..22)
    page_art = [
        ".11111111...",
        "1222222221..",
        "12333333221.",
        "123RR3332221",
        "123RRR331111",
        "1233RR333321",
        "12333RR33321",
        "1233RR333321",
        "123RRR333321",
        "123333333321",
        "123BBBBB3321",
        "123333333321",
        "123BBBBB3321",
        "122333333221",
        ".1111111111.",
    ]
    page_colors = {
        '.': (0, 0, 0, 0),
        '1': (70, 55, 40, 255),    # Burnt rim
        '2': (180, 165, 135, 255), # Aged parchment border
        '3': (230, 220, 195, 255), # Parchment surface
        'R': (160, 20, 30, 255),   # Crimson ink rune
        'B': (90, 70, 55, 255),    # Handwritten text line
    }
    px0, py0 = 8, 8
    for row_idx, row in enumerate(page_art):
        for col_idx, ch in enumerate(row):
            col = page_colors[ch]
            if col[3] > 0:
                set_pixel(buf, w, px0 + col_idx, py0 + row_idx, *col)

    # 7. Right Icon: Eldritch Watcher Eye Sigil (12x13, centered at x=w-21..w-10, y=9..21)
    eye_art = [
        "....1111....",
        "..11222211..",
        ".1223333221.",
        "123344443321",
        "123440044321",
        "123400004321",
        "12340VV04321",
        "123400004321",
        "123440044321",
        "123344443321",
        ".1223333221.",
        "..11222211..",
        "....1111....",
    ]
    eye_colors = {
        '.': (0, 0, 0, 0),
        '1': (30, 25, 45, 255),    # Shadow border
        '2': (80, 70, 110, 255),   # Muted violet ring
        '3': (140, 130, 175, 255), # Silver iris rim
        '4': (180, 30, 50, 255),   # Crimson inner eye
        '0': (12, 10, 18, 255),    # Void pupil slit
        'V': (255, 80, 100, 255),  # Piercing gaze spark
    }
    ex0, ey0 = w - 21, 9
    for row_idx, row in enumerate(eye_art):
        for col_idx, ch in enumerate(row):
            col = eye_colors[ch]
            if col[3] > 0:
                set_pixel(buf, w, ex0 + col_idx, ey0 + row_idx, *col)

    # 8. Subtle inner horizontal guide lines
    for x in range(24, w - 24):
        set_pixel(buf, w, x, 3, 35, 38, 50, 80)
        set_pixel(buf, w, x, h - 4, 18, 20, 28, 80)

    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_hud_pages_bg.png"), w, h, buf)

if __name__ == "__main__":
    generate_vignette()
    generate_hud_flash()
    generate_flash_camera()
    generate_dimensional_cloth()
    generate_shroud_of_stalking()
    generate_cursed_page_item()
    generate_ritual_pyre_textures()
    generate_pages_hud_bg()
    print("All pixel art textures successfully generated.")
