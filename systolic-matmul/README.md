# 4x4 Systolic Matrix Multiplier (FP8 E3M4)

A 4x4 output-stationary systolic array that multiplies two 4x4 matrices in
E3M4 floating point (1 sign, 3 exponent, 4 mantissa, bias 3). A moves right
through the mesh, B moves down, each PE accumulates its own `C[i][j]` in
place.

## MAC pipeline

Each PE's MAC is a 3-stage pipeline: capture operands, multiply (registered),
accumulate (registered). It used to do the multiply and add combinationally
in one cycle, which didn't match the `NUM_CYCLES_IN_MAC=3` the surrounding
address/timing counters already assumed, and left a long mult+add critical
path. Splitting it into three register-to-register hops fixed both.

## Verification

`tb/matmul_with_ram_tb.sv` loads A/B through the design's actual BRAM ports,
not internal hierarchical pokes, runs two cases, and reads C back:
- `A = 2*I`: every output is a single nonzero product, checks addressing.
- `A` all-ones, `B`'s columns permutations of `{1,2,4,8}`: every output sums
  all 4 terms, checks the MAC's accumulate path.

Values are all powers of two, so every multiply and every intermediate sum
is exact in E3M4, no need to model the adder's rounding to check results.
32/32 checks pass.

```
vlib work
vlog -sv rtl/matmul.sv rtl/matmul_with_ram.sv tb/matmul_with_ram_tb.sv
vsim -c work.matmul_with_ram_tb -do "run -all; quit -f"
```
(ModelSim / Questa)

## Synthesis

Quartus Prime, targeting the `matmul_4x4_systolic` core directly. The RAM
wrapper's behavioral memory doesn't infer to block RAM, so timing it would
just be measuring register-built memory, not the multiplier.

```
cd synth
quartus_map matmul_synth               # speed grade 8, worst commercial
quartus_fit matmul_synth
quartus_sta matmul_synth

quartus_map matmul_synth -c matmul_synth_fastgrade   # speed grade 7
quartus_fit matmul_synth -c matmul_synth_fastgrade
quartus_sta matmul_synth -c matmul_synth_fastgrade
```

| Device (Cyclone V) | Fmax, worst-case | Fmax, typical |
|---|---|---|
| 5CGXFC9E7F35C8 (speed grade 8) | 93.3 MHz | 95.6 MHz |
| 5CGXFC9E6F35C7 (speed grade 7) | 106.7 MHz | 110.6 MHz |

2862 LEs, 16 DSP blocks. Critical path both times is entirely inside one
PE's adder (`FPAddSub_E3M4`'s align/shift/normalize/round chain), so the
pipeline split isn't leaking a multi-op path anywhere else.

## Not implemented

No APB/register wrapper, just the core and a RAM-backed top level. No bus
fabric, no larger-than-4x4 tiling (the ports for chaining tiles exist but
are unused), no exhaustive rounding-corner testing since the test data is
intentionally exact (see above).
