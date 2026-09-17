# Copyright (c) 2026 Shubham Lonkar
# SPDX-License-Identifier: MIT

# Per-instruction regression: runs every program in tb_trace.sv against the golden trace from the Python ISS, with assertions and coverage bound in
param([string]$Mode = "BP_GSHARE")

$ErrorActionPreference = "Stop"
$env:PATH = "C:\Xilinx\Vivado\2024.2\bin;$env:PATH"
Set-Location $PSScriptRoot

Push-Location ..\..\common\tb
python gen_program.py | Out-Null
python iss.py program.hex
python iss.py mem_program.hex
python iss.py cov_program.hex
Pop-Location

if (Test-Path xsim.dir) { Remove-Item -Recurse -Force xsim.dir }

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
    riscv_cov.sv `
    ..\..\common\tb\mem_model.sv `
    tb_trace.sv
if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

xelab -timescale 1ns/1ps -s trace_sim tb_trace
if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

xsim trace_sim -runall
