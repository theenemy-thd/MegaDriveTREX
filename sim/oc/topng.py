import zlib, struct, sys
def topng(src, dst):
    d = open(src, 'rb').read(); i = d.index(b'255\n') + 4; px = d[i:]
    w, h = 320, 224
    raw = b''.join(b'\x00' + px[y*w*3:(y+1)*w*3].ljust(w*3, b'\x00') for y in range(h))
    def ch(t, b): return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    open(dst, 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw)) + ch(b'IEND', b''))
for f in sys.argv[1:]: topng(f, f[:-4] + '.png')
