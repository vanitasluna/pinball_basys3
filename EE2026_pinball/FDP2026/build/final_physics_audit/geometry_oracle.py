from fractions import Fraction
from pathlib import Path
import random

rng = random.Random(20261014)
root = Path(__file__).resolve().parent
vectors = []
faces = [(1, 0, 1024), (-1, 0, 1024), (0, 1, 1024), (0, -1, 1024),
         (1, 1, 1472), (-1, -1, 1472), (1, -1, 1472), (-1, 1, 1472)]
for _ in range(30000):
    x, y = rng.randint(-1500, 1500), rng.randint(-1500, 1500)
    vx, vy = rng.randint(-256, 256), rng.randint(-320, 160)
    if all(a*x+b*y <= limit for a, b, limit in faces):
        continue
    lo, hi = Fraction(0), Fraction(1)
    hit = True
    for a, b, limit in faces:
        start = a*x+b*y
        delta = a*vx+b*vy
        if delta > 0:
            hi = min(hi, Fraction(limit-start, delta))
        elif delta < 0:
            lo = max(lo, Fraction(limit-start, delta))
        elif start > limit:
            hit = False
    hit = hit and lo <= hi
    fields = [x, y, vx, vy]
    vectors.append(''.join(f'{field & 0xffff:04x}' for field in fields) + f'{int(hit):02x}')
root.joinpath('octagon.hex').write_text('\n'.join(vectors)+'\n', encoding='ascii')
root.joinpath('count.vh').write_text(f'localparam COUNT = {len(vectors)};\n', encoding='ascii')
print(f'Generated {len(vectors)} exact rational segment/original-octagon checks')
