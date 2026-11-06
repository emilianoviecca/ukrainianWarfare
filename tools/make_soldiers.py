# Dipinge le divise sulla mappa UV dei Blocky Characters di Kenney (CC0): testa dal modello originale, resto nuovo.
import numpy as np, sys
from PIL import Image, ImageDraw
base,out=sys.argv[1:3]
src=Image.open(base).convert('RGB')
def camo(w,h,pal,cell,seed):
    r=np.random.default_rng(seed); g=np.zeros((h//cell+1,w//cell+1),int)
    for _ in range(int(g.size*.09)):
        y,x=r.integers(g.shape[0]),r.integers(g.shape[1]); ry,rx=r.integers(1,4),r.integers(1,5)
        g[y:y+ry,x:x+rx]=r.integers(1,len(pal))
    a=np.array(pal,dtype='uint8')[g]
    return Image.fromarray(a).resize((w,h),Image.NEAREST)
def paint(fac):
    ua=fac=='ua'
    pal=[(88,98,58),(48,62,36),(120,112,76),(66,52,36)] if ua else [(112,104,74),(70,74,50),(50,44,32),(136,124,92)]
    im=src.copy(); d=ImageDraw.Draw(im)
    hair=(44,34,28)
    a=np.array(im); m=(a[...,0]>190)&(a[...,1]<160)&(a[...,1]>100)&(a[...,2]<120)  # capelli e baffi arancio
    m[:128]=False; m[256:]=False; m[:,512:]=False
    a[m]=hair; im=Image.fromarray(a); d=ImageDraw.Draw(im)
    tex=camo(1024,1024,pal,16,1 if ua else 2)
    for box in [(96,688,224,1024),(0,784,448,928),(480,534,544,598),(480,598,736,768),(768,534,832,598),(768,598,1024,768),(480,800,544,864),(480,864,736,1024),(768,800,832,864),(768,864,1024,1024)]:
        im.paste(tex.crop(box),box)
    skin=(245,208,160)
    for x in (480,768):
        d.rectangle([x,742,x+255,768],fill=skin); d.rectangle([x+64,534,x+127,597],fill=skin)
        band=(250,206,20) if ua else (238,238,238)
        d.rectangle([x,632,x+255,656],fill=band)
        d.rectangle([x,968,x+255,1024],fill=(34,28,24)); d.rectangle([x+64,800,x+127,863],fill=(30,26,22))
        if not ua: d.rectangle([x,885,x+255,905],fill=band)
    vest=(52,60,40) if ua else (58,56,44)
    dk=tuple(int(c*.72) for c in vest)
    for b in [(106,784,214,928),(330,784,438,928)]: d.rectangle(b,fill=vest)
    d.rectangle([96,700,224,784],fill=vest)
    for i in range(3): d.rectangle([112+i*33,860,138+i*33,918],fill=dk); d.rectangle([112+i*33,860,138+i*33,868],fill=tuple(int(c*.5) for c in vest))
    d.rectangle([350,800,418,890],fill=dk)
    d.polygon([(135,784),(185,784),(160,812)],fill=skin)
    if ua:
        d.rectangle([168,820,206,832],fill=(0,87,183)); d.rectangle([168,832,206,844],fill=(255,215,0))
    im.resize((512,512),Image.LANCZOS).save(f'{out}/soldier_{fac}.dat',format='PNG',optimize=True)
paint('ua'); paint('ru')

# --- Icone originali dei comandi (bianche/ottone su fondo trasparente) ---
S=1024; W=(244,244,236,255); G=(190,190,182,255)
def ring(d,r=470,w=16,col=W,gaps=((40,50),(130,140),(220,230),(310,320))):
    c=S/2; last=0
    for a,b in gaps:
        d.arc([c-r,c-r,c+r,c+r],last,a,fill=col,width=w); last=b
    d.arc([c-r,c-r,c+r,c+r],last,360,fill=col,width=w)
def bullet(l=620,w=150,angle=45,cx=512,cy=512,flat=False):
    B=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(B)
    x0=cx-w/2; y0=cy-l/2; case=y0+l*.40
    if flat: col=[W,W,W]
    else: col=[(232,198,120,255),(198,120,72,255),(160,150,130,255)]
    d.rectangle([x0,case,x0+w,y0+l],fill=col[0])
    pts=[(cx,y0)]+[(x0+w*t,case-(1-(abs(t-.5)*2)**2)**.5*l*.34-l*.01 if False else case-(1-(abs(t-.5)*2)**2.2)*l*.40) for t in (.5,)]
    tip=[(cx+np.sin(t)*w/2, case-np.cos(t)*l*.40) for t in np.linspace(-np.pi/2,np.pi/2,36)]
    d.polygon(tip,fill=col[1])
    d.rectangle([x0,case-l*.02,x0+w,case+l*.035],fill=(120,88,50,255) if not flat else (40,40,40,0))
    d.rectangle([x0-w*.05,y0+l*.94,x0+w*1.05,y0+l],fill=col[2])
    if not flat:
        d.rectangle([x0+w*.12,case+l*.05,x0+w*.3,y0+l*.92],fill=(250,226,170,255))
    return B.rotate(angle,resample=Image.BICUBIC,center=(cx,cy))
def save(im,n): im.resize((256,256),Image.LANCZOS).save(f'{out}/icon_{n}.dat',format='PNG',optimize=True)
# Spara: proiettile in diagonale dentro un anello
im=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(im); ring(d); im.alpha_composite(bullet(620,150,-45)); save(im,'fire')
# Ricarica: tre proiettili con freccia circolare
im=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(im); c=S/2; r=430
d.arc([c-r,c-r,c+r,c+r],-55,205,fill=W,width=44)
d.arc([c-r,c-r,c+r,c+r],235,275,fill=W,width=44)
a=np.radians(-55); p=(c+np.cos(a)*r,c+np.sin(a)*r); dirv=np.array([np.sin(a),-np.cos(a)])*-1; n=np.array([np.cos(a),np.sin(a)])
d.polygon([tuple(np.array(p)+n*92),tuple(np.array(p)-n*92),tuple(np.array(p)-dirv*-1*0+dirv*-125)],fill=W)
for x,y in ((372,548),(512,500),(652,548)): im.alpha_composite(bullet(380,92,0,x,y,flat=True))
save(im,'reload')
# Mira: mirino ad anello con tacche; la scritta la disegna il gioco
im=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(im); ring(d,r=440,w=30,gaps=((35,55),(125,145),(215,235),(305,325)))
for a,b in (((512,8),(512,130)),((512,894),(512,1016)),((8,512),(130,512)),((894,512),(1016,512))): d.line([a,b],fill=W,width=34)
save(im,'aim')
