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

# --- VDP stress: display on, long VRAM write bursts (FIFO full -> VDP holds DTACK) ---
w(0x43F9,0x00C0,0x0004)        # lea $C00004,a1
w(0x45F9,0x00C0,0x0000)        # lea $C00000,a2
for r in (0x8004,0x8144,0x8230,0x8407,0x857C,0x8700,0x8C81,0x8F02,0x8D3F,0x9001):
    w(0x32BC, r)
w(0x22BC,0x4000,0x0000)        # VRAM write 0
w(0x3E3C,0x07FF)               # move.w #2047,d7
w(0x3C3C,0x1357)               # move.w #$1357,d6
L('v1')
w(0x3486)                      # move.w d6,(a2)
w(0x0646,0x0F1D)               # addi.w #$0F1D,d6
dbf(7,'v1')
w(0x22BC,0x4000,0x0000)        # VRAM write 0 again: long writes back to back
w(0x3E3C,0x03FF)
w(0x2C3C,0x1234,0x5678)        # move.l #$12345678,d6
L('v2')
w(0x2486)                      # move.l d6,(a2)
w(0xE39E)                      # rol.l #1,d6
dbf(7,'v2')
# work RAM $FF0000: 4096 words of pattern, then 68k->VRAM DMA of 4096 words to VRAM $4000 (display on)
w(0x41F9,0x00FF,0x0000)        # lea $FF0000,a0
w(0x3E3C,0x0FFF)
w(0x3A3C,0x2468)               # move.w #$2468,d5
L('f1')
w(0x30C5)                      # move.w d5,(a0)+
w(0x0645,0x3B5F)               # addi.w #$3B5F,d5
dbf(7,'f1')
w(0x32BC,0x8154)               # display on, M5, DMA enable
w(0x32BC,0x9300)               # length $1000 words
w(0x32BC,0x9410)
w(0x32BC,0x9500)               # source $FF0000>>1 = $7F8000
w(0x32BC,0x9680)
w(0x32BC,0x977F)
w(0x22BC,0x4000,0x0081)        # VRAM write $4000 + DMA
w(0x32BC,0x8144)               # DMA off again
# keep the CPU busy writing VRAM straight after the DMA
w(0x22BC,0x6000,0x0001)        # VRAM write $6000
w(0x3E3C,0x00FF)
L('v3')
w(0x3486)
w(0x0646,0x0F1D)
dbf(7,'v3')
w(0x22BC,0x0000,0x0000)        # VRAM read 0
w(0x3E3C,0x30FF)
w(0x7C00)                      # moveq #0,d6
L('r1')
w(0xDC52)                      # add.w (a2),d6
w(0xE39E)                      # rol.l #1,d6
dbf(7,'r1')
w(0x23C6,0x00FF,0x800C)        # move.l d6,$FF800C (VRAM sum)
w(0x33FC,0x600D,0x00FF,0x8020)
L('end')
bra('end')

words = [0] * 0x400
code = assemble(0x200)
words[0:4] = [0x00FF, 0xFE00, 0x0000, 0x0200]
for v in range(2, 64):
    words[v * 2:v * 2 + 2] = [0x0000, 0x0700]
words[0x100:0x100 + len(code)] = code
words[0x380:0x385] = [0x33FC, 0x0BAD, 0x00FF, 0x8020, 0x60FE]
open('rom_vdp.hex', 'w').write(''.join(('%04X' % x) + chr(10) for x in words))
