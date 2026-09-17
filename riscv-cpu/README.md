# RV32I Cores

Two RV32I cores in SystemVerilog: a 5-stage in-order pipeline and an
out-of-order core using Tomasulo with a reorder buffer. Both run the same
program and end up with the same register state.

## In-order core

IF, ID, EX, MEM, WB. All 37 RV32I instructions, including the sub-word
loads and stores (LB/LH/LBU/LHU/SB/SH).

Hazard handling:
- forwarding from EX/MEM and MEM/WB into EX
- one stall cycle for a load-use pair
- write-first bypass in the register file for the distance-3 case
- branches resolve in EX, so a mispredict costs 2 cycles

## Out-of-order core

32-entry RAT, 4 reservation stations, 8-entry ROB, 2-port CDB. Fetch,
decode, rename, dispatch and commit are in order. Issue and execute are
not.

It does not speculate. Fetch stalls after a branch until that branch
commits, so there is no misprediction recovery to build. That costs most
of the ILP, and it is the first thing I would fix.

## Branch predictor

One BHT with three index functions, picked at compile time:

| Mode | Index |
|---|---|
| `BP_BIMODAL` | PC only |
| `BP_GSELECT` | PC bits concatenated with GHR |
| `BP_GSHARE` | PC xor GHR |

Table depth, GHR width and counter width are parameters. Global history
is snapshotted per branch and restored on a mispredict.

## Verification

`common/tb/iss.py` is a Python RV32I simulator I wrote as a golden model.
It has no pipeline and no timing, just the ISA. `tb_trace.sv` reads its
trace and compares every instruction that retires (PC, rd, value), so a
test fails at the first instruction that goes wrong instead of at the end.

There are also SVA checkers in `riscv_sva.sv` (bound, not inlined) and a
covergroup in `riscv_cov.sv`. Coverage is at 100% on all four groups.

Three test programs, all built by `common/tb/gen_program.py`:

| Program | What it covers |
|---|---|
| `program.hex` | forwarding, load-use, branches, JAL, LUI/AUIPC |
| `mem_program.hex` | sub-word loads and stores at every offset |
| `cov_program.hex` | the coverage holes the other two leave |

## Running it

Needs Vivado 2024.2 and Python 3. From `in_order/tb`:

```powershell
.\run_trace.ps1    # compare against the ISS, run assertions and coverage
.\run.ps1          # check register state at the end
.\run_bp.ps1       # branch predictor benchmarks
```

All three take `-Mode BP_BIMODAL|BP_GSELECT|BP_GSHARE`. Same scripts in
`out_of_order/tb`.

## Not implemented

No CSRs, no traps, no M/A/F/D/C. Memories are Harvard with combinational
reads, so there is no memory stall path. Misaligned accesses are not
supported, and since there are no traps an assertion fires instead of
returning a wrong word.

The out-of-order core is LW/SW only and has no JALR.
