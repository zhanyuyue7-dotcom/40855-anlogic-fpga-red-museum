param([string]$PythonExe="", [string]$IcarusBin="D:\EDA\iverilog\bin")
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try{
 $py=$PythonExe
 if(-not $py){$py=Join-Path $root 'desktop/.venv/Scripts/python.exe'}
 if(-not (Test-Path -LiteralPath $py)){throw 'Create desktop/.venv or pass -PythonExe with the desktop requirements installed.'}
 [System.IO.Directory]::CreateDirectory((Join-Path $root 'diagnostics')) | Out-Null
 $env:IVERILOG_BIN=$IcarusBin
 $iv=Join-Path $IcarusBin 'iverilog.exe';$vvp=Join-Path $IcarusBin 'vvp.exe'
 $s='src/user_source/hdl_source'
 $cases=@(
  @{Name='glyph-mapping';Top='glyph_mapping_tb';Files=@('tests/glyph_mapping_tb.v','reference/equivalence/osd_glyph_rom_bram_ref.v','reference/equivalence/osd_glyph_rom_24_bram_ref.v',"$s/osd_glyph_rom.v","$s/osd_glyph_rom_24.v")},
  @{Name='web-rom';Top='web_rom_tb';Files=@('tests/web_rom_tb.v',"$s/network/w5500_web_rom.v")},
  @{Name='image-udp';Top='w5500_image_udp_tb';Files=@('tests/w5500_image_udp_tb.v',"$s/network/w5500_image_udp.v")},
  @{Name='frame-bridge';Top='hxfp_frame_bridge_tb';Files=@('tests/hxfp_frame_bridge_tb.v',"$s/network/hxfp_frame_bridge.v","$s/IP/afifo_16_32_256.v")},
  @{Name='ui-blend';Top='ui_blend_equivalence_tb';Extra='-i';Files=@('tests/ui_blend_equivalence_tb.v',"$s/subtitle_osd.v")},
  @{Name='audio-reader';Top='audio_pcm_raw_reader_tb';Files=@('reference/donor-tests/audio_pcm_raw_reader_tb.v',"$s/audio_pcm_raw_reader.v")},
  @{Name='audio-count';Top='audio_count_equivalence_tb';Files=@('tests/audio_count_equivalence_tb.v','reference/equivalence/audio_pcm_raw_reader_ref.v',"$s/audio_pcm_raw_reader.v")},
  @{Name='image-address';Top='image_write_address_tb';Files=@('tests/image_write_address_tb.v',"$s/SD/frame_fifo_write.v")},
  @{Name='bmp-handshake';Top='bmp_write_handshake_tb';Files=@('reference/donor-tests/bmp_write_handshake_tb.v',"$s/SD/bmp_read.v")},
  @{Name='fft-equivalence';Top='fft_equivalence_tb';Files=@('tests/fft_equivalence_tb.v','reference/equivalence/fft_ref.v','reference/equivalence/fft_ram_ref.v','reference/equivalence/spectrum_hann_rom.v','reference/equivalence/spectrum_twiddle_rom.v',"$s/spectrum_fft_1024.v","$s/spectrum_sync_ram_1024.v","$s/spectrum_hann_rom.v","$s/spectrum_twiddle_rom.v")},
  @{Name='boot-equivalence';Top='boot_equivalence_tb';Files=@('tests/boot_equivalence_tb.v','reference/equivalence/boot_ref.v',"$s/boot_video_stream.v")}
 )
 foreach($case in $cases){
  $binary='diagnostics/'+$case.Name+'.vvp'
  $argsList=@('-g2012','-s',$case.Top,'-o',$binary)
  if($case.Extra){$argsList+=$case.Extra}
  $argsList+=$case.Files
  & $iv @argsList
  if($LASTEXITCODE -ne 0){throw ('Compile failed: '+$case.Name)}
  & $vvp $binary | Tee-Object -FilePath ('diagnostics/test-'+$case.Name+'.log')
  if($LASTEXITCODE -ne 0){throw ('Simulation failed: '+$case.Name)}
 }
 & $py fpga_upload/tests/run_cosim.py
 if($LASTEXITCODE -ne 0){throw 'HXFP cosimulation failed'}
 Push-Location desktop
 try{& $py -m unittest test_desktop test_report test_fpga_transfer -v;if($LASTEXITCODE -ne 0){throw 'Desktop tests failed'}}finally{Pop-Location}
}finally{Pop-Location}
