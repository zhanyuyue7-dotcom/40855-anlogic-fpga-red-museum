# Integration work — 2026-11-02

## CURRENT AUTHORITY — 2026-11-02, successful SRAM retry

TIMING CLOSED, BITSTREAM FROZEN, AUTHORIZED SRAM DOWNLOAD SUCCEEDED.
See `TIMING_CLOSED_2026-11-02.md` for complete evidence and exact next step.
Successful run `build/physical-retries/541d-routability`: Setup+0.156/0ns,
Hold+0.022/0ns,coverage99.97%,48/32 SDRAM endpoints checked, LUT84.05%.
Bit SHA256625d0b2d7974b01f5d138eef0ae82afd547d5584011d1e3d4a1fb04416900b76.
Full current regressions pass (including30 desktop tests). Picture/audio/buttons
passed by user confirmation. No real Ethernet transfer claim.
Frozen artifacts/source at `artifacts/integrated-timing-closed-20261102`.
First SRAM attempt13:53 failed with USB-9/-4/-1 and exit1 despite100%/Done.
After user-confirmed replug, retry1 passed: unique JTAG,100%/Done,exit0,no USB error.
Success receipt `diagnostics/final-sram-receipt-retry1.json`; log
`diagnostics/final-sram-download-retry1.log`. No Flash/TF writes, no SRAM readback.
tools/build.tcl now defaults to the successful routability strategy. This final
driver-only change was made AFTER artifact freezing/download, so the original
inputs.json binds the historical driver; successful retry.tcl is frozen alongside
the bitstream. Hardware source/constraints remain identical to the frozen snapshot.
No TD processes should remain active. Older running states below are historical.
No Word/PDF edits; no push/merge. User prefers present functionality and zero timing
violations over further numerical resource-target tuning.

## Takeover checkpoint (2026-11-02, current conversation)

### Latest user-confirmed acceptance and current run

- 13:34 update: user explicitly prioritizes avoiding timing penalties. Do not
  download with negative setup/hold, relax clocks or cut functional paths.
  ec627 final routed LUT17557/19600 (89.58%), SWNS-1.739/STNS-32.881ns,
  HWNS+0.030/HTNS0ns. NO bitgen/download. Post-route phys_opt reproduced TD crash
  from its saved final.db; see build/post-route/ec627-high, no artifacts lost.
- Current run541d2c577e3b4eed-20261102-133428-305205, attempt-01.log full build.
  Changes: CHECK-stage HXFP dispatch predicates, preselected next audio song
  descriptor,24px glyph restored to identical BRAM mapping to relieve congestion.
  Audio16600-word cycle comparison and exhaustive glyph/latency comparison pass.
  HXFP full regression running in diagnostics/hxfp-predecode-regression.log.
  Initial848e attempt was deliberately stopped after Icarus found declaration
  order errors; those are fixed and compile passes. Do not use that run.

- 13:15 current: user is satisfied with the present resource/function tradeoff;
  stop tuning just to reach a percentage and finish timing/build/SRAM on it.
  Run ec627ee7b299b85a-20261102-130902-287232 passed placement. Area-priority
  mapping + high gate packing reduced physical MSlices5334 ->4782 /4900.
  Gate LUT16753/19600 (85.47%) is NOT the final routed count. Full physical packing
  occupancy and LUT utilization are different metrics; do not interchange them.
  attempt-02.log is now routing from the hash-verified place checkpoint.
  attempt-01 took345.738s for synthesis+placement. No additional RTL edits pending.

- User confirms the integrated version INCLUDING HXFP image reception passed
  picture, sound and button checks. Project functional acceptance for those three
  items is PASSED by user confirmation; do not ask for duplicate testing or
  distinguish the test device in user-facing acceptance summaries.
- This confirmation does not claim a real Ethernet image-transfer test, nor a
  hash match to the still-building local timing/resource iteration. Keep build
  and programming receipts factual. No report editing is authorized.
- Current physical retry: build/physical-retries/20261102-130545-more_lut_pair,
  reuses SHA256-verified gate from run 8ac7a36f1dd3997a-20261102-125824-569611.
  Same RTL/SDC, only pack_mode changed to more_lut_pair. Prior adaptive packing
  required 5334 MSlices / 4900 despite gate LUT 18000/19600 (91.84%).
- The preceding 84.61% routed attempt closed hold at +0.021ns but failed setup
  -2.857ns. Subsequent fixes: registered BMP header capture, bytewise audio-zero
  flags, standard-read vendor image FIFO with buffered output/backpressure.
  Real vendor FIFO regression passes; all 1,228,800 addresses across four image
  banks pass; 16,600 PCM words match baseline cycle by cycle, including borrow
  boundaries and zero-length songs. Prior protocol/FFT/boot/software tests pass.
- 24px + legacy glyph LUT mappings free 8 BRAM9K; exhaustive glyph equivalence
  passes. Gate BRAM9K now 41/64; BRAM32K 8/16; DSP21/29.
- Found predecessor's HTTP ROM path warning HDL-5105; fixed source-relative
  path, all2071 HTTP bytes pass simulation. Missing ROM files now stop builds.

- User explicitly confirmed ownership of board receiver, complete integrated
  build, timing and SRAM board validation. Actual LUT target near 94.6% remains.
- User excluded report layout/photos entirely; report text changes require prior
  approval. Word/PDF have only been read; NO report mutations were made.
- Snapshot: diagnostics/takeover-20261102-122526 (source/tools/tests zip,
  tracked diff, prior state, log and timing report).
- Prior 03:44 attempt routed then crashed in phys_opt; its real final_timing.rpt
  was SWNS -0.647ns / STNS -2.502ns / HWNS -1.540ns / HTNS -3.417ns.
  build/integrated route/bit files are older, not that candidate's output.
- Added hash-verified stages, per-run outputs/receipts, exclusive build lock,
  gate-only check, resource overflow rejection, route checkpoint before optional
  phys_opt and negative-timing bitgen rejection. High placement effort retained.
- Fresh gate 93.265s; verified identical gate cache hit 0.652s wall. Changed input
  and corrupt/missing checkpoint tests pass. No blanket full-build speedup claim.
- Fixed audio header comparison enable path and cycle-preserving boot timeout
  precomputation; added narrowly reviewed hold exceptions on first stages only:
  image display_bank_sd[0], display_ack_sd[0], image_boot_sync[0].
- Seven integration simulations, 1226 HXFP cases / 614912 pixels, and 30 desktop
  tests pass in diagnostics/regression-takeover.log. Network hardware untested.
- Active TD run: build/runs/266ed7cf5fcf3282-20261102-123023-033464, attempt-02.log,
  resumed from gate, process 37600 at last check, routing. Do not modify source
  or start another TD writer while it runs. Gate LUT 15979/19600 (81.53%).
- USB Code0 and unique JTAG EG4S20BG256/0x0a014c35 detect passed again; log:
  diagnostics/takeover-jtag-detect.log. Loader available D:/msys64/ucrt64/bin.
  D:/EDA/Download-guide.md and old loader path absent on this host; project
  FPGA_DOWNLOAD.md read. Backup manifest is host-specific 9e7ad654...8a27f;
  independently verify full backup and reread slices before any SRAM transfer.
- No physical UART currently enumerated (Bluetooth COM25/26 only); no new SRAM
  download yet. Real Ethernet remains excluded while router is off.

The earlier section below is historical; its running-session IDs are obsolete.

User scope: combine teammate FPGA repo and local host/HXFP, repair timing, build
and verify on connected board without real Ethernet transfer (router off).
LUT utilization must come from actual TD reports; no 90–94% padding.

Baseline fetched: f8f8793c878983634fe5d0ae53f4e6d2b8ee0418.
Teammate already has boot video, real FFT, HTTP and W5500 optimizations.
HXFP network endpoint and safe frame-buffer ownership are missing.
Donor protocol receiver includes CRC/session/ACK/backpressure/commit tests.

JTAG detect succeeds: one EG4S20BG256, 0x0a014c35. No physical UART enumerated;
only Bluetooth COM25/26. Flash/TF not written. Existing Flash backup is at
D:/FPGA/shunying/backups/before-first-sram (hash must be independently checked).

Current step (2026-11-02 ~03:10): full merged build routing, PID/session tracked
in active Codex. Latest exec build session 57204, diagnostics/build-integrated.log.
Do not start a second TD writer to the same output directory.

Findings and changes:
- Untouched teammate baseline fails placement: gate utilization 28006/19600 LUT,
  physical 21261 LUT nodes +3007 slices, not the ~75% historical report.
- Large arrays were inferred into logic. Converted band-power to sync RAM,
  boot byte/line buffers to synchronous prefetch RAM, glyph ROMs to documented
  rom_style=bram; Hann/twiddle synchronous coefficient reads preserve phase use.
- FFT bit-exact original/optimized comparison passes silence, antiphase stereo
  tones and DC bias. Boot producer pixel-by-pixel comparison passes complete 2x2.
- Blend rewritten as under*32+(over-under)*gain; 2162688 exhaustive combinations
  match the former arithmetic. No display-feature reduction or filler logic.
- HXFP uses sync packet RAM and shared CRC byte datapath. 1226 packet scenarios,
  614912 pixel writes and one display commit pass.
- W5500 socket2/UDP5002 transport added, ring-wrap/peer ACK routing test passes.
- Frame bridge reserves offscreen boot bank after boot finishes, pauses new TF
  scheduling, FIFO backpressure, memory-drain and frame/read-ACK COMMIT, abort
  writer-only reset, top-down image writes. Bridge test passes.
- Merged Windows donor source/report data/tools; 30 software regressions pass.
- Current gate area ~16093 LUT /19600 (82.11%), 64 BRAM9K,21DSP; must wait for
  routed values and closure. Earlier memory-optimized pre-upload build routed
  at16187 LUT but setup -2.332ns,hold -1.540ns; not downloaded.
- tools/pipeline_sd_checks.py prepared but NOT YET APPLIED: register SD header
  and song-empty paths, precise existing boot CDC first-stage hold exceptions.
- TD manual says route fix_hold defaults OFF. Enable set_param route fix_hold on;
  phys_opt -post_route -effort high and fix_hold are documented commands.

Next: finish/inspect current routed report; preserve output snapshot; apply
SD pipeline fixes, enable hold repair, address real critical paths; rebuild.
Run relevant donor audio/image tests and packet/FFT/UI/boot/bridge tests before
any SRAM. Backup independently hashes to9e7ad654beb708b1f22e8bd3aafed6d8c7b8f040f20f591d9259e83beac8a27f
matching its own backup.json (different from older host-specific hash).
JTAG unique detect succeeds; physical UART absent (Bluetooth only).

Outstanding user document work: live file is
C:/Users/41116/output/doc/瞬应逻辑队_红色数字展馆_作品设计报告_精简排版定稿.docx
user edited since generated scripts; do NOT regenerate from old drafts.
Photos now stacked full-width by Word COM (checkpoint in output/doc/checkpoints),
20 pages, photo1 p13/photo2 p14. Need remove large gaps locally, hide Word's
nonprinting black paragraph property markers, replace speculative94.6% throughout
paragraphs/tables/chart with final TD numbers. Word not running at last check.
Do not lose user's edits. Preserve raw data/provenance; no fake network acceptance.
