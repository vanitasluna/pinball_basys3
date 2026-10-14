param([string]$VivadoBin='D:\2025.2\Vivado\bin',
    [string[]]$Tests=@('tb_input','tb_game','tb_physics','tb_multiball','tb_two_ball_game','tb_collision','tb_vga','tb_vga_clock','tb_renderer','tb_effects','tb_vga_renderer','tb_top'))
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path $projectRoot 'tests'
$simWork=Join-Path $testRoot 'work'
New-Item -ItemType Directory -Force -Path $simWork | Out-Null
Push-Location $simWork
try {
    $sources=Join-Path $projectRoot 'FDP2026.srcs\sources_1\new'
    & (Join-Path $VivadoBin 'xvhdl.bat') (Join-Path $sources 'Ps2Interface.vhd') (Join-Path $sources 'Mouse_Control.vhd')
    if($LASTEXITCODE -ne 0){throw 'VHDL compilation failed'}
    $verilog=@(Get-ChildItem -LiteralPath $sources -Filter '*.v' | ForEach-Object FullName)
    & (Join-Path $VivadoBin 'xvlog.bat') @verilog
    if($LASTEXITCODE -ne 0){throw 'RTL compilation failed'}
    $globalSource=Join-Path (Split-Path -Parent $VivadoBin) 'data\verilog\src\glbl.v'
    & (Join-Path $VivadoBin 'xvlog.bat') $globalSource
    if($LASTEXITCODE -ne 0){throw 'FPGA global simulation model compilation failed'}
    $testbenches=@(Get-ChildItem -LiteralPath $testRoot -Filter 'tb_*.sv' | ForEach-Object FullName)
    & (Join-Path $VivadoBin 'xvlog.bat') -sv @testbenches
    if($LASTEXITCODE -ne 0){throw 'Test compilation failed'}
    foreach($test in $Tests) {
        if(!(Test-Path -LiteralPath (Join-Path $testRoot ($test+'.sv')))){throw "Missing test: $test"}
        # Serial elaboration avoids intermittent generated-C compiler failures
        # in Vivado 2025.2 on this Windows host; simulation coverage is unchanged.
        & (Join-Path $VivadoBin 'xelab.bat') $test glbl -L unisims_ver -L unisim -L unimacro_ver -mt off -s $test --timescale 1ns/1ps
        if($LASTEXITCODE -ne 0){throw "Elaboration failed: $test"}
        & (Join-Path $VivadoBin 'xsim.bat') $test -runall -onerror quit -onfinish quit -log ($test+'.log')
        if($LASTEXITCODE -ne 0){throw "Simulation failed: $test"}
        $logText=Get-Content -LiteralPath ($test+'.log') -Raw
        if($logText -notmatch "PASS $test" -or $logText -match 'Fatal:'){throw "Self-check failed: $test"}
    }
    Write-Output 'ALL SIMULATIONS PASSED'
} finally {Pop-Location}
