# Prerecorded Spectrum Animation

This is a visual loop extracted from a user-provided video, not an FFT result or
an audio-reactive spectrum. It is not synchronized to the FPGA PCM playback.
The video's dark matte and audio track are discarded. Music playback remains
the existing, separate PCM path.

`manifest.json` records the source hash, extraction settings and logical height
data hash. Keep the original video on the user's desktop; it is not committed.
The extraction uses Python 3 with NumPy and Pillow and a local FFmpeg executable.

Data contract:

- `heights.hex`: one unsigned 8-bit height per line, frame-major, then bar-major.
  Address = frame index * 64 + bar index. 512 frames * 64 bars = 32768 bytes.
- `palette.hex`: 64 fixed RGB24 colors, one six-digit RGB hex value per line.
- Display is 640x480; bar stride is 10 pixels, width 9, transparent gap 1.
  Bars are bottom-aligned and at most 240 pixels tall. Zero height is invisible.
- Global peak normalization preserves relative heights across frames. The final
  12 frames are blended toward frame zero. The loop is 34.1333 seconds at 15 fps,
  truncating roughly 0.73 seconds from the source recording's end.
- GIF/contact-sheet/transparent PNG previews live in ignored
  `artifacts/spectrum-preview/`. Without `--background`, the checkerboard is only
  a transparency demonstrator; it does not represent the physical board image.

Reproduce from the repository root:

```powershell
& 'E:\python\python.exe' -X utf8 tools/extract_spectrum_animation.py `
  'C:\Users\ZhuanZ（无密码）\Desktop\屏幕录制 2026-10-07 081008.mp4' `
  --ffmpeg 'C:\Users\ZhuanZ（无密码）\AppData\Local\JianyingPro\Apps\10.7.0.14095\ffmpeg.exe'
& 'E:\python\python.exe' -m unittest discover -s tests -p test_spectrum_animation.py
```

The final Speed candidate has passed FPGA resource and timing validation with
the banked organization below. It was downloaded to volatile SRAM and the user confirmed the basic
visual/control/music checks. Flash persistence and a new long run are not claimed.

The Speed RTL build stores the same height stream as eight generated 4096x8
MIF banks under `work/lab_ex5_i2s/src/user_source/hdl_source/`. The banked
organization is intentional: the target's 9K BRAM mapping is reproducible and
avoids turning the asynchronous 32 KiB lookup into LUTs. The validated Speed
candidate uses 54 of 64 available 9K BRAMs. The build/resource result is distinct from the recorded SRAM transfer
and user-confirmed basic visual acceptance; see SPEED_SPECTRUM_ACCEPTANCE_2026-10-07.md.
