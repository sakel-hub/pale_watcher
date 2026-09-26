import os
import wave
import struct
import math
import random
import bpy
import aud

SOUNDS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "sounds"))
os.makedirs(SOUNDS_DIR, exist_ok=True)
SAMPLE_RATE = 44100

def write_wav_and_convert_to_ogg(filename, samples):
    # Normalize samples to -30000 .. +30000 (16-bit PCM)
    max_amp = max((abs(s) for s in samples), default=1.0)
    if max_amp <= 0.0001:
        max_amp = 1.0
    scale = 28000.0 / max_amp

    temp_wav = os.path.join(SOUNDS_DIR, "_temp_" + filename + ".wav")
    out_ogg = os.path.join(SOUNDS_DIR, filename)

    with wave.open(temp_wav, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        raw = bytearray()
        for s in samples:
            val = int(max(-32767, min(32767, s * scale)))
            raw.extend(struct.pack("<h", val))
        wf.writeframes(raw)

    snd = aud.Sound.file(temp_wav)
    snd.write(out_ogg, rate=SAMPLE_RATE, channels=aud.CHANNELS_MONO,
              format=aud.FORMAT_S16, container=aud.CONTAINER_OGG,
              codec=aud.CODEC_VORBIS, bitrate=128000)

    if os.path.exists(temp_wav):
        os.remove(temp_wav)
    print(f"Generated {out_ogg}")

def generate_paper_burn():
    # 3 seconds of sizzling paper burn & crackling embers
    duration = 3.0
    n = int(SAMPLE_RATE * duration)
    samples = [0.0] * n

    # Base low rumble + mid hiss
    lp = 0.0
    hp = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        fade = 1.0 if t < 2.0 else max(0.0, (duration - t) / 1.0)
        white = (random.random() * 2.0 - 1.0)
        # Lowpass filter for flame body
        lp += 0.08 * (white - lp)
        # Highpass filter for parchment hiss
        hp = white - lp
        env = (0.4 + 0.3 * math.sin(2 * math.pi * 3.5 * t)) * fade
        samples[i] += (lp * 0.4 + hp * 0.3) * env

    # Random explosive crackles / micro-pops of burning ember
    num_crackles = int(duration * 45)
    for _ in range(num_crackles):
        idx = random.randint(0, n - 400)
        pop_len = random.randint(80, 250)
        amp = random.uniform(0.6, 1.8)
        freq = random.uniform(1200, 4500)
        for j in range(pop_len):
            if idx + j < n:
                decay = math.exp(-j * 0.04)
                samples[idx + j] += amp * math.sin(2 * math.pi * freq * (j / SAMPLE_RATE)) * decay

    write_wav_and_convert_to_ogg("pale_watcher_paper_burn.ogg", samples)

def generate_camera_flash():
    # 2 seconds: shutter click + capacitor whine + bulb pop
    duration = 2.0
    n = int(SAMPLE_RATE * duration)
    samples = [0.0] * n

    # 1. Shutter mechanical click (0.0 to 0.08s)
    click_len = int(SAMPLE_RATE * 0.08)
    for i in range(click_len):
        decay = math.exp(-i * 0.015)
        samples[i] += (random.random() * 2 - 1) * decay * 1.5

    # 2. Bulb ignition pop & sizzle (0.02 to 0.35s)
    pop_start = int(SAMPLE_RATE * 0.03)
    pop_len = int(SAMPLE_RATE * 0.3)
    for i in range(pop_len):
        t = i / SAMPLE_RATE
        decay = math.exp(-t * 12.0)
        pop = math.sin(2 * math.pi * 320 * t) * decay * 1.8
        fizz = (random.random() * 2 - 1) * math.exp(-t * 8.0) * 0.8
        if pop_start + i < n:
            samples[pop_start + i] += pop + fizz

    # 3. Capacitor recharge high whine (0.4 to 1.8s)
    whine_start = int(SAMPLE_RATE * 0.4)
    whine_len = int(SAMPLE_RATE * 1.4)
    for i in range(whine_len):
        t = i / SAMPLE_RATE
        freq = 1200.0 + 3500.0 * (t / 1.4) ** 2
        env = math.sin(math.pi * (t / 1.4)) * 0.25
        if whine_start + i < n:
            samples[whine_start + i] += math.sin(2 * math.pi * freq * t) * env

    write_wav_and_convert_to_ogg("pale_watcher_camera_flash.ogg", samples)

def generate_page_whisper():
    # 4 seconds subtle eerie ink whispering
    duration = 4.0
    n = int(SAMPLE_RATE * duration)
    samples = [0.0] * n

    for i in range(n):
        t = i / SAMPLE_RATE
        # Formant frequencies modulating like quiet whispered syllables
        f1 = 450 + 200 * math.sin(2 * math.pi * 0.8 * t)
        f2 = 1800 + 400 * math.cos(2 * math.pi * 1.3 * t)
        noise = (random.random() * 2 - 1)
        amp = (0.5 + 0.5 * math.sin(2 * math.pi * 0.5 * t)) * (0.5 + 0.5 * math.sin(2 * math.pi * 2.2 * t))
        res = math.sin(2 * math.pi * f1 * t) * 0.3 + math.sin(2 * math.pi * f2 * t) * 0.15
        samples[i] = (noise * 0.4 + res * 0.6) * amp * 0.4

    write_wav_and_convert_to_ogg("pale_watcher_page_whisper.ogg", samples)

def generate_watcher_drone():
    # 5 seconds foghorn / deep domain release drone
    duration = 5.0
    n = int(SAMPLE_RATE * duration)
    samples = [0.0] * n

    for i in range(n):
        t = i / SAMPLE_RATE
        envelope = (1.0 - math.exp(-t * 2.0)) * math.exp(-(t - 1.0) * 0.5 if t > 1.0 else 1.0)
        f0 = 55.0  # A1
        f1 = 110.0 # Octave
        f2 = 165.0 # Fifth
        sub = math.sin(2 * math.pi * f0 * t) * 0.6
        harm1 = math.sin(2 * math.pi * f1 * t) * 0.3
        harm2 = math.sin(2 * math.pi * f2 * t + 0.2) * 0.2
        brass = math.sin(2 * math.pi * 220.0 * t) * 0.1 * math.sin(2 * math.pi * 4.0 * t)
        samples[i] = (sub + harm1 + harm2 + brass) * envelope

    write_wav_and_convert_to_ogg("pale_watcher_drone.ogg", samples)

def generate_watcher_stun():
    # 2.5 seconds dissonant glitch screech
    duration = 2.5
    n = int(SAMPLE_RATE * duration)
    samples = [0.0] * n

    for i in range(n):
        t = i / SAMPLE_RATE
        decay = math.exp(-t * 1.2)
        # Sweeping saw/square frequencies
        f = 2400.0 * math.exp(-t * 1.5) + 300.0 * math.sin(2 * math.pi * 18.0 * t)
        screech = math.copysign(1.0, math.sin(2 * math.pi * f * t)) * 0.4
        static = (random.random() * 2 - 1) * 0.5
        samples[i] = (screech + static) * decay

    write_wav_and_convert_to_ogg("pale_watcher_stun.ogg", samples)

if __name__ == "__main__":
    generate_paper_burn()
    generate_camera_flash()
    generate_page_whisper()
    generate_watcher_drone()
    generate_watcher_stun()
    print("All audio assets synthesized successfully.")
