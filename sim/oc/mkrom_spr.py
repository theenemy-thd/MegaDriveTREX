# Builds the 68000 test ROM for the overclock bench (rom.hex, one 16-bit word per line).
# Results go to work RAM $FF8000.. and the bench prints them when $600D is written
# to $FF8020 ($0BAD there means an exception happened).
import sys

prog = []          # items: int word, ('label', name), ('br', opcode_base, label), ('dbf', reg, label)
def w(*ws): prog.extend(ws)
def L(name): prog.append(('label', name))
def dbf(reg, lab): prog.append(('dbf', reg, lab))
def bne(lab): prog.append(('bcc', 0x6600, lab))
def bra(lab): prog.append(('bcc', 0x6000, lab))

def assemble(org):
    # pass 1: addresses
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
            d = labels[it[2]] - (addr + 2)
            out += [0x51C8 | it[1], d & 0xFFFF]; addr += 4
        else:
            d = labels[it[2]] - (addr + 2)
            assert -128 <= d < 128 and d != 0
            out.append(it[1] | (d & 0xFF)); addr += 2
    return out

# --- sprite test: 30 8x8 sprites on lines 100-107 (H40 shows 20 per line) ---
w(0x43F9,0x00C0,0x0004)        # lea $C00004,a1
w(0x45F9,0x00C0,0x0000)        # lea $C00000,a2
for r in (0x8004,0x8144,0x8230,0x8407,0x857C,0x8700,0x8C81,0x8F02,0x8D3F,0x9001):
    w(0x32BC, r)               # move.w #reg,(a1)
w(0x22BC,0xC000,0x0000)        # CRAM 0
w(0x34BC,0x0000, 0x34BC,0x000E)        # pal0: 0, red
w(0x22BC,0xC020,0x0000)        # CRAM $20
w(0x34BC,0x0000, 0x34BC,0x00E0)        # pal1: 0, green
w(0x22BC,0x4020,0x0000)        # VRAM $0020 (tile 1)
w(0x7E0F)                      # moveq #15,d7
L('t1')
w(0x34BC,0x1111)               # move.w #$1111,(a2)
dbf(7,'t1')
w(0x22BC,0x7800,0x0003)        # VRAM $F800 (SAT)
w(0x7000)                      # moveq #0,d0
L('s1')
w(0x34BC,0x00E4)               # y = 228 (line 100)
w(0x3400, 0x5242, 0x0C42,0x001E) # d2 = d0+1; cmp #30
bne('s2')
w(0x7400)                      # last link = 0
L('s2')
w(0x3482)                      # size 0 | link
w(0x3600, 0x0243,0x0001, 0xE65B, 0x0043,0x0001, 0x3483) # pattern: pal = i&1, tile 1
w(0x3800, 0xC8FC,0x000C, 0x0644,0x0088, 0x3484)         # x = 136 + 12*i
w(0x5240, 0x0C40,0x001E)       # i++; cmp #30
bne('s1')
L('end')
bra('end')

words = [0] * 0x400
code = assemble(0x200)
assert 0x200 + 2 * len(code) <= 0x700
words[0:4] = [0x00FF, 0xFE00, 0x0000, 0x0200]
for v in range(2, 64):
    words[v * 2:v * 2 + 2] = [0x0000, 0x0700]
words[0x100:0x100 + len(code)] = code
words[0x380:0x385] = [0x33FC, 0x0BAD, 0x00FF, 0x8020, 0x60FE]
open(sys.argv[1] if len(sys.argv) > 1 else 'rom_spr.hex', 'w').write(''.join(('%04X' % x) + chr(10) for x in words))
