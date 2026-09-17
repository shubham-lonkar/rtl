# Copyright (c) 2026 Shubham Lonkar
# SPDX-License-Identifier: MIT

# Build and run the UVM environment against xsim's precompiled UVM 1.2
param(
    [string]$Test = "axi_dma_smoke_test",
    [int]$Seed = 1,
    [string]$Verbosity = "UVM_MEDIUM"
)

$ErrorActionPreference = "Stop"
$env:PATH = "C:\Xilinx\Vivado\2024.2\bin;$env:PATH"
Set-Location $PSScriptRoot

if (Test-Path xsim.dir) { Remove-Item -Recurse -Force xsim.dir }

xvlog -sv -L uvm `
    ..\rtl\axi_dma_pkg.sv `
    ..\rtl\axi_dma_fifo.sv `
    ..\rtl\axi_dma_csr.sv `
    ..\rtl\axi_dma_split.sv `
    ..\rtl\axi_dma_rd.sv `
    ..\rtl\axi_dma_wr.sv `
    ..\rtl\axi_dma_top.sv `
    axi_dma_if.sv `
    axi_dma_pkg_uvm.sv `
    tb_axi_dma_uvm.sv
if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

xelab -L uvm -timescale 1ns/1ps -s dma_uvm tb_axi_dma_uvm
if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

# Plusargs go through an -f options file, never the command line: xsim.bat is a cmd batch file and cmd mangles '=' in arguments
$opts = ".xsim_uvm.f"
@(
    "-testplusarg `"UVM_TESTNAME=$Test`"",
    "-testplusarg `"UVM_VERBOSITY=$Verbosity`""
) | Out-File -Encoding ascii $opts

xsim dma_uvm -runall -sv_seed $Seed -f $opts
