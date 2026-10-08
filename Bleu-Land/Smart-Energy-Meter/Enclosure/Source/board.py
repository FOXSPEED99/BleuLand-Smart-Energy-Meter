import cadquery as cq, json
from collections import defaultdict
M=json.load(open('models.json')); B=json.load(open('bodies.json')); C={c['SOURCEDESIGNATOR']:c for c in json.load(open('Components6.json'))}
P=json.load(open('pads.json')); RG=json.load(open('regions.json'))
idx={}
for k,m in enumerate(M): idx.setdefault(m['ID'],k)
O=1003.937; T=1.6
def mil(s): return float(s.replace('mil',''))
padc=defaultdict(list)
for p in P:
    if p['comp']: padc[p['comp']].append((p['x'],p['y']))
def centroid(c): 
    l=padc[c]; return (sum(a for a,b in l)/len(l), sum(b for a,b in l)/len(l))
cache={}
parts=[]
for b in B:
    comp=b['comp']; side=C[comp]['LAYER']
    if b['MODEL.MODELTYPE']!='1': continue
    k=idx[b['MODELID']]
    if k not in cache: cache[k]=cq.importers.importStep('models/%d.step'%k).val()
    s=cache[k]
    s=s.rotate((0,0,0),(1,0,0),float(b['MODEL.3D.ROTX'])).rotate((0,0,0),(0,1,0),float(b['MODEL.3D.ROTY'])).rotate((0,0,0),(0,0,1),float(b['MODEL.3D.ROTZ']))
    s=s.translate((0,0,mil(b['MODEL.3D.DZ'])*0.0254))
    x=(mil(b['MODEL.2D.X'])-O)*0.0254; y=(mil(b['MODEL.2D.Y'])-O)*0.0254
    if side=='BOTTOM':
        s=s.mirror('XY')
        bb=s.BoundingBox(); cx,cy=centroid(comp)
        s=s.translate((cx-(bb.xmin+bb.xmax)/2, cy-(bb.ymin+bb.ymax)/2, 0))
    else:
        s=s.translate((x,y,T))
    # trim long THT leads below board to 2.5 mm
    bb=s.BoundingBox()
    if side=='TOP' and bb.zmin< -2.6:
        cut=cq.Solid.makeBox(400,400,100,cq.Vector(-150,-150,-102.6))
        try:
            s2=s.cut(cut); b2=s2.BoundingBox()
            if abs(b2.zmax-bb.zmax)<0.5 and abs(b2.xmax-bb.xmax)<0.5 and abs(b2.ymax-bb.ymax)<0.5 and abs(b2.ymin-bb.ymin)<0.5: s=s2
            else: print('trim skipped',comp)
        except Exception as e: print('trim fail',comp,e)
    parts.append((comp,s))
for comp in ('C9','C10'):
    cx,cy=centroid(comp); rot=float(C[comp]['ROTATION'])
    parts.append((comp,cq.Workplane().box(3.2,1.6,1.7).val().rotate((0,0,0),(0,0,1),rot).translate((cx,cy,-0.85))))
# PCB solid: 75x75 r2, slots, notch, holes
pcb=cq.Workplane('XY').box(75,75,T,centered=False).edges('|Z').fillet(2)
for r in RG:
    xs=[p[0] for p in r['pts']]; ys=[p[1] for p in r['pts']]
    w=max(xs)-min(xs); h=max(ys)-min(ys)
    cut=cq.Workplane('XY').box(w,h,10).translate(((max(xs)+min(xs))/2,(max(ys)+min(ys))/2,0))
    if min(w,h)<2: cut=cut.edges('|Z').fillet(min(w,h)/2-0.01)
    pcb=pcb.cut(cut)
for p in P:
    if p['hole']>0:
        pcb=pcb.cut(cq.Workplane('XY').circle(p['hole']/2).extrude(10).translate((p['x'],p['y'],-5)))
import pickle
cq.exporters.export(pcb,'enc/pcb_only.step')
from collections import defaultdict as dd
g=dd(list)
for c,sh in parts: g[c].append(sh)
for c,l in g.items(): cq.exporters.export(cq.Compound.makeCompound(l),'enc/comp/%s.step'%c)
comp_all=cq.Compound.makeCompound([s for _,s in parts])
cq.exporters.export(comp_all,'enc/parts_only.step')
for comp,s in parts:
    bb=s.BoundingBox()
    if comp in('R1','R2','R3','R9','RV1','C4','PS1'): print(comp,round(bb.xmin,1),round(bb.xmax,1),round(bb.ymin,1),round(bb.ymax,1),round(bb.zmin,1),round(bb.zmax,1))
bb=comp_all.BoundingBox(); print('ALL',bb.xmin,bb.xmax,bb.ymin,bb.ymax,bb.zmin,bb.zmax)
