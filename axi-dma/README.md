# AXI4 DMA

A block-copy DMA in SystemVerilog. You program it over AXI4-Lite and it
moves data as an AXI4 master. There is a directed testbench and a UVM
environment.

## How it works

Software writes source, destination, length and max burst size, then sets
the start bit. The engine splits that into legal AXI bursts and copies the
data.

The splitting is the interesting part. Each burst is the smallest of four
limits:

1. bytes left in the transfer
2. bytes to the next 4KB boundary from the source
3. bytes to the next 4KB boundary from the destination
4. the configured max beats per burst

Source and destination can have different alignments, so 2 and 3 have to
be separate limits. A copy from 0x0FF0 to 0x2000 hits a source boundary
after 16 bytes but a destination boundary after 4096.

```
AXI4-Lite --> CSR --> split FSM --> rd cmd FIFO --> read engine --+
                         |                                   data FIFO
                         |                                       |
                         +------> wr cmd FIFO --> write engine <--+
```

Read and write are separate engines with a FIFO between them instead of
one FSM doing read-then-write. This lets the read side run ahead while the
write side is still draining.

The read engine will not start a burst until the data FIFO has room for
all of it, so `max_beats` gets clamped to the FIFO depth at the top level.
Without that clamp it deadlocks.

## Registers

| Offset | Name | Bits |
|---|---|---|
| 0x00 | CTRL | [0] START (self-clearing) [1] ABORT [2] IRQ_EN |
| 0x04 | STATUS | read only: [0] BUSY [1] DONE [2] ERR [4:3] last bad response |
| 0x08 | SRC | source address |
| 0x0C | DST | destination address |
| 0x10 | LEN | length in bytes |
| 0x14 | BURST | max beats per burst, clamped to 1..256 |
| 0x18 | IRQ | [0] DONE latch, write 1 to clear |

START is ignored while the engine is busy. The CSR latches AW and W
separately because they are independent channels and a master is allowed
to send W first.

## Testbenches

Directed (`tb/`) is 12 scenarios and 35 checks: registers, single beat,
one full burst, multi-burst, a transfer crossing a 4KB boundary, max burst
length, random stalls, zero length, read and write errors, interrupts, and
back-to-back descriptors.

UVM (`uvm/`) does the random side: random descriptors, random alignments,
random slave stalls and error injection.

- AXI4-Lite master agent for the CSR port
- AXI4 slave responder with a memory model, stall rate and error injection
- monitors on both ports that rebuild bursts from the channels
- scoreboard that learns the descriptor by watching the CSR writes rather
  than being told by the sequence

The scoreboard snapshots the source at START and compares the destination
at DONE. It also checks that the bursts tile the address range with no gap
or overlap, which the end-state check alone would miss.

Protocol rules (4KB boundary, INCR only, VALID stability) are assertions
on the interface, not in the tests, so they apply to every run.

| Test | What it does |
|---|---|
| `axi_dma_smoke_test` | one descriptor, no stalls |
| `axi_dma_base_test` | 5 to 20 random descriptors |
| `axi_dma_long_test` | page-aligned 4KB copies at 256 beats |
| `axi_dma_stall_test` | 50% backpressure everywhere |
| `axi_dma_err_test` | SLVERR injection, engine must set ERR and still finish |

## Running it

Needs Vivado 2024.2 with its built-in UVM 1.2.

```powershell
cd tb  ; .\run.ps1
cd uvm ; .\run_uvm.ps1
         .\run_uvm.ps1 -Test axi_dma_stall_test
         .\run_uvm.ps1 -Test axi_dma_err_test -Seed 42
```

## Not implemented

Addresses have to be beat-aligned and length a whole number of beats. No
byte-granular or unaligned transfers, so the WSTRB cases are untested.

Read and write bursts are forced to the same beat count. That keeps the
data FIFO simple with no beat rebalancing, but a badly aligned pair splits
more often than it needs to.
