# Integrated HXFP candidate — timing closed

The integrated image receiver, frame-buffer bridge, HTTP control page, boot video,
FFT, OSD and audio design completed TD6.2.168116 place/route/bitgen on2026-11-02.
Picture, sound and button functional acceptance is passed by user confirmation.

## Candidate identity

- Branch: `integration/hxfp`, based on teammate commit `f8f8793` plus local work.
- Candidate: `build/physical-retries/541d-routability/integrated.bit`.
- SHA256: `625d0b2d7974b01f5d138eef0ae82afd547d5584011d1e3d4a1fb04416900b76`.
- Frozen source, bit, reports, recipe, input manifest and regressions:
  `artifacts/integrated-timing-closed-20261102/`.
- Successful recipe: area-priority gate mapping, high gate packing/high placement,
  adaptive pin-density packing, routing effort `routability`, hold repair enabled.
  No clock periods were relaxed. Extra `phys_opt` is omitted because it repeatedly
  crashes in this TD version; normal routing optimization remains enabled.

## Final routed results

| Metric | Result |
|---|---:|
| Setup WNS / TNS | +0.156 / 0.000 ns |
| Hold WNS / TNS | +0.022 / 0.000 ns |
| STA coverage | 99.97% |
| SDRAM write/read endpoints | 48 /32, analyzed with zero violations |
| LUT |16474 /19600,84.05% |
| Registers |12087 /19600,61.67% |
| BRAM9K |47 /64,73.44% |
| BRAM32K |8 /16,50.00% |
| DSP |21 /29,72.41% |

The earlier94.6% target was superseded by the user's preference to retain the
current functional result and prioritize zero timing violations. These are actual
routed values; Slice occupancy must not be substituted for LUT percentage.
`tools/check-timing.ps1` passed. Timing is closed for the analyzed constraints,
not a claim of100% interface coverage. A local-clock-routing warning remains on
the shifted PLL connection to the dedicated SDRAM clock; both SDRAM directions
were explicitly checked. No abnormal timing path or multi-driver was reported.

## Relevant changes and checks

- Receiver predecodes header/session/length/CRC dispatch predicates in CHECK;
  pixel writes remain after packet validation and display ACK after real commit.
- Image bridge uses the production vendor FIFO in normal-read mode with a holding
  register, preserving backpressure and removing the long show-ahead control path.
- BMP header capture/decision and audio next-song descriptors are registered;
  bytewise audio zero flags remove the wide decrement-to-zero control path.
- Boot timeout precomputation preserves the timeout cycle. Synchronous buffers
  and FFT coefficient/band memories retain verified numerical/pixel results.
- Legacy glyphs use LUTs;24px glyphs use BRAM to relieve congestion. Exhaustive
  glyph/row/latency comparison passes. HTTP ROM source-relative lookup is fixed;
  missing initialization file warningHDL-5105 now aborts builds.
- Three reviewed first-stage HXFP CDC hold exceptions added: display bank,
  display ACK toggle and boot-active level. Later stages and SDRAM remain timed.

Final regression log: `diagnostics/regression-final-541d.log`.
It includes1226 HXFP packet scenarios,614912 pixel writes,2162688 UI channel/gain
comparisons, all1228800 frame-write addresses across four banks,16600 PCM words
with cycle comparison, FFT/boot comparisons, real FIFO backpressure/cancel/frame
commit tests, all2071 HTTP response bytes, and30 passing desktop tests.
Real Ethernet image-transfer acceptance was not claimed in this session.

## Build time

Input/artifact SHA256 checks allow exact checkpoint reuse. An unchanged gate
check took0.652s versus93.265s fresh. Failed physical retries retained gate/place
databases. The successful route-from-place, final STA and bitgen took176.925s;
the same placement's prior normal-route attempt failed after243.912s routing.
This is a measured retry improvement, not a guarantee for unrelated designs.

## SRAM download

Full2MiB Flash backup and three independent reread blocks verified; USB Code0;
unique JTAG ID0x0a014c35/EG4S20BG256 detection exited0.
At13:53 the authorized1MHz SRAM write failed with USB read/write errors
(-9,-4,-1), final exit1. A100%/Done progress line is NOT success when the loader
ends with `Failed to program FPGA`. No SRAM readback is claimed. Flash/TF untouched.

After user-confirmed USB-JTAG replug, retry1 rechecked bit hash, timing, USB and
unique JTAG target, then completed at100%/Done with exit0 and no USB error.
The same timing-closed candidate is now loaded in volatile SRAM. See
`diagnostics/final-sram-receipt-retry1.json` and
`diagnostics/final-sram-download-retry1.log`; the first failed attempt remains
preserved separately. Flash/TF were not written. SRAM bit-for-bit readback was
not performed. Picture, sound and button acceptance remains user-confirmed passed.

After artifact freezing and download, `tools/build.tcl` was updated to default to
the successful routability strategy. The frozen `retry.tcl` and historical input
manifest identify the exact successful invocation; hardware source/constraints
were not changed after the successful build. The next clean build will have a
new driver hash and run identity, as intended by the conservative cache policy.

No Word/PDF report was edited. Report layout is another owner's task; content
updates still require user approval.
