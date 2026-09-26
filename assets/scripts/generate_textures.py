#!/usr/bin/env python3
"""
pale_watcher Texture Generator
Generates:
1. pale_watcher_particles.png (16x128 8-frame vertical horror particle spritesheet)
2. pale_watcher_body.png (64x64 greyscale for BodyMat: head, fingers, tendrils)
3. pale_watcher_suit.png (64x64 greyscale for SuitMat: torso jacket, sleeves, trousers)
4. pale_watcher_tie.png (64x64 greyscale for TieMat: tie knot and blade)
"""

import os
import struct
import zlib
import math

TEXTURES_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "textures"))
os.makedirs(TEXTURES_DIR, exist_ok=True)

def write_png(filepath, width, height, rgba_data):
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    raw_lines = bytearray()
    for y in range(height):
        raw_lines.append(0)  # filter type 0 (None)
        raw_lines.extend(rgba_data[y * width * 4 : (y + 1) * width * 4])

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(bytes(raw_lines), 9))
    iend = chunk(b'IEND', b'')

    with open(filepath, 'wb') as f:
        f.write(header + ihdr + idat + iend)
    print(f"Generated {os.path.basename(filepath)} ({width}x{height})")

def set_pixel(buf, w, x, y, r, g, b, a=255):
    if 0 <= x < w and 0 <= y < (len(buf) // (w * 4)):
        idx = (y * w + x) * 4
        buf[idx] = max(0, min(255, int(r)))
        buf[idx + 1] = max(0, min(255, int(g)))
        buf[idx + 2] = max(0, min(255, int(b)))
        buf[idx + 3] = max(0, min(255, int(a)))

def get_pixel(buf, w, x, y):
    if 0 <= x < w and 0 <= y < (len(buf) // (w * 4)):
        idx = (y * w + x) * 4
        return (buf[idx], buf[idx+1], buf[idx+2], buf[idx+3])
    return (0, 0, 0, 0)

def fill_rect(buf, w, x0, y0, rw, rh, r, g, b, a=255):
    for y in range(y0, y0 + rh):
        for x in range(x0, x0 + rw):
            set_pixel(buf, w, x, y, r, g, b, a)

# ==============================================================================
# 1. HORROR PARTICLE SPRITESHEET (16x128 - 8 Frames of 16x16)
# ==============================================================================
def generate_particles():
    w, h = 16, 128
    buf = bytearray(w * h * 4)

    # Frame 0: Void Shadow Tendril / Smoke Wisp (y = 0..15)
    # A curling, ethereal shadow tendril with soft alpha dropoff
    for y in range(16):
        t = y / 15.0
        # S-curve tendril center
        cx = 7.5 + math.sin(t * math.pi * 1.5) * 3.5
        radius = 1.0 + (1.0 - t) * 3.2
        for x in range(16):
            dist = abs(x - cx)
            if dist < radius:
                alpha = int((1.0 - (dist / radius) ** 1.8) * (180 + 75 * (1.0 - t)))
                v = int(12 + (1.0 - t) * 18)
                set_pixel(buf, w, x, y, v, v, v + 4, alpha)
    # Add subtle wisps around tendril
    for (wx, wy, wa) in [(3, 4, 110), (4, 3, 140), (12, 10, 90), (11, 11, 120), (7, 14, 160)]:
        set_pixel(buf, w, wx, wy, 15, 12, 20, wa)

    # Frame 1: Static Glitch Noise / CRT Interference (y = 16..31)
    # Fragmented scanlines and digital artifact clusters
    f1_y0 = 16
    glitch_pixels = [
        # Scanline blocks
        (2, 2, 4, 1, 230, 210), (9, 2, 5, 1, 180, 160),
        (1, 5, 6, 1, 240, 240), (10, 5, 3, 1, 140, 130),
        (4, 8, 8, 1, 255, 255), (1, 9, 3, 1, 190, 180), (12, 9, 3, 1, 190, 180),
        (3, 12, 5, 1, 220, 200), (9, 12, 6, 1, 210, 190),
        (2, 14, 12, 1, 160, 150),
        # Noise specks
        (3, 3, 1, 1, 255, 255), (7, 6, 1, 1, 255, 255), (13, 7, 1, 1, 255, 255),
        (5, 10, 1, 1, 255, 255), (11, 13, 1, 1, 255, 255), (1, 13, 1, 1, 200, 180),
    ]
    for (gx, gy, gw, gh, val, a) in glitch_pixels:
        for py in range(gh):
            for px in range(gw):
                set_pixel(buf, w, gx + px, f1_y0 + gy + py, val, val, val, a)

    # Frame 2: Eldritch Sigil / Scratched Operator Rune (y = 32..47)
    # Scratched circular glyph with an X through it, dripping ink
    f2_y0 = 32
    # Circle
    for angle_deg in range(0, 360, 10):
        rad = math.radians(angle_deg)
        rx = 7.5 + math.cos(rad) * 5.2
        ry = 7.5 + math.sin(rad) * 5.2
        set_pixel(buf, w, int(rx), f2_y0 + int(ry), 22, 18, 25, 240)
        # Jagged scratch variation
        if angle_deg % 30 == 0:
            set_pixel(buf, w, int(rx + math.cos(rad)), f2_y0 + int(ry + math.sin(rad)), 35, 28, 40, 160)
    # Diagonal cross
    for d in range(11):
        # Top-left to bottom-right
        set_pixel(buf, w, 3 + d, f2_y0 + 3 + d, 25, 20, 30, 245)
        # Top-right to bottom-left
        set_pixel(buf, w, 13 - d, f2_y0 + 3 + d, 25, 20, 30, 245)
    # Ink drips down
    set_pixel(buf, w, 7, f2_y0 + 13, 20, 15, 25, 200)
    set_pixel(buf, w, 7, f2_y0 + 14, 20, 15, 25, 150)
    set_pixel(buf, w, 8, f2_y0 + 14, 20, 15, 25, 120)

    # Frame 3: Dark Ink Splatter / Decaying Droplet (y = 48..63)
    f3_y0 = 48
    # Main droplet core
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            dist = math.hypot(dx, dy)
            if dist <= 3.2:
                alpha = int((1.0 - (dist / 3.4) ** 2) * 255)
                v = int(14 + (dist / 3.4) * 16)
                set_pixel(buf, w, 7 + dx, f3_y0 + 7 + dy, v, v, v + 2, alpha)
    # Splatter droplets
    splats = [
        (2, 3, 200), (3, 4, 160), (12, 4, 180), (13, 3, 140),
        (2, 11, 160), (4, 13, 220), (11, 12, 190), (13, 10, 150),
        (7, 13, 230), (7, 14, 180), (8, 14, 140), (8, 15, 90)
    ]
    for (sx, sy, sa) in splats:
        set_pixel(buf, w, sx, f3_y0 + sy, 18, 15, 22, sa)

    # Frame 4: Whispering Void Ash / Static Ember (y = 64..79)
    # Soft glowing specks of dimensional static ash floating upward
    f4_y0 = 64
    embers = [
        (7, 3, 2.0, 255, 240),
        (4, 7, 1.6, 230, 200),
        (11, 6, 1.8, 240, 210),
        (3, 12, 1.4, 210, 170),
        (9, 11, 2.2, 255, 230),
        (13, 13, 1.2, 190, 150),
        (6, 14, 1.5, 220, 180),
    ]
    for (ex, ey, rad, bright, a) in embers:
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                d = math.hypot(dx, dy)
                if d <= rad:
                    ca = int((1.0 - d / rad) * a)
                    set_pixel(buf, w, ex + dx, f4_y0 + ey + dy, bright, bright, bright, ca)

    # Frame 5: Spectral Eye / Stalking Slit (y = 80..95)
    # Eerie horizontal eye slit staring from the shadows
    f5_y0 = 80
    for x in range(2, 14):
        t = (x - 7.5) / 5.5
        if abs(t) <= 1.0:
            half_h = (1.0 - t * t) * 2.2
            for y_off in range(-2, 3):
                if abs(y_off) <= half_h:
                    v = int(220 * (1.0 - abs(y_off) / 2.5))
                    set_pixel(buf, w, x, f5_y0 + 7 + y_off, v, v, v, 230)
    # Center slit pupil
    set_pixel(buf, w, 7, f5_y0 + 7, 10, 10, 15, 255)
    set_pixel(buf, w, 8, f5_y0 + 7, 10, 10, 15, 255)
    set_pixel(buf, w, 7, f5_y0 + 6, 15, 15, 20, 200)
    set_pixel(buf, w, 8, f5_y0 + 6, 15, 15, 20, 200)
    set_pixel(buf, w, 7, f5_y0 + 8, 15, 15, 20, 200)
    set_pixel(buf, w, 8, f5_y0 + 8, 15, 15, 20, 200)

    # Frame 6: Tendril Barb / Void Thorn (y = 96..111)
    f6_y0 = 96
    for i in range(12):
        bx = int(3 + i * 0.9)
        by = int(14 - math.sin(i / 11.0 * math.pi * 0.7) * 11)
        width = int(2.5 * (1.0 - i / 12.0) + 0.5)
        for w_off in range(-width, width + 1):
            set_pixel(buf, w, bx + w_off, f6_y0 + by, 20, 18, 25, 230)
    set_pixel(buf, w, 13, f6_y0 + 3, 20, 18, 25, 255) # Sharp tip

    # Frame 7: Quantum Glitch Burst / 4-Point Spark (y = 112..127)
    f7_y0 = 112
    # Radiating cross
    for d in range(8):
        ca = int((1.0 - d / 7.0) * 255)
        cv = int(180 + (1.0 - d / 7.0) * 75)
        set_pixel(buf, w, 7, f7_y0 + 7 - d, cv, cv, cv, ca)
        set_pixel(buf, w, 8, f7_y0 + 7 - d, cv, cv, cv, ca)
        set_pixel(buf, w, 7, f7_y0 + 8 + d, cv, cv, cv, ca)
        set_pixel(buf, w, 8, f7_y0 + 8 + d, cv, cv, cv, ca)
        set_pixel(buf, w, 7 - d, f7_y0 + 7, cv, cv, cv, ca)
        set_pixel(buf, w, 7 - d, f7_y0 + 8, cv, cv, cv, ca)
        set_pixel(buf, w, 8 + d, f7_y0 + 7, cv, cv, cv, ca)
        set_pixel(buf, w, 8 + d, f7_y0 + 8, cv, cv, cv, ca)
    # Bright core
    set_pixel(buf, w, 7, f7_y0 + 7, 255, 255, 255, 255)
    set_pixel(buf, w, 8, f7_y0 + 7, 255, 255, 255, 255)
    set_pixel(buf, w, 7, f7_y0 + 8, 255, 255, 255, 255)
    set_pixel(buf, w, 8, f7_y0 + 8, 255, 255, 255, 255)

    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_particles.png"), w, h, buf)

# ==============================================================================
# 2. GREYSCALE MESH SKINS (64x64): BODY, SUIT, TIE, AND COMPOSITE
# ==============================================================================
def generate_mesh_skins():
    w, h = 64, 64
    buf_body = bytearray(w * h * 4)
    buf_suit = bytearray(w * h * 4)
    buf_tie = bytearray(w * h * 4)

    # --------------------------------------------------------------------------
    # BODY TEXTURE: Head, Fingers, Tendrils
    # --------------------------------------------------------------------------
    # HEAD (u0=0, v0=0, w=8, d=8, h=8) -> bounds [0, 0] to [32, 16]
    # Faces:
    # Right: [0..7, 8..15]
    # Front: [8..15, 8..15]
    # Left: [16..23, 8..15]
    # Back: [24..31, 8..15]
    # Top: [8..15, 0..7]
    # Bottom: [16..23, 0..7]

    # Fill base head with pale parchment skin tones
    fill_rect(buf_body, w, 0, 0, 32, 16, 210, 210, 210, 255)

    # Top of head [8..15, 0..7] - subtle cranial lighting
    for y in range(0, 8):
        for x in range(8, 16):
            d = math.hypot(x - 11.5, y - 3.5)
            val = int(235 - d * 5)
            set_pixel(buf_body, w, x, y, val, val, val, 255)

    # Bottom of head / neck underside [16..23, 0..7] - shadowed neck
    for y in range(0, 8):
        for x in range(16, 24):
            val = int(140 + y * 6)
            set_pixel(buf_body, w, x, y, val, val, val, 255)

    # Sides [0..7, 8..15] (Right) and [16..23, 8..15] (Left) - subtle jawline depth
    for y in range(8, 16):
        for x in range(0, 8): # Right
            val = int(185 + x * 4 - (y - 8) * 3)
            set_pixel(buf_body, w, x, y, val, val, val, 255)
        for x in range(16, 24): # Left
            val = int(215 - (x - 16) * 4 - (y - 8) * 3)
            set_pixel(buf_body, w, x, y, val, val, val, 255)

    # Back [24..31, 8..15] - uniform pale skin with subtle occluded center
    for y in range(8, 16):
        for x in range(24, 32):
            d = abs(x - 27.5)
            val = int(195 + d * 3)
            set_pixel(buf_body, w, x, y, val, val, val, 255)

    # FRONT FACE OF HEAD [8..15, 8..15] - The Uncanny Blank Visage
    # Forehead highlight
    for y in range(8, 11):
        for x in range(8, 16):
            val = 240 if 10 <= x <= 13 else 225
            set_pixel(buf_body, w, x, y, val, val, val, 255)
    # Hollow eye sockets (faint depressions without eyes)
    for y in range(11, 13):
        for x in range(8, 16):
            if x in (10, 13):
                set_pixel(buf_body, w, x, y, 190, 190, 190, 255) # eye hollows
            elif x in (11, 12):
                set_pixel(buf_body, w, x, y, 230, 230, 230, 255) # nasal bridge highlight
            else:
                set_pixel(buf_body, w, x, y, 215, 215, 215, 255)
    # Smooth cheekbones and tapered chin
    for y in range(13, 16):
        for x in range(8, 16):
            if x in (9, 14):
                set_pixel(buf_body, w, x, y, 205, 205, 205, 255) # cheek shading
            elif x in (11, 12) and y == 15:
                set_pixel(buf_body, w, x, y, 200, 200, 200, 255) # chin underside
            else:
                set_pixel(buf_body, w, x, y, 225, 225, 225, 255)

    # FINGERS (Left hand [0..11, 44..50], Right hand [0..11, 52..58])
    for hand_y in (44, 52):
        for f in range(3):
            fx = f * 4
            fill_rect(buf_body, w, fx, hand_y, 4, 7, 210, 210, 210, 255)
            # Knuckle joint crease
            set_pixel(buf_body, w, fx + 1, hand_y + 3, 130, 130, 130, 255)
            set_pixel(buf_body, w, fx + 2, hand_y + 3, 130, 130, 130, 255)
            # Sharp tip
            set_pixel(buf_body, w, fx + 1, hand_y + 6, 245, 245, 245, 255)
            set_pixel(buf_body, w, fx + 2, hand_y + 6, 245, 245, 245, 255)

    # TENDRILS ([16..47, 46..63]) - writhing organic void black with chitin segments
    for tx in range(16, 48):
        for ty in range(46, 64):
            # Segmented rib pattern
            seg = (ty + (tx // 4)) % 4
            if seg == 0:
                v = 45 # Chitin ridge highlight
            elif seg == 1:
                v = 28
            else:
                v = 15 # Void dark
            set_pixel(buf_body, w, tx, ty, v, v, v, 255)

    # --------------------------------------------------------------------------
    # SUIT TEXTURE: Torso Jacket, Sleeves (Arms), Trousers (Legs)
    # --------------------------------------------------------------------------
    # TORSO (u0=16, v0=16, w=8, d=5, h=24) -> [16, 16] to [42, 45]
    # Top (+Z): [21..28, 16..20] - Shoulders
    # Bottom (-Z): [29..36, 16..20] - Hem underside
    # Right (+X): [16..20, 21..44] - Right side panel
    # Front (+Y): [21..28, 21..44] - Jacket front & lapels
    # Left (-X): [29..33, 21..44] - Left side panel
    # Back (-Y): [34..41, 21..44] - Jacket back & vent

    # Base suit charcoal greyscale
    fill_rect(buf_suit, w, 16, 16, 26, 29, 50, 50, 50, 255)

    # Shoulders (Top [21..28, 16..20])
    for y in range(16, 21):
        for x in range(21, 29):
            d = abs(x - 24.5)
            v = int(60 + d * 5)
            set_pixel(buf_suit, w, x, y, v, v, v, 255)

    # Jacket Sides ([16..20, 21..44] and [29..33, 21..44])
    for y in range(21, 45):
        for x in range(16, 21): # Right side
            v = int(45 - abs(x - 18) * 4)
            set_pixel(buf_suit, w, x, y, v, v, v, 255)
        for x in range(29, 34): # Left side
            v = int(45 - abs(x - 31) * 4)
            set_pixel(buf_suit, w, x, y, v, v, v, 255)

    # Jacket Back ([34..41, 21..44])
    for y in range(21, 45):
        for x in range(34, 42):
            v = 52
            # Spine seam
            if x in (37, 38):
                v = 35
            # Lower vent slit
            if y >= 38 and x in (37, 38):
                v = 22
            set_pixel(buf_suit, w, x, y, v, v, v, 255)

    # Jacket Front ([21..28, 21..44]) - Detailed Victorian Cut
    for y in range(21, 45):
        for x in range(21, 29):
            v = 50
            # 1. Dress Shirt Collar V-Neck (rows 21..27)
            dx = abs(x - 24.5)
            if y <= 27 and dx < (y - 20) * 0.4:
                # White dress shirt in pale greyscale
                v = int(220 + (27 - y) * 5)
            elif y <= 33 and (x in (22, 23) or x in (26, 27)):
                # Wide peaked lapels
                v = 68
                if x in (22, 27):
                    v = 82 # Lapel outer highlight edge
            elif y > 27:
                # Jacket body
                v = 48
                # Center seam
                if x == 24:
                    v = 30
                # Front jacket buttons at y=33 and y=37
                if (y == 33 or y == 37) and x == 24:
                    v = 135 # Horn/metal button highlight
                # Breast pocket welt at left chest (x=26..27, y=28)
                if y == 28 and x in (26, 27):
                    v = 75
                # Bottom hem
                if y == 44:
                    v = 32
            set_pixel(buf_suit, w, x, y, v, v, v, 255)

    # SLEEVES / ARMS
    # Arm_L_Upper [32..39, 0..13], Arm_L_Lower [40..47, 0..13]
    # Arm_R_Upper [48..55, 0..13], Arm_R_Lower [56..63, 0..13]
    for arm_x in (32, 40, 48, 56):
        fill_rect(buf_suit, w, arm_x, 0, 8, 14, 50, 50, 50, 255)
        # Shoulder cap highlights on upper arms
        if arm_x in (32, 48):
            for x in range(arm_x, arm_x + 8):
                set_pixel(buf_suit, w, x, 0, 68, 68, 68, 255)
                set_pixel(buf_suit, w, x, 1, 62, 62, 62, 255)
        # Sleeve cuffs on lower arms
        if arm_x in (40, 56):
            for x in range(arm_x, arm_x + 8):
                set_pixel(buf_suit, w, x, 13, 35, 35, 35, 255) # Cuff rim
                set_pixel(buf_suit, w, x, 12, 62, 62, 62, 255) # Cuff band
            # Cuff buttons
            set_pixel(buf_suit, w, arm_x + 2, 12, 120, 120, 120, 255)
            set_pixel(buf_suit, w, arm_x + 4, 12, 120, 120, 120, 255)

    # LEGS / TROUSERS
    # Leg_L [0..11, 16..42], Leg_R [44..55, 16..42]
    for leg_x in (0, 44):
        fill_rect(buf_suit, w, leg_x, 16, 12, 27, 46, 46, 46, 255)
        # Vertical trouser crease down the front (x_off = 4..5)
        for y in range(16, 42):
            set_pixel(buf_suit, w, leg_x + 4, y, 62, 62, 62, 255) # Crease highlight
            set_pixel(buf_suit, w, leg_x + 5, y, 35, 35, 35, 255) # Crease shadow
        # Knee wrinkles (y = 28..30)
        set_pixel(buf_suit, w, leg_x + 3, 29, 32, 32, 32, 255)
        set_pixel(buf_suit, w, leg_x + 6, 29, 32, 32, 32, 255)
        # Trouser cuff hem
        for x in range(leg_x, leg_x + 12):
            set_pixel(buf_suit, w, x, 42, 28, 28, 28, 255)

    # --------------------------------------------------------------------------
    # TIE TEXTURE: Tie Knot & Blade ([56..63, 16..31])
    # --------------------------------------------------------------------------
    # Knot [56..61, 16..18]
    fill_rect(buf_tie, w, 56, 16, 6, 3, 75, 75, 75, 255)
    # Knot dimple & highlight
    set_pixel(buf_tie, w, 58, 17, 130, 130, 130, 255)
    set_pixel(buf_tie, w, 59, 17, 130, 130, 130, 255)
    set_pixel(buf_tie, w, 58, 18, 45, 45, 45, 255)
    set_pixel(buf_tie, w, 59, 18, 45, 45, 45, 255)

    # Blade [56..61, 19..30]
    for y in range(19, 31):
        for x in range(56, 62):
            # Diagonal silk twill rib pattern
            diag = (x + y) % 3
            v = 85 if diag == 0 else 65
            # Center fold highlight
            if x in (58, 59):
                v += 28
            # Border edge shadows
            if x in (56, 61):
                v -= 24
            # Pointed bottom tip
            if y == 30 and x in (56, 61):
                v = 0
                set_pixel(buf_tie, w, x, y, 0, 0, 0, 0)
                continue
            set_pixel(buf_tie, w, x, y, v, v, v, 255)

    # Save individual greyscale textures
    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_body.png"), w, h, buf_body)
    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_suit.png"), w, h, buf_suit)
    write_png(os.path.join(TEXTURES_DIR, "pale_watcher_tie.png"), w, h, buf_tie)

if __name__ == "__main__":
    generate_particles()
    generate_mesh_skins()
    print("All textures generated successfully.")
