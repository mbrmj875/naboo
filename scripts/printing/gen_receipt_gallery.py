import json, re, glob, os, colorsys, sys
from PIL import Image, ImageStat
def shot_dark(fam,b):
    f=glob.glob(f'{F}/{fam}/{b}.png')
    if not f: return False
    im=Image.open(f[0]).convert('L'); w,h=im.size
    return ImageStat.Stat(im.crop((int(w*.3),int(h*.3),int(w*.7),int(h*.7)))).mean[0]<100
# يحوّل تصاميم ستيتش إلى قوالب المحرّك (lib/printing/receipt_gallery_data.dart).
# الألوان مقيسة من صفحات HTML (receipt_gallery_probe.json)، والهيكل من رقم الملف،
# والخط من الصفحة. التشغيل من جذر المشروع: python3 scripts/printing/gen_receipt_gallery.py
# (يحتاج Pillow) ثم: dart format lib/printing/receipt_gallery_data.dart
ROOT=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..'))
F=os.path.join(ROOT,'docs/specs/printing_shots/families')
OUT=os.path.join(ROOT,'lib/printing/receipt_gallery_data.dart')
PROBE=json.load(open(os.path.join(ROOT,'scripts/printing/receipt_gallery_probe.json')))
FAMS=['sky','sea','forest','dark','vivid','formal','contemporary','vintage']
SK=['ticketStub','sideStrip','cards','fullGrid','twoColumns','diagonalBanner','classicCentred','timeline','sealTotal','boardingPass','minimal','framedOrnate','tabbed','waveHeader','checklist','dashboard','ribbonTitles','invertedBody','magazine','certificate']
NEEDS_TOP={5,13,18}
FONTS=[('Reem Kufi','reemKufi'),('IBM Plex','plex'),('Changa','changa'),('Amiri','amiri'),('Cairo','cairo'),('Tajawal','tajawal'),('Almarai','almarai'),('Courier','amiri'),('Special Elite','amiri')]
WM=['diagonalRight','grid','diagonalLeft','vertical']
QR=['classic','squareRounded','squareCircle','squareLeaf','dots','dotsRounded','dotsCircle','dotsLeaf','soft','softCircle','softLeaf','diamond','diamondCircle','vbars','vbarsSquare','hbars','hbarsCircle','tiny','tinyLeaf','plus']

def rgb(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))
def hexs(t): return '#%02X%02X%02X'%t
def lum(h):
    def ch(v):
        v/=255; return v/12.92 if v<=0.03928 else ((v+0.055)/1.055)**2.4
    r,g,b=rgb(h); return 0.2126*ch(r)+0.7152*ch(g)+0.0722*ch(b)
def con(a,b):
    la,lb=lum(a),lum(b); return (max(la,lb)+0.05)/(min(la,lb)+0.05)
def sat(h):
    r,g,b=[v/255 for v in rgb(h)]; return colorsys.rgb_to_hls(r,g,b)[2]
def dist(a,b): return sum((x-y)**2 for x,y in zip(rgb(a),rgb(b)))**0.5
def best_on(bg, cands, need=4.5):
    for c in cands:
        if c and con(c,bg)>=need: return c
    return '#FFFFFF' if con('#FFFFFF',bg)>=con('#000000',bg) else '#000000'
def shade(h, k):
    # k<0 darker, k>0 lighter
    r,g,b=rgb(h)
    if k<0: return hexs(tuple(int(v*(1+k)) for v in (r,g,b)))
    return hexs(tuple(int(v+(255-v)*k) for v in (r,g,b)))
def ensure(c, bg, need):
    # darken/lighten c until it reads on bg
    dark = lum(bg)>0.4
    for i in range(20):
        if con(c,bg)>=need: return c
        c = shade(c, -0.12) if dark else shade(c, 0.12)
    return best_on(bg,[],need)

entries=[]; seen=set()
for fi,fam in enumerate(FAMS):
    for f in sorted(glob.glob(f'{F}/{fam}/html/{fam}_*.html')):
        b=os.path.basename(f)[:-5]
        n=int(b.split('_')[1]); sk=n-1
        P=PROBE.get(b)
        if P is None: print('skip',b,file=sys.stderr); continue
        html=open(f,encoding='utf-8').read()
        font='tajawal'
        m=re.search(r"font-family:\s*'([^']+)'",html)
        if m:
            for k,v in FONTS:
                if m.group(1).startswith(k): font=v; break
        paper=(P.get('paper') or '#ffffff').upper()
        areas=[(c.upper(),a) for c,a in P['areas']]
        texts=[c.upper() for c,_ in P['texts']]
        pa=dict(areas).get(paper,0)
        darks=[c for c,a in areas if lum(c)<0.06]
        if lum(paper)>0.5 and darks and shot_dark(fam,b):
            print('paper', b, paper, '->', darks[0], file=sys.stderr); paper=darks[0]
        # accent: strong colour (reads on paper) with most area*saturation; else strong text colour
        strong=[(c,a*(0.35+sat(c))) for c,a in areas if dist(c,paper)>40 and con(c,paper)>=2.2]
        if strong: accent=max(strong,key=lambda x:x[1])[0]
        else:
            st=[c for c in texts if con(c,paper)>=3 and sat(c)>0.25]
            accent=st[0] if st else (texts[0] if texts else '#000000')
        accent=ensure(accent,paper,3)
        ink=best_on(paper,[t for t in texts if dist(t,accent)>30]+texts,4.5)
        muted=next((t for t in texts if t not in (ink,accent) and con(t,paper)>=3.2 and dist(t,ink)>25),ink)
        onfill=[(k.split('|')[0].upper(),k.split('|')[1].upper()) for k,_ in P.get('onFill',[])]
        onA=best_on(accent,[t for fb,t in onfill if fb==accent]+['#FFFFFF','#000000'],3.2)
        pal={'accent':accent,'ink':ink,'paper':paper,'muted':muted}
        if onA!='#FFFFFF': pal['onAccent']=onA
        top=[(c.upper(),a) for c,a in P.get('top',[])]
        topBg=top[0][0] if top and dist(top[0][0],paper)>18 else None
        if sk in NEEDS_TOP and not topBg:
            topBg=accent if dist(accent,paper)>60 else shade(accent,-0.3)
        if topBg:
            pal['topBg']=topBg
            h1=(P.get('h1') or '').upper() or None
            pal['topInk']=best_on(topBg,[h1,onA,ink,'#FFFFFF','#000000'],4.5)
            # the title bar sits in the top zone: keep accent distinct from it
            if dist(accent,topBg)<40:
                alt=[c for c,_ in strong if dist(c,topBg)>60 and con(c,paper)>=3]
                if alt: accent=pal['accent']=alt[0]; pal.pop('onAccent',None); onA=best_on(accent,['#FFFFFF','#000000'],3.2)
                if onA!='#FFFFFF': pal['onAccent']=onA
        bot=[(c.upper(),a) for c,a in P.get('bot',[])]
        if bot and dist(bot[0][0],paper)>18:
            pal['bottomBg']=bot[0][0]
            pal['bottomInk']=best_on(bot[0][0],[ink,muted,'#FFFFFF','#000000'],4.5)
        th=P.get('th')
        if th and th[0]:
            hb=th[0].upper(); pal['tableHead']=hb
            pal['tableHeadInk']=best_on(hb,[(th[1] or '').upper() or None,ink,'#FFFFFF','#000000'],4.5)
        if 'tableHead' not in pal:
            r1,g1,b1=rgb(paper); r2,g2,b2=rgb(accent)
            hb=hexs((int(r1+(r2-r1)*.16),int(g1+(g2-g1)*.16),int(b1+(b2-b1)*.16)))
            pal['tableHead']=hb; pal['tableHeadInk']=best_on(hb,[ink,accent,'#FFFFFF','#000000'],4.5)
        td=P.get('td')
        if td and td[1] and td[0] not in ('0px',):
            g=td[1].upper()
            if dist(g,paper)>15: pal['grid']=g
        # QR: darkest readable of accent/ink on its real backdrop
        back=pal.get('bottomBg',paper); back = '#FFFFFF' if con(back,'#000000')<8 else back
        q=next((c for c in (accent,ink) if con(c,back)>=7),None)
        if q and q!='#000000': pal['qr']=q
        key=(sk,tuple(sorted(pal.items())))
        assert key not in seen, b; seen.add(key)
        entries.append(dict(id=b.rsplit('_',1)[0],fam=fam,n=n,sk=SK[sk],font=font,pal=pal,
            qr=QR[(sk+fi*7)%20], wm=WM[(n+fi)%4], hasWm=(P.get('wm',0)>0)))

def dart_map(p): return '{'+', '.join(f"'{k}': '{v}'" for k,v in p.items())+'}'
lines=["// مولَّد من تصاميم ستيتش (docs/specs/printing_shots/families) — لا تعدّله يدوياً.",
"// إعادة التوليد: scripts/printing/gen_receipt_gallery.py",
"library;","","import 'receipt_design.dart';","import 'receipt_gallery.dart';","import 'receipt_model.dart';","",
"const receiptGalleryData = <ReceiptGalleryEntry>["]
for e in entries:
    lines.append(f"  ReceiptGalleryEntry('{e['id']}', ReceiptGalleryFamily.{e['fam']}, {e['n']}, ReceiptSkeleton.{e['sk']}, ReceiptFont.{e['font']}, {dart_map(e['pal'])}, qr: ReceiptQrStyle.{e['qr']}"
        + (f", watermark: ReceiptWatermarkPattern.{e['wm']}, hasWatermark: true" if e['hasWm'] else '') + "),")
lines.append("];")
open(OUT,'w').write('\n'.join(lines)+'\n')
from collections import Counter
print(len(entries), Counter(e['fam'] for e in entries), Counter(e['font'] for e in entries), sum(e['hasWm'] for e in entries))
