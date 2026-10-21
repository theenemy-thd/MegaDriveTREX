import struct, math, sys
def load(d):
    raw=open(d+'/audio.raw','rb').read()
    n=len(raw)//4
    return [struct.unpack_from('<hh',raw,i*4)[0] for i in range(n)]
def fstart(k): return int((52074526 + (k-30)*1789300)/2048)
def peak(x):
    N=len(x); m=sum(x)/N; x=[v-m for v in x]
    rms=math.sqrt(sum(v*v for v in x)/N)
    best=(0,0)
    for f in range(100,12000,50):
        w=2*math.pi*f/52437; c=2*math.cos(w); s1=s2=0
        for v in x: s0=v+c*s1-s2; s2=s1; s1=s0
        p=s1*s1+s2*s2-c*s1*s2
        if p>best[0]: best=(p,f)
    return rms, best[1], math.sqrt(best[0])/N*2
d=sys.argv[1]; a=load(d); k0=int(sys.argv[2]); k1=int(sys.argv[3])
for k in range(k0,k1,int(sys.argv[4])):
    s=fstart(k); x=a[s:s+1024]
    if len(x)<1024: break
    r,f,amp=peak(x)
    print(d,k,'rms %6.0f peak %5d Hz amp %6.0f'%(r,f,amp))
