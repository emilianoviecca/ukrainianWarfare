# Converte un carro Quaternius (CC0, GLB già decompresso e con scheletro) in geometria statica
# con colori per vertice, così sulla mappa si fonde con il resto in un'unica chiamata di disegno.
# Uso: bake_vehicle.py sorgente.glb destinazione.bin lunghezza_in_metri
import json,struct,sys
import numpy as np
src,dst,LEN=sys.argv[1],sys.argv[2],float(sys.argv[3])
b=open(src,'rb').read(); jl=struct.unpack('<I',b[12:16])[0]; g=json.loads(b[20:20+jl]); bin0=b[20+jl+8:]
CT={5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'}; NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def acc(i):
    a=g['accessors'][i]; bv=g['bufferViews'][a['bufferView']]; n=NC[a['type']]; dt=np.dtype('<'+CT[a['componentType']])
    o=bv.get('byteOffset',0)+a.get('byteOffset',0); st=bv.get('byteStride',dt.itemsize*n)
    if st==dt.itemsize*n: return np.frombuffer(bin0,dtype=dt,count=a['count']*n,offset=o).reshape(-1,n).astype(float)
    return np.stack([np.frombuffer(bin0,dtype=dt,count=n,offset=o+i2*st) for i2 in range(a['count'])]).astype(float)
def local(n):
    if 'matrix' in n: return np.array(n['matrix']).reshape(4,4).T
    t=np.array(n.get('translation',[0,0,0]),float); q=n.get('rotation',[0,0,0,1]); s=np.array(n.get('scale',[1,1,1]),float)
    x,y,z,w=q; R=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
    M=np.eye(4); M[:3,:3]=R*s; M[:3,3]=t; return M
world={}
def walk(i,P):
    world[i]=P@local(g['nodes'][i])
    for c in g['nodes'][i].get('children',[]): walk(c,world[i])
for r in g['scenes'][g.get('scene',0)]['nodes']: walk(r,np.eye(4))
def lin2srgb(c): c=np.clip(c,0,1); return np.where(c<=.0031308,c*12.92,1.055*c**(1/2.4)-.055)
P=[];N=[];C=[]
for i,nd in world.items():
    node=g['nodes'][i]
    if 'mesh' not in node: continue
    for pr in g['meshes'][node['mesh']]['primitives']:
        at=pr['attributes']; pos=acc(at['POSITION']); nor=acc(at['NORMAL']) if 'NORMAL' in at else None
        idx=acc(pr['indices']).astype(int).ravel() if 'indices' in pr else np.arange(len(pos))
        if 'skin' in node and 'JOINTS_0' in at:
            sk=g['skins'][node['skin']]; ibm=acc(sk['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
            J=np.stack([world[j]@ibm[k] for k,j in enumerate(sk['joints'])])
            jt=acc(at['JOINTS_0']).astype(int); wt=acc(at['WEIGHTS_0'])
            M=(J[jt]*wt[...,None,None]).sum(1)
            hp=np.c_[pos,np.ones(len(pos))]; wp=np.einsum('nij,nj->ni',M,hp)[:,:3]
        else:
            M=np.broadcast_to(world[i],(len(pos),4,4)); wp=(pos@world[i][:3,:3].T)+world[i][:3,3]
        tri=wp[idx].reshape(-1,3,3)
        fn=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]); fl=np.linalg.norm(fn,axis=1,keepdims=True); keep=fl[:,0]>1e-9; tri=tri[keep]; fn=fn[keep]/fl[keep]
        m=g['materials'][pr['material']]; col=np.array(m['pbrMetallicRoughness'].get('baseColorFactor',[1,1,1,1])[:3])
        P.append(tri); N.append(fn); C.append(np.broadcast_to(col,(len(tri),3)))
P=np.concatenate(P);N=np.concatenate(N);C=np.concatenate(C)
mn=P.reshape(-1,3).min(0); mx=P.reshape(-1,3).max(0); size=mx-mn; print('dim originali',size)
horiz=[0,2]; long_ax=horiz[int(size[2]>size[0])]
# Asse lungo su Z, base a terra, centrato.
ctr=(mn+mx)/2; P=P-[ctr[0],mn[1],ctr[2]]
if long_ax==0:
    P=P[...,[2,1,0]]*[1,1,-1]; N=N[...,[2,1,0]]*[1,1,-1]
k=LEN/(P[...,2].max()-P[...,2].min()); P=P*k
# Godot vuole i triangoli in senso orario: inverte l'ordine.
P=P[:,[0,2,1]]
n3=np.repeat(N,3,axis=0); col=lin2srgb(C); r=np.random.default_rng(3)
# Variante bruciata: quasi nera con chiazze di ruggine e fuliggine, per triangolo.
t=r.random(len(col))[:,None]; burnt=np.where(t<.05,[.20,.135,.095],np.where(t<.4,[.125,.118,.11],[.085,.082,.078]))*(.85+.3*r.random(len(col)))[:,None]
def rgba(c): return np.c_[np.repeat(c,3,axis=0),np.ones(len(c)*3)]
h=P[...,1].max(); w=P[...,0].max()-P[...,0].min(); L=P[...,2].max()-P[...,2].min()
with open(dst,'wb') as f:
    f.write(struct.pack('<ifff',len(P)*3,w,h,L)); f.write(P.reshape(-1,3).astype('<f4').tobytes()); f.write(n3.astype('<f4').tobytes()); f.write(rgba(col).astype('<f4').tobytes()); f.write(rgba(burnt).astype('<f4').tobytes())
print(dst,'triangoli',len(P),'dimensioni l/a/L %.2f %.2f %.2f'%(w,h,L))
