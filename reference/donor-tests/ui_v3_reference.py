"""Independent v3 pixel oracle. Not imported by RTL/font production generators.
Produces synthetic-background references, NOT board photographs.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib, json, sys
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'artifacts/ui-v3-verification'
FONT = ROOT/'assets/osd-font-ui-source/SourceHanSansCN-Normal.otf'
for manifest_path in (ROOT/'assets/osd-font-20/manifest.json', ROOT/'assets/osd-font-24/manifest.json'):
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    if hashlib.sha256(FONT.read_bytes()).hexdigest() != manifest['font_sha256']:
        raise SystemExit(f'Font hash mismatch: {manifest_path}')
CASES = [(0,0,0,0),(0,1,1,1),(0,2,2,0),(0,3,3,1),(0,4,0,0),(0,15,3,1),(1,4,2,1),(2,2,1,0),(0,4,2,1)]
CREAM=(245,230,211); RED=(139,0,0); GOLD=(212,175,55); INK=(62,39,35)
def cell(char,size):
    im=Image.new('L',(size,size)); ImageDraw.Draw(im).text((size/2,size/2),char,font=ImageFont.truetype(str(FONT),size),fill=255,anchor='mm')
    return im.point(lambda v:255 if v>=128 else 0)
def reference(st,br,mode):
    im=Image.new('RGB',(640,480)); im.putdata([(y%256,x%256,90) for y in range(480) for x in range(640)])
    d=ImageDraw.Draw(im)
    d.rectangle((0,0,639,35),fill=CREAM); d.rectangle((0,408,639,479),fill=CREAM)
    for y in (35,408,440): d.line((0,y,639,y),fill=RED)
    for x in (155,410): d.line((x,450,x,473),fill=RED)
    d.rectangle((260,456,379,463),fill=RED); d.rectangle((262,458,377,461),fill=CREAM)
    d.rectangle((262,458,262+[29,58,87,116][br]-1,461),fill=RED)
    def put(c,x,y,size,color=INK,crop=None):
        mask=cell(c,size)
        if crop: mask=mask.crop((crop[0],0,crop[1],size))
        im.paste(color,(x,y),mask)
    for c,x in zip('场景历史回顾等级0',[20,44,76,100,124,148,200,224,256]): put(c,x,8,24)
    for c,x in zip('不忘初心牢记使命',[220,244,268,292,324,348,372,396]): put(c,x,414,24,GOLD)
    for i,c in enumerate('运行状态'): put(c,20+20*i,452,20)
    put(':',100,452,20,crop=(5,15))
    state={0:'等待',1:'空闲',2:'扫描',3:'等待',4:'加载'}.get(st,'未知')
    for i,c in enumerate(state): put(c,110+20*i,452,20)
    for i,c in enumerate('亮度'): put(c,212+20*i,452,20)
    for i,c in enumerate('调节' if mode else '运行'): put(c,450+20*i,452,20)
    return im
if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    for n,(sc,st,br,mode) in enumerate(CASES):
        if sc: continue
        im=reference(st,br,mode)
        (OUT/f'expected-{n}.hex').write_text(''.join('%02x%02x%02x\n'%p for p in im.get_flattened_data()),encoding='ascii')
        im.save(OUT/f'expected-{n}.png')
    print('Generated seven complete ordinary-frame references; two alert frames use legacy equivalence.')
