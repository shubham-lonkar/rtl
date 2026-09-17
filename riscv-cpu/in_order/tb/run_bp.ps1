# Copyright (c) 2026 Shubham Lonkar
# SPDX-License-Identifier: MIT

# Branch predictor benchmark sweep, in-order core
param(
    [ValidateSet("BP_BIMODAL","BP_GSELECT","BP_GSHARE")][string]$Mode = "BP_GSHARE",
    [int]$IdxW = 10,
    [int]$Ghr  = 4,
    [int]$Ctr  = 2
)

$ErrorActionPreference = "Stop"
$env:PATH = "C:\Xilinx\Vivado\2024.2\bin;$env:PATH"
Set-Location $PSScriptRoot

if (Test-Path xsim.dir) { Remove-Item -Recurse -Force xsim.dir }

# Defines go through an -f options file, never on the command line: xvlog is a cmd batch file and cmd mangles '=' in arguments
$opts = ".xvlog_bp.f"
@(
    "-d BP_MODE_SEL=riscv_pkg::$Mode",
    "-d BP_IDX_W_DEF=$IdxW",
    "-d BP_GHR_BITS_DEF=$Ghr",
    "-d BP_CTR_BITS_DEF=$Ctr"
) | Out-File -Encoding ascii $opts

xvlog -sv -f $opts -i ..\..\common\tb `
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
    tb_bp.sv
if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

xelab -timescale 1ns/1ps -s bp_sim tb_bp
if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

xsim bp_sim -runall
