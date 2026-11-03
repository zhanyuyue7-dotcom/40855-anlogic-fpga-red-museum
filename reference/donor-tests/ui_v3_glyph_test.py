"""Character-level checks; catches shared font/oracle missing-glyph false positives."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib, json, re, unittest, subprocess, sys
ROOT=Path(__file__).resolve().parents[1]
IDS=list(dict.fromkeys(" 场景普通轮播提示紧急等级012346运行等待空闲扫描加载未知亮度57%调节历史回顾不忘初心牢记使命89-:正常|状态"))
def bitmap(font,char,size):
    im=Image.new('L',(size,size))
    ImageDraw.Draw(im).text((size/2,size/2),char,font=font,fill=255,anchor='mm')
    return [sum((im.getpixel((x,y))>=128)<<(size-1-x) for x in range(size)) for y in range(size)]
def inspect(size):
    folder=ROOT/f'assets/osd-font-{size}'
    m=json.loads((folder/'manifest.json').read_text(encoding='utf8'))
    path=ROOT/m['font_path'] if 'font_path' in m else Path('C:/Windows/Fonts')/m['font_file']
    font=ImageFont.truetype(str(path),size)
    missing=bitmap(font,chr(0x10ffff),size)
    rows=[int(x,16) for x in (folder/'glyphs.hex').read_text().split()]
    rtl=(ROOT/f'work/lab_ex5_i2s/src/user_source/hdl_source/osd_glyph_rom_{size}.v').read_text()
    assignments=re.findall(r"mem\[(\d+)\] = \d+'h([0-9a-f]+)",rtl)
    rom={int(a):int(v,16) for a,v in assignments}
    bad=[]; mapping=[]
    for g in m['glyphs']:
        start=g['id']*size; actual=rows[start:start+size]
        record=dict(g,rom_start=start,rom_end=start+size-1,nonzero=any(actual),missing_glyph=actual==missing,font_match=actual==bitmap(font,g['character'],size),rom_match=actual==[rom.get(a) for a in range(start,start+size)])
        mapping.append(record)
        if record['missing_glyph']: bad.append(g['character'])
    return dict(size=size,font_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),manifest_hash=m['font_sha256'],mapping=mapping,missing=bad)
class GlyphTests(unittest.TestCase):
    def test_character_identity_coverage_and_rom(self):
        for size in (20,24):
            e=inspect(size)
            self.assertEqual(e['font_sha256'],e['manifest_hash'])
            self.assertEqual([(g['id'],g['character']) for g in e['mapping']],list(enumerate(IDS)))
            for g in e['mapping']:
                self.assertTrue(g['font_match'] and g['rom_match'],g)
                if g['character']!=' ': self.assertTrue(g['nonzero'],g)
            self.assertEqual(e['missing'],[],f"{size}px missing glyphs: {e['missing']}")
    def test_incomplete_font_rejected_without_modifying_outputs(self):
        bad_font=Path('C:/Windows/Fonts/SourceHanSansJP-Normal.otf')
        if not bad_font.exists(): self.skipTest('Original local regression font not installed')
        outputs=[ROOT/f'assets/osd-font-{sz}/{name}' for sz in (20,24) for name in ('glyphs.hex','manifest.json')]
        outputs += [ROOT/f'work/lab_ex5_i2s/src/user_source/hdl_source/osd_glyph_rom_{sz}.v' for sz in (20,24)]
        before=[p.read_bytes() for p in outputs]
        result=subprocess.run([sys.executable,str(ROOT/'tools/generate_revolutionary_osd_font.py'),'--font',str(bad_font)],capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn(b'Missing/empty glyphs',result.stderr+result.stdout)
        self.assertEqual(before,[p.read_bytes() for p in outputs])
if __name__=='__main__': unittest.main()
