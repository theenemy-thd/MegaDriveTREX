# Sprite Limit Off test 2: 24 overlapping 16x16 sprites with flips and two palettes,
# more than the VDP can show on a line (sprite count and dot limits).
# Writes rom_spr2.hex and spr2_ref.txt (reference render of lines 95..125 with no limits).
#   python mkrom_spr2.py [h32]
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

h32 = len(sys.argv) > 1 and sys.argv[1] == 'h32'
WIDTH = 256 if h32 else 320
NSPR = 24

prog = []
def w(*ws): prog.extend(ws)
def L(n): prog.append(('label', n))
def dbf(r, l): prog.append(('dbf', r, l))
def bra(l): prog.append(('bcc', 0x6000, l))

def assemble(org):
    addr, labels = org, {}
    for it in prog:
        if isinstance(it, int): addr += 2
        elif it[0] == 'label': labels[it[1]] = addr
        elif it[0] == 'dbf': addr += 4
        else: addr += 2
    out, addr = [], org
    for it in prog:
        if isinstance(it, int): out.append(it); addr += 2
        elif it[0] == 'label': pass
        elif it[0] == 'dbf':
            d = labels[it[2]] - (addr + 2); out += [0x51C8 | it[1], d & 0xFFFF]; addr += 4
        else:
            d = labels[it[2]] - (addr + 2); assert -128 <= d < 128 and d; out.append(it[1] | (d & 0xFF)); addr += 2
    return out

# --- data ---
def pix(t, x, y):
    if (x * 3 + y * 5 + t) % 7 == 0: return 0
    return ((x + 2 * y + t * 3) % 15) + 1

tiles = {}
for t in range(1, 5):
    rows = []
    for y in range(8):
        v = 0
        for x in range(8): v = (v << 4) | pix(t, x, y)
        rows += [(v >> 16) & 0xFFFF, v & 0xFFFF]
    tiles[t] = rows
tile_words = sum((tiles[t] for t in range(1, 5)), [])

cram = []
for p in range(2):
    for i in range(16):
        r, b = i & 7, i >> 3
        cram.append((r << 1) | (b << 9) | ((7 << 5) if p else 0))

spr = []
for i in range(NSPR):
    y = 128 + 100 - (i % 3) * 5
    x = 128 + i * 13 - 4
    link = i + 1 if i + 1 < NSPR else 0
    pat = 1 | ((i & 1) << 11) | (((i >> 1) & 1) << 12) | ((i % 2) << 13) | (((i >> 2) & 1) << 15)
    spr.append((y, 0x5, link, pat, x))
sat_words = []
for (y, size, link, pat, x) in spr:
    sat_words += [y, (size << 8) | link, pat, x]

# --- program ---
w(0x43F9, 0x00C0, 0x0004)                  # lea $C00004,a1
w(0x45F9, 0x00C0, 0x0000)                  # lea $C00000,a2
regs = (0x8004, 0x8144, 0x8230, 0x8407, 0x857C, 0x8700, 0x8C00 if h32 else 0x8C81, 0x8F02, 0x8D3F, 0x9001)
for r in regs: w(0x32BC, r)
def copy(cmd, table_label, n):
    w(0x22BC, cmd >> 16, cmd & 0xFFFF)      # move.l #cmd,(a1)
    prog.append(('lea', table_label))       # lea table,a0
    w(0x3E3C, n - 1)                        # move.w #n-1,d7
    lab = 'c%d' % len(prog)
    L(lab)
    w(0x3498)                               # move.w (a0)+,(a2)
    dbf(7, lab)
copy(0xC0000000, 'cram', len(cram))
copy(0x40200000, 'tiles', len(tile_words))
copy(0x78000003, 'sat', len(sat_words))
L('end'); bra('end')

TABLES = 0x1000
tables = {'cram': cram, 'tiles': tile_words, 'sat': sat_words}
taddr, a = {}, TABLES
for k, v in tables.items(): taddr[k] = a; a += 2 * len(v)
prog = [(0x41F9, taddr[it[1]] >> 16, taddr[it[1]] & 0xFFFF) if isinstance(it, tuple) and it[0] == 'lea' else it for it in prog]
flat = []
for it in prog:
    if isinstance(it, tuple) and len(it) == 3 and all(isinstance(z, int) for z in it): flat += list(it)
    else: flat.append(it)
prog = flat

words = [0] * 4096
code = assemble(0x200)
assert 0x200 + 2 * len(code) <= 0x700
words[0:4] = [0x00FF, 0xFE00, 0x0000, 0x0200]
for v in range(2, 64): words[v * 2:v * 2 + 2] = [0x0000, 0x0700]
words[0x100:0x100 + len(code)] = code
words[0x380:0x385] = [0x33FC, 0x0BAD, 0x00FF, 0x8020, 0x60FE]
for k, v in tables.items(): words[taddr[k] // 2:taddr[k] // 2 + len(v)] = v
open('rom_spr2.hex', 'w').write(''.join(('%04X' % x) + chr(10) for x in words))

# --- reference: all sprites, first in the list wins, background colour 0 ---
def ref_line(line):
    out = [None] * WIDTH
    for (y, size, link, pat, x) in spr:
        hs, vs = (size >> 2) & 3, size & 3
        row = line + 128 - y
        if not (0 <= row < (vs + 1) * 8): continue
        hf, vf = (pat >> 11) & 1, (pat >> 12) & 1
        pal = (pat >> 13) & 3
        r = (vs * 8 + 7 - row) if vf else row
        for c in range(hs + 1):
            cc = hs - c if hf else c
            tile = (pat & 0x7FF) + cc * (vs + 1) + r // 8
            for px in range(8):
                p = 7 - px if hf else px
                v = pix(tile, p, r % 8)
                sx = x - 128 + c * 8 + px
                if v and 0 <= sx < WIDTH and out[sx] is None: out[sx] = (pal, v)
    return out
with open('spr2_ref.txt', 'w') as f:
    for line in range(95, 126):
        f.write('%d %s\n' % (line, ' '.join('-' if v is None else '%d.%d' % v for v in ref_line(line))))
print('ok', len(code), 'code words')
