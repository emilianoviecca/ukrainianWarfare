import numpy as np, wave, struct, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
out=sys.argv[1]; rng=np.random.default_rng(2022)
W,H=2048,1463
def noise(h,w,scales,seed=0):
    r=np.random.default_rng(seed); a=np.zeros((h,w),float); amp=1; tot=0
    for s in scales:
        g=r.random((max(2,h//s)+2,max(2,w//s)+2))
        im=Image.fromarray((g*255).astype('uint8')).resize((w,h),Image.BICUBIC)
        a+=np.asarray(im,float)/255*amp; tot+=amp; amp*=.55
    return a/tot
n=noise(H,W,[300,120,50,20,8,3],1); n2=noise(H,W,[200,70,25,9],2); fine=noise(H,W,[6,3],3)
grass=np.stack([.28+.2*n2,.29+.13*n,.16+.07*n],-1)
snow=np.array([.72,.74,.77])
m=np.clip((n-.60)*12,0,1)[...,None]
img=grass*(1-m)+snow*m
img*= (0.88+.24*fine)[...,None]
def px(x,z): return (x+350)/700*W,(z+250)/500*H
conc=Image.new('L',(W,H),0); d=ImageDraw.Draw(conc)
def rect(dr,x0,z0,x1,z1,fill): dr.rectangle([*px(x0,z0),*px(x1,z1)],fill=fill)
for r in [(-350,98,350,142),(-350,55,350,73),(-130,-55,130,55),(-210,73,-190,98),(-10,73,10,98),(190,73,210,98),(-340,-12,-130,0),(130,-22,300,-8),(-20,-190,-8,-165)]:
    rect(d,*r,255)
cm=np.asarray(conc.filter(ImageFilter.GaussianBlur(.7)),float)[...,None]/255
base=(.37+.11*n2+.05*fine)[...,None]*np.array([1,1,.97])
# lastre di cemento
yy,xx=np.mgrid[0:H,0:W]; jx=(xx*700/W%15)<.35; jz=(yy*500/H%15)<.35
base=base*(1-.28*(jx|jz))[...,None]
snowc=np.clip((n-.66)*8,0,1)[...,None]*.8; base=base*(1-snowc)+snow*snowc
img=img*(1-cm)+base*cm
pil=Image.fromarray((np.clip(img,0,1)*255).astype('uint8')); d=ImageDraw.Draw(pil,'RGBA')
Y=(232,228,214,235)
for x in range(-310,310,28): rect(d,x,119.4,x+15,120.6,Y)
for sx,xa in((1,-345),(-1,345)):
    for i in range(8):
        z=102+i*5.3
        rect(d,min(xa,xa+sx*22),z,max(xa,xa+sx*22),z+2.8,Y)
try: f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',46)
except: f=ImageFont.load_default()
for t,x,rot in(("15",-312,270),("33",312,90)):
    tm=Image.new('RGBA',(120,70),(0,0,0,0)); ImageDraw.Draw(tm).text((14,4),t,font=f,fill=Y); tm=tm.rotate(rot,expand=True)
    pil.paste(tm,(int(px(x,120)[0]-tm.width/2),int(px(x,120)[1]-tm.height/2)),tm)
d=ImageDraw.Draw(pil,'RGBA')
LY=(214,170,40,190)
for x in range(-348,348,5): rect(d,x,63.7,x+3,64.3,LY)
# crateri e bruciature
r=np.random.default_rng(7)
for i in range(46):
    x=r.uniform(-340,340); z=r.choice([r.uniform(98,142),r.uniform(-55,73),r.uniform(-240,240)]); s=r.uniform(2,6.5)
    p=px(x,z); q=s*W/700
    for k,a in((1.9,55),(1.3,110),(.8,190)):
        d.ellipse([p[0]-q*k,p[1]-q*k,p[0]+q*k,p[1]+q*k],fill=(22,20,18,a))
pil=pil.filter(ImageFilter.GaussianBlur(.5)); pil.save(f'{out}/ground.dat',format='PNG',optimize=True)
pil.resize((512,366),Image.LANCZOS).save(f'{out}/minimap.dat',format='PNG')
Image.fromarray((noise(256,256,[64,32,16,8,4,2],4)*255).astype('uint8')).save(f'{out}/detail.dat',format='PNG')
# fumo
yy,xx=np.mgrid[-1:1:64j,-1:1:64j]; a=np.clip(1-np.sqrt(xx**2+yy**2),0,1)**1.3*(0.55+.9*noise(64,64,[16,8,4],5))
s=np.zeros((64,64,4),'uint8'); s[...,:3]=255; s[...,3]=(np.clip(a,0,1)*255).astype('uint8'); Image.fromarray(s).save(f'{out}/smoke.dat',format='PNG')
# icona
ic=Image.new('RGB',(432,432),(0,87,183)); d=ImageDraw.Draw(ic); d.rectangle([0,216,432,432],fill=(255,215,0))
pl=[(216,62),(236,110),(238,185),(382,250),(382,278),(238,250),(232,322),(278,356),(278,374),(216,358),(154,374),(154,356),(200,322),(194,250),(50,278),(50,250),(194,185),(196,110)]
d.polygon(pl,fill=(245,245,240)); d.polygon([(330,226),(344,232),(344,258),(330,254)],fill=(40,40,44)); d.polygon([(102,226),(88,232),(88,258),(102,254)],fill=(40,40,44))
ic.save(f'{out}/../icon.png')
Image.new('RGB',(432,432),(0,87,183)).save(f'{out}/../icon_bg.png')
# audio
SR=22050
def save(name,x):
    x=np.clip(x,-1,1); (x*32000).astype('<i2').tofile(f'{out}/{name}.bin')
def lp(x,a):
    y=np.zeros_like(x); s=0.
    for i,v in enumerate(x): s+=a*(v-s); y[i]=s
    return y
def shot(dur,decay,tone,lpa,g=1.):
    t=np.arange(int(SR*dur))/SR; e=np.exp(-t*decay); w=lp(rng.normal(0,1,len(t)),lpa)
    b=np.sin(2*np.pi*tone*t*np.exp(-t*12))*np.exp(-t*decay*.8)
    return (w/np.abs(w).max()*.75+b*.55)*e*g
save('ak',shot(.32,20,130,.42)); save('pistol',shot(.22,30,190,.5,.8)); save('svd',shot(.75,9,80,.3,1.)); save('enemy',shot(.4,14,90,.14,1.))
t=np.arange(int(SR*1.6))/SR; w=lp(rng.normal(0,1,len(t)),.05); save('boom',(w/np.abs(w).max()*.85+np.sin(2*np.pi*48*t)*.6)*np.exp(-t*3.2))
def click(fr,dur,g=.5):
    t=np.arange(int(SR*dur))/SR; return np.sin(2*np.pi*fr*t)*np.exp(-t*90)*g+rng.normal(0,.2,len(t))*np.exp(-t*160)
save('reload',np.concatenate([click(1500,.1),np.zeros(5500),click(1000,.12),np.zeros(3000),click(1800,.1)]))
save('hit',click(2600,.07,.5)); save('step',lp(rng.normal(0,.7,1800),.2)*np.exp(-np.arange(1800)/300))
t=np.arange(int(SR*.26))/SR; save('hurt',np.sin(2*np.pi*(110-120*t)*t)*np.exp(-t*12)*.9+lp(rng.normal(0,.3,len(t)),.3)*np.exp(-t*20))
t=np.arange(int(SR*.26))/SR; save('pick',np.sin(2*np.pi*(700+900*(t>.09))*t)*np.exp(-t*11)*.45)
# ambiente e rotore in loop
L=SR*4; v=lp(rng.normal(0,1,L),.018); v=v/np.abs(v).max()*.6; f=SR//2; v[:f]=v[:f]*np.linspace(0,1,f)+v[-f:]*np.linspace(1,0,f); save('wind',v[:L-f])
L=SR*2; t=np.arange(L)/SR; pulse=(.5+.5*np.sign(np.sin(2*np.pi*12*t)))*np.exp(-((t*12)%1)*4); v=lp(rng.normal(0,1,L),.1)*pulse; save('rotor',v/np.abs(v).max()*.9)
