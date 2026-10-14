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

# --- program ---
w(0x41F9,0x00FF,0x0000)        # lea $FF0000,a0
w(0x203C,0x1234,0x5678)        # move.l #$12345678,d0
w(0x7200)                      # moveq #0,d1
w(0x3E3C,0x001F)               # move.w #31,d7
L('l1')
w(0x20C0)                      # move.l d0,(a0)+
w(0xD280)                      # add.l d0,d1
w(0xE798)                      # rol.l #3,d0
w(0xB380)                      # eor.l d1,d0
w(0xC0C1)                      # mulu.w d1,d0
dbf(7,'l1')
w(0x41F9,0x00FF,0x0000)        # lea $FF0000,a0
w(0x7400)                      # moveq #0,d2
w(0x3E3C,0x001F)               # move.w #31,d7
L('l2')
w(0xD498)                      # add.l (a0)+,d2
w(0xE39A)                      # rol.l #1,d2
dbf(7,'l2')
w(0x33FC,0x8104,0x00C0,0x0004) # move.w #$8104,$C00004
w(0x3639,0x00C0,0x0004)        # move.w $C00004,d3
w(0x33FC,0x0100,0x00A1,0x1100) # move.w #$100,$A11100 (Z80 bus request)
w(0x33FC,0x0100,0x00A1,0x1200) # move.w #$100,$A11200 (Z80 reset off)
L('zw')
w(0x0839,0x0000,0x00A1,0x1100) # btst #0,$A11100
bne('zw')
w(0x41F9,0x00A0,0x0000)        # lea $A00000,a0
w(0x3E3C,0x001F)               # move.w #31,d7
w(0x7A11)                      # moveq #$11,d5
L('z1')
w(0x10C5)                      # move.b d5,(a0)+
w(0x0605,0x0035)               # addi.b #$35,d5
dbf(7,'z1')
w(0x41F9,0x00A0,0x0000)        # lea $A00000,a0
w(0x3E3C,0x001F)               # move.w #31,d7
w(0x7800)                      # moveq #0,d4
L('z2')
w(0xD818)                      # add.b (a0)+,d4
w(0xE39C)                      # rol.l #1,d4
dbf(7,'z2')
w(0x43F9,0x00C0,0x0004)        # lea $C00004,a1
w(0x45F9,0x00C0,0x0000)        # lea $C00000,a2
w(0x32BC,0x8F02)               # move.w #$8F02,(a1)  autoinc 2
w(0x22BC,0x4000,0x0000)        # move.l #$40000000,(a1)  VRAM write 0
w(0x3E3C,0x000F)               # move.w #15,d7
w(0x3C3C,0x1357)               # move.w #$1357,d6
L('v1')
w(0x3486)                      # move.w d6,(a2)
w(0x0646,0x0F1D)               # addi.w #$0F1D,d6
dbf(7,'v1')
w(0x22BC,0x0000,0x0000)        # move.l #0,(a1)  VRAM read 0
w(0x3E3C,0x000F)               # move.w #15,d7
w(0x7C00)                      # moveq #0,d6
L('v2')
w(0xDC52)                      # add.w (a2),d6
w(0xE39E)                      # rol.l #1,d6
dbf(7,'v2')
# 68k -> VRAM DMA of 16 words from $FF0000 to VRAM $0100, then read back
w(0x32BC,0x8114)               # move.w #$8114,(a1)  M5 + DMA enable
w(0x32BC,0x9310)               # length 16 words
w(0x32BC,0x9400)
w(0x32BC,0x9500)               # source $FF0000 >> 1 = $7F8000
w(0x32BC,0x9680)
w(0x32BC,0x977F)
w(0x22BC,0x4100,0x0080)        # move.l #$41000080,(a1)  VRAM write $0100 + DMA
w(0x22BC,0x0100,0x0000)        # move.l #$01000000,(a1)  VRAM read $0100
w(0x3E3C,0x000F)               # move.w #15,d7
w(0x7A00)                      # moveq #0,d5
L('d1')
w(0xDA52)                      # add.w (a2),d5
w(0xE39D)                      # rol.l #1,d5
dbf(7,'d1')
w(0x84FC,0x0007)               # divu #7,d2
w(0x23C2,0x00FF,0x8000)        # move.l d2,$FF8000
w(0x23C1,0x00FF,0x8004)        # move.l d1,$FF8004
w(0x23C4,0x00FF,0x8008)        # move.l d4,$FF8008 (Z80 RAM sum)
w(0x23C6,0x00FF,0x800C)        # move.l d6,$FF800C (VRAM sum)
w(0x23C3,0x00FF,0x8010)        # move.l d3,$FF8010 (VDP status, timing dependent)
w(0x23C5,0x00FF,0x8014)        # move.l d5,$FF8014 (DMA sum)
w(0x33FC,0x600D,0x00FF,0x8020) # move.w #$600D,$FF8020
L('end')
bra('end')

words = [0] * 0x400
code = assemble(0x200)
assert 0x200 + 2 * len(code) <= 0x700
words[0:4] = [0x00FF, 0xFE00, 0x0000, 0x0200]   # SSP, PC
for v in range(2, 64):                           # all other vectors -> trap handler at $700
    words[v * 2:v * 2 + 2] = [0x0000, 0x0700]
words[0x100:0x100 + len(code)] = code
words[0x380:0x385] = [0x33FC, 0x0BAD, 0x00FF, 0x8020, 0x60FE]
open(sys.argv[1] if len(sys.argv) > 1 else 'rom.hex', 'w').write('\n'.join('%04X' % x for x in words) + '\n')
