import sys, struct, olefile
def check(f):
    olefile.OleFileIO(f, raise_defects=olefile.DEFECT_INCORRECT)
    d=open(f,'rb').read()
    o=olefile.OleFileIO(f)
    ents=[]
    raw=o._open(o.first_dir_sector, force_FAT=True).read() if hasattr(o,'_open') else None
    for k in range(len(raw)//128):
        e=raw[k*128:(k+1)*128]
        L,t,col=struct.unpack_from('<HBB',e,64); l,r,c=struct.unpack_from('<III',e,68)
        ents.append((e[:max(L-2,0)].decode('utf-16-le'),t,col,l,r,c))
    def key(n): return (len(n), n.upper())
    def sub(i):  # returns black-height, list of names in order
        if i==0xFFFFFFFF: return 1,[]
        n,t,col,l,r,c=ents[i]
        hl,a=sub(l); hr,b=sub(r)
        assert hl==hr, ('black height', n)
        if col==0:
            for ch in (l,r):
                if ch!=0xFFFFFFFF: assert ents[ch][2]==1, ('red-red', n)
        if c!=0xFFFFFFFF and t in (1,5): sub_root(c)
        return hl+(col==1), a+[n]+b
    def sub_root(i):
        _,names=sub(i)
        assert names==sorted(names,key=key), 'order'
        assert len(set(n.upper() for n in names))==len(names), 'dup'
    sub_root(ents[0][5])
    print(f,'strict + tree OK,', len(ents),'dir slots')
for f in sys.argv[1:]: check(f)
