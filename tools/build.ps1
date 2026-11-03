param(
 [ValidateSet('baseline','integrated')][string]$Variant='integrated',
 [ValidateSet('gate','place','route','full')][string]$Stage='full',
 [switch]$Clean,
 [switch]$PostRouteOptimize,
 [string]$PythonExe="",
 [string]$TdExecutable="D:\EDA\TD6.2.1\bin\td_commands_prompt.exe"
)
$ErrorActionPreference='Stop'
$py=$PythonExe
if(-not $py){$py=Join-Path (Split-Path -Parent $PSScriptRoot) 'desktop/.venv/Scripts/python.exe'}
if(-not (Test-Path -LiteralPath $py)){throw 'Create desktop/.venv or pass -PythonExe (Python 3.12).'}
$env:MUSEUM_TD_EXE=$TdExecutable
$argsList=@((Join-Path $PSScriptRoot 'td_build.py'),'--variant',$Variant,'--stage',$Stage)
if($Clean){$argsList+='--clean'}
if($PostRouteOptimize){$argsList+='--phys-opt'}
& $py @argsList
if($LASTEXITCODE -ne 0){throw "TD stage failed; see printed run directory and receipt (exit $LASTEXITCODE)"}
