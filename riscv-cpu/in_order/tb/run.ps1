# Copyright (c) 2026 Shubham Lonkar
# SPDX-License-Identifier: MIT

# Build and run the in-order core
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
    ..\..\common\rtl\alu.sv `
    ..\..\common\rtl\imm_gen.sv `
    ..\..\common\rtl\control.sv `
    ..\..\common\rtl\branch_predictor.sv `
    ..\rtl\regfile.sv `
    ..\rtl\if_stage.sv `
    ..\rtl\id_stage.sv `
    ..\rtl\ex_stage.sv `
    ..\rtl\mem_wb_stage.sv `
    ..\rtl\hazard_unit.sv `
    ..\rtl\riscv_core.sv `
    ..\rtl\riscv_sva.sv `
    ..\..\common\tb\mem_model.sv `
    tb_core.sv
if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

xelab -timescale 1ns/1ps -s core_sim tb_core
if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

xsim core_sim -runall
