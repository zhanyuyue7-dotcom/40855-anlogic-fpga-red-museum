# Integration candidate SRAM entry

Read this before each detect/download. This is the integration-host adaptation
of `D:/FPGA/shunying/FPGA_DOWNLOAD.md`; its referenced old `D:/EDA/Download-guide.md`
and old loader path are absent on this host. Use the existing verified loader:

`D:/msys64/ucrt64/bin/openFPGALoader.exe`

The user authorized this integration candidate's volatile SRAM download and
confirmed picture/audio/button functional acceptance on 2026-11-02. Configuration
Flash programming, TF writes, driver changes and pushes are NOT authorized.

Before writing:

1. Read `INTEGRATION_STATE.md` and the exact candidate receipt. Ensure inputs did
   not change during/after the build, the run is complete, and bit SHA256 matches.
   Do not use mixed-age `build/integrated` artifacts.
2. Run `tools/check-timing.ps1 -ReportDirectory <candidate-run>`. Verify nonnegative
   SWNS/STNS/HWNS/HTNS, 48 write/32 read SDRAM endpoints, and inspect coverage.
3. Verify the 2MiB backup `D:/FPGA/shunying/backups/before-first-sram/config-flash-2MiB.bin`.
   Expected SHA256:
   `9e7ad654beb708b1f22e8bd3aafed6d8c7b8f040f20f591d9259e83beac8a27f`.
   Compare all three 64KiB independent blocks `check-000000.bin`,
   `check-100000.bin`, `check-1f0000.bin` against corresponding full-backup slices.
   Do not substitute the zero-byte failed monolithic backup or an old host hash.
4. Enumerate USB VID0547/PID1002. Require Code0, then independently require unique
   JTAG detect exit0 with EG4S20BG256 / ID0x0a014c35 at1MHz.
5. Use the generic reviewed-candidate command:

```powershell
& 'D:/msys64/ucrt64/bin/openFPGALoader.exe' -c anlogicCable --detect --freq 1000000
& 'D:/msys64/ucrt64/bin/openFPGALoader.exe' -c anlogicCable --write-sram --freq 1000000 '<verified-bit-path>'
```

Save logs and a receipt with SHA256, target, backup checks, timing and exit code.
Require process completion, exit0,100% and Done. Do not describe this as SRAM
bit-for-bit readback. SRAM is volatile; Flash remains untouched.

On USB bulk write -9/-7, stop writes and ask for USB-JTAG unplug/replug with an
approximately3-second wait. Do not loop retries or alter drivers. Successful USB
enumeration alone is not successful JTAG detection.

User-confirmed picture/audio/button acceptance is recorded as passed. No real
Ethernet image-transfer success is inferred from that confirmation. Any new local
candidate's build/download record must identify its own artifact independently.
