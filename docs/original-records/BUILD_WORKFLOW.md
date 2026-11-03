# TD build and candidate evidence

Run from this integration repository using the pinned TD 6.2.168116 toolchain.

```powershell
# Fast RTL/protocol checks; includes the actual vendor image FIFO.
./tools/test-integration.ps1
# Check synthesis/resources without paying for placement/routing.
./tools/build.ps1 -Stage gate
# Continue the same verified inputs from the most advanced saved checkpoint.
./tools/build.ps1
# Final independent clean build, with no old artifacts deleted.
./tools/build.ps1 -Clean
```

`-Stage place` and `-Stage route` can stop at those checkpoints for diagnosis.
These stops are NOT completed bitstreams or timing acceptance. `-PostRouteOptimize`
enables an optional extra `phys_opt` step that crashed in the predecessor's TD run;
normal routing optimization and high placement effort are retained by default.
The final validated flow also uses area-priority mapping, high gate packing and
route effort `routability`. On the accepted candidate this removed an HTTP route
conflict and completed route/STA/bitgen in176.925s from a verified place checkpoint,
with Setup+0.156ns and Hold+0.022ns. The normal-route attempt on that same placement
failed. These settings preserve the RTL and timing constraints.

Each run is under `build/runs/<input-hash>-<timestamp>`. `inputs.json` binds source,
constraints, ROM assets, project/IP inputs, build driver and TD executable hashes.
`receipt.json` records artifact hashes, elapsed time, actual stage reuse and STA.
`diagnostics/latest-build.json` points to the latest requested result. Never choose
a bitstream solely by its filename or modification time. Historical
`build/integrated` contains mixed-age files and is not the new candidate directory.

A cache hit requires matching inputs AND matching saved artifact contents. Inputs
changed during a run invalidate eligibility. A lock prevents two managed builds
from writing TD's implicit project reports concurrently. Do not launch a separate
unmanaged TD writer against this project.

Resource overflow is rejected before placement. Missing ROM initialization files
(`HDL-5105`) stop the owned TD process before wasting physical work. Every routed
checkpoint is exported before optional post-route processing, so a later optimizer
failure does not require repeating synthesis, placement and routing. Negative
SWNS/STNS/HWNS/HTNS prevents bitgen. Before download, also run:

```powershell
./tools/check-timing.ps1 -ReportDirectory '<run-directory>'
```

This checks the 48 SDRAM write and 32 read endpoints as well as global timing.
Review STA coverage, exceptions and warnings separately. A timing pass does not
prove physical HDMI/audio/network behavior.

Measured example on 2026-11-02: fresh gate 93.265 seconds; an unchanged, hash-checked
repeat took 0.652 seconds wall time. This measures avoided repeated work, not a
promise that new placement/routing becomes that fast. The first post-takeover full
physical run took 749.733 seconds after the gate checkpoint and failed setup;
it must not be presented as a successful candidate. Detailed times are in receipts.

Report layout/photos are outside this task. Changes to the user's Word/PDF report
require approval. Engineering results belong here and in `INTEGRATION_STATE.md`.
