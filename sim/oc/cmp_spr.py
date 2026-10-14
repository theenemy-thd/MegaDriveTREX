# Compares the bench's PIX runs (stdin) with spr2_ref.txt. Prints per-line match.
import sys
ref = {}
for l in open('spr2_ref.txt'):
    a = l.split(); ref[int(a[0])] = a[1:]
lines, cur, bad = {}, [], 0
for l in sys.stdin:
    if l.startswith('PIX'):
        f = dict(kv.split('=') for kv in l.split()[1:])
        rgb = int(f['rgb'], 16); r, g, b = rgb >> 16, (rgb >> 8) & 255, rgb & 255
        lv = lambda v: round(v * 7 / 255)
        if rgb == 0: tok = '-'
        else: tok = '%d.%d' % (1 if lv(g) == 7 else 0, lv(r) | (lv(b) << 3))
        cur += [tok] * int(f['n'])
    elif l.startswith('LINEDONE'):
        ln = int(l.split()[1].split('=')[1]); lines[ln] = cur; cur = []
for ln in sorted(lines):
    got, exp = lines[ln], ref.get(ln)
    diff = [i for i in range(min(len(got), len(exp))) if got[i] != exp[i]]
    vis = sum(1 for t in exp if t != '-')
    print('line %d: %s (ref pixels %d, sim width %d)%s' % (ln, 'OK' if not diff and len(got) == len(exp) else 'DIFF', vis, len(got),
          '' if not diff else ' first diffs at x=%s got=%s exp=%s' % (diff[:6], [got[i] for i in diff[:6]], [exp[i] for i in diff[:6]])))
    bad += bool(diff)
print('BAD LINES', bad)
