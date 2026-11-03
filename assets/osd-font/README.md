# E1 固定字模

字模来源为本机已有的 Adobe 思源黑体 CN Regular，源字体保持上游名称与归属，许可见 `LICENSE.txt`。
`manifest.json` 记录源 OTF 的 SHA256、栅格化参数和字模编号。
本工程仅嵌入少量固定字模，不分发完整 OTF。

16×16、1bpp，屏幕上最近邻放大 2 倍至 32×32。`glyphs.hex` 为 512 行，
每行 16 bit，最高位为左侧像素。`osd_glyph_rom.v` 是同一数据的同步 ROM 代码，
不依赖运行时文件路径；字模编号和行号输入后，下一拍得到该行。

复现（使用已有 Pillow 环境，不向全局安装依赖）：

```powershell
& 'D:\Downloads\contentcreater-resources\bluetooth\pc-helper\.venv-package312\Scripts\python.exe' `
  .\tools\generate_osd_font.py --font 'D:\Downloads\contentcreater-resources\desksense-xiaozhi-console\assets\fonts\source-han-sans\SourceHanSansCN-Regular.otf'
```

`preview.png` 是字体和布局检查用的本机预览，不代表板上显示证据。
