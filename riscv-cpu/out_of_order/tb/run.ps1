# Copyright (c) 2026 Shubham Lonkar
# SPDX-License-Identifier: MIT

# Build and run the out-of-order core
param([string]$Mode = "BP_GSHARE")

$ErrorActionPreference = "Stop"
$env:PATH = "C:\Xilinx\Vivado\2024.2\bin;$env:PATH"
Set-Location $PSScriptRoot

# A stale work library hides compile errors: xelab happily links the previous build of a file that failed to analyse this time
if (Test-Path xsim.dir) { Remove-Item -Recurse -Force xsim.dir }

# Mode name -> a valueless define
switch ($Mode) {
    "BP_BIMODAL" { $ModeDef = "-d", "BP_SEL_BIMODAL" }
    "BP_GSELECT" { $ModeDef = "-d", "BP_SEL_GSELECT" }
    "BP_GSHARE"  { $ModeDef = @() }
    default      { throw "unknown -Mode $Mode (BP_BIMODAL | BP_GSELECT | BP_GSHARE)" }
}

xvlog -sv $ModeDef `
    ..\..\common\rtl\riscv_pkg.sv `
    ..\rtl\oo_pkg.sv `
    ..\..\common\rtl\alu.sv `
    ..\..\common\rtl\imm_gen.sv `
    ..\..\common\rtl\control.sv `
    ..\..\common\rtl\branch_predictor.sv `
    ..\rtl\arch_regfile.sv `
    ..\rtl\oo_core.sv `
    ..\..\common\tb\mem_model.sv `
    tb_oo_core.sv
if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

xelab -timescale 1ns/1ps -s oo_sim tb_oo_core
if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

xsim oo_sim -runall
