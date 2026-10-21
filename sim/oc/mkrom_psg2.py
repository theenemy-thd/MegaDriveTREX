# PSG write burst: tones on with full volume, then all four volumes off with back-to-back
# move.b writes (as games do at scene changes). The bench prints the PSG volume latches at the
# end ($600D); all four must be F (silent).
import sys, os
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'mkrom.py')).read()
exec(src[:src.index('# --- program ---')])

w(0x41F9,0x00C0,0x0011)          # lea $C00011,a0
for b in (0x80, 0x00, 0x9F, 0xA0, 0x00, 0xBF, 0xC0, 0x00, 0xDF, 0xE0, 0x00, 0xFF):   # Earthion $413F6
    w(0x10BC, b)                 # move.b #b,(a0)
w(0x3E3C,0x0100)
L('d1')
dbf(7,'d1')
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
open('rom_psg2.hex', 'w').write(''.join(('%04X' % x) + chr(10) for x in words))
print('ok')
