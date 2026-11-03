param([string]$ReportDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build-work'))
$ErrorActionPreference = 'Stop'
$status = Get-Content -LiteralPath (Join-Path $ReportDirectory 'timing_status.rpt') -Raw
$summary = Get-Content -LiteralPath (Join-Path $ReportDirectory 'timing_summary.rpt') -Raw
foreach ($metric in @('SWNS', 'STNS', 'HWNS', 'HTNS')) {
    $match = [regex]::Match($status, "$metric`: ([+-]?[0-9.]+)ns")
    if (-not $match.Success) { throw "Missing timing metric: $metric" }
    $value = [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
    if ($value -lt 0) { throw "Timing check failed: $metric = $value ns" }
}
# Ensure SDRAM read/write paths were analyzed, rather than cut away. The
# generated shifted clock has its normal PLL pin name in this project.
$shifted = 'sys_pll_m0/pll_inst.clkc[2]'
foreach ($direction in @(@('ext_mem_clk', $shifted, 48), @($shifted, 'ext_mem_clk', 32))) {
    $name = [regex]::Escape("$($direction[0]) -> $($direction[1])")
    $pattern = "(?ms)^Path Group\s+:\s+$name\s*\r?\n(?:(?!^Path Group).)*?^Max\s+: SWNS\s+([+-]?[0-9.]+)ns, STNS\s+([+-]?[0-9.]+)ns,\s+(\d+) Viol Endpoints,\s+(\d+) Total Endpoints"
    $group = [regex]::Match($summary, $pattern)
    if (-not $group.Success) { throw "Missing analyzed SDRAM path group: $name" }
    if ([int]$group.Groups[3].Value -ne 0 -or [int]$group.Groups[4].Value -ne $direction[2]) {
        throw "Unexpected SDRAM violations or endpoint coverage: $($direction[0]) -> $($direction[1])"
    }
}
Write-Output 'PASS: nonnegative Setup/Hold WNS/TNS and all 48 write / 32 read SDRAM endpoints analyzed without violations. Physical verification remains separate.'
