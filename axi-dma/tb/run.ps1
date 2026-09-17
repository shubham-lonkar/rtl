# Copyright (c) 2026 Shubham Lonkar
# SPDX-License-Identifier: MIT

# Build and run the directed DMA testbench
$ErrorActionPreference = "Stop"
$env:PATH = "C:\Xilinx\Vivado\2024.2\bin;$env:PATH"
Set-Location $PSScriptRoot

# A stale work library hides compile errors: xelab links the previous build of a file that failed to analyse this time
if (Test-Path xsim.dir) { Remove-Item -Recurse -Force xsim.dir }

xvlog -sv `
    ..\rtl\axi_dma_pkg.sv `
    ..\rtl\axi_dma_fifo.sv `
    ..\rtl\axi_dma_csr.sv `
    ..\rtl\axi_dma_split.sv `
    ..\rtl\axi_dma_rd.sv `
    ..\rtl\axi_dma_wr.sv `
    ..\rtl\axi_dma_top.sv `
    axi_slave_mem.sv `
    tb_axi_dma.sv
if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

xelab -timescale 1ns/1ps -s dma_sim tb_axi_dma
if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

xsim dma_sim -runall
