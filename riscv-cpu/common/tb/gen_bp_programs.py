# Copyright (c) 2026 Shubham Lonkar
# SPDX-License-Identifier: MIT

"""Branch-predictor workloads -> bp_*.hex plus the scenario table the TBs read.

gen_program.py builds the one program that checks architectural correctness.
This builds the programs that make the predictor sweat: each one is a branch
PATTERN chosen so a specific predictor property either shows up or does not.

Run:  python gen_bp_programs.py

Emits, next to this file:
    bp_<name>.hex          one per scenario
    bp_scenarios.svh       generated SV include: name, hex file, expected result

The .svh is generated rather than hand-maintained so the expected values cannot
drift away from the programs that produce them.
"""

# encoders
R_OPS = {"add": (0x00, 0b000), "sub": (0x20, 0b000), "and": (0x00, 0b111)}
I_OPS = {"addi": 0b000, "andi": 0b111, "ori": 0b110, "slti": 0b010}
B_OPS = {"beq": 0b000, "bne": 0b001, "blt": 0b100,
         "bge": 0b101, "bltu": 0b110, "bgeu": 0b111}

DONE_ADDR = 252          # dmem word 63 -- the "program finished" flag

def r(name, rd, rs1, rs2):
    f7, f3 = R_OPS[name]
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0b0110011

def i(name, rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (I_OPS[name] << 12) | (rd << 7) | 0b0010011

def sw(rs2, rs1, imm):
    imm &= 0xFFF
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (0b010 << 12) | ((imm & 0x1F) << 7) | 0b0100011

def b(name, rs1, rs2, off):
    off &= 0x1FFF
    return (((off >> 12) & 1) << 31) | (((off >> 5) & 0x3F) << 25) | \
           (rs2 << 20) | (rs1 << 15) | (B_OPS[name] << 12) | \
           (((off >> 1) & 0xF) << 8) | (((off >> 11) & 1) << 7) | 0b1100011

def jal(rd, off):
    off &= 0x1FFFFF
    return (((off >> 20) & 1) << 31) | (((off >> 1) & 0x3FF) << 21) | \
           (((off >> 11) & 1) << 20) | (((off >> 12) & 0xFF) << 12) | \
           (rd << 7) | 0b1101111

# two-pass assembler Hand-resolved branch offsets are where bring-up time goes, and a wrong offset in a predictor benchmark looks exactly like a predictor bug
def assemble(src):
    labels, pc = {}, 0
    for item in src:
        if isinstance(item, str):
            labels[item] = pc
        else:
            pc += 4

    words, pc = [], 0
    for item in src:
        if isinstance(item, str):
            continue
        op, args = item[0], item[1:]
        if op in R_OPS:
            words.append(r(op, *args))
        elif op in I_OPS:
            words.append(i(op, *args))
        elif op == "sw":
            words.append(sw(*args))
        elif op in B_OPS:
            rs1, rs2, lbl = args
            words.append(b(op, rs1, rs2, labels[lbl] - pc))
        elif op == "jal":
            rd, lbl = args
            words.append(jal(rd, labels[lbl] - pc))
        else:
            raise ValueError("unknown op " + op)
        pc += 4
    return words, labels

# scenarios Trip counts are deliberately large
SCENARIOS = []

def scenario(name, note, src, reg, exp):
    """Append the standard epilogue and register the scenario.

    Every program ends by storing 1 to DONE_ADDR and then spinning on a self
    JUMP. Two reasons for that shape:

      - The store is how the testbench knows the run finished. Watching the PC
        instead does not work: a cold predictor falls through the loop branch
        and fetches the halt address speculatively, long before the program is
        actually done. A store only ever executes on the correct path.

      - The spin is a JAL, not the self-BRANCH that gen_program.py uses. A
        self-branch would contribute thousands of trivially predictable events
        and drown out the workload being measured.
    """
    SCENARIOS.append(dict(
        name=name, note=note, reg=reg, exp=exp,
        src=list(src) + [
            ("addi", 31, 0, 1),
            ("sw", 31, 0, DONE_ADDR),
            "halt", ("jal", 0, "halt"),
        ]))

# 1
scenario("loop_simple", "single loop, 200 trips -- baseline, every scheme passes", [
    ("addi", 1, 0, 200),         # trip count
    ("addi", 2, 0, 0),           # accumulator
    "loop",
    ("addi", 2, 2, 3),
    ("addi", 1, 1, -1),
    ("bne", 1, 0, "loop"),       # 199 taken, 1 not taken
], reg=2, exp=600)

# 2
scenario("loop_nested", "50 x 4 nested -- inner branch is T,T,T,N; bimodal caps near 75%", [
    ("addi", 3, 0, 50),          # outer count
    ("addi", 2, 0, 0),
    "outer",
    ("addi", 4, 0, 4),           # inner count
    "inner",
    ("addi", 2, 2, 1),
    ("addi", 4, 4, -1),
    ("bne", 4, 0, "inner"),
    ("addi", 3, 3, -1),
    ("bne", 3, 0, "outer"),
], reg=2, exp=200)

# 3
scenario("correlated", "B's outcome is decided by A -- pure global-correlation test", [
    ("addi", 5, 0, 0),           # i
    ("addi", 6, 0, 200),         # trip
    ("addi", 9, 0, 0),           # accumulator
    "top",
    ("andi", 7, 5, 1),           # x7 = i & 1
    ("beq", 7, 0, "skipA"),      # A: taken when i is even -> T,N,T,N ...
    ("addi", 9, 9, 1),
    "skipA",
    ("beq", 7, 0, "skipB"),      # B: identical condition, perfectly correlated
    ("addi", 9, 9, 10),
    "skipB",
    ("addi", 5, 5, 1),
    ("bne", 5, 6, "top"),
], reg=9, exp=1100)           # 100 odd trips x 11

# 4
scenario("pattern4", "one branch, T,T,N,N forever -- 2-bit counters cannot see it", [
    ("addi", 5, 0, 0),
    ("addi", 6, 0, 200),
    ("addi", 9, 0, 0),
    "top",
    ("andi", 7, 5, 2),           # 0,0,2,2,0,0,2,2 ...
    ("beq", 7, 0, "skip"),       # T,T,N,N repeating
    ("addi", 9, 9, 1),
    "skip",
    ("addi", 5, 5, 1),
    ("bne", 5, 6, "top"),
], reg=9, exp=100)

# 5
scenario("aliasing", "six branches, six biases -- shrink -IdxW to force collisions", [
    ("addi", 5, 0, 0),           # i
    ("addi", 6, 0, 200),         # trip
    ("addi", 9, 0, 0),           # accumulator
    "top",
    ("andi", 7, 5, 1),
    ("beq", 7, 0, "L1"),         # B1: period 2
    ("addi", 9, 9, 1),           # 100 trips  -> +100
    "L1",
    ("andi", 7, 5, 2),
    ("beq", 7, 0, "L2"),         # B2: period 4, T,T,N,N
    ("addi", 9, 9, 2),           # 100 trips  -> +200
    "L2",
    ("andi", 7, 5, 3),
    ("beq", 7, 0, "L3"),         # B3: taken 1 trip in 4
    ("addi", 9, 9, 4),           # 150 trips  -> +600
    "L3",
    ("addi", 7, 0, 1),
    ("beq", 7, 0, "L4"),         # B4: never taken
    ("addi", 9, 9, 8),           # 200 trips  -> +1600
    "L4",
    ("beq", 0, 0, "L5"),         # B5: always taken
    ("addi", 9, 9, 16),          # never runs
    "L5",
    ("addi", 5, 5, 1),
    ("bne", 5, 6, "top"),        # B6: the loop
], reg=9, exp=2500)

# emit
if __name__ == "__main__":
    rows = []

    for s in SCENARIOS:
        words, _ = assemble(s["src"])
        fn = "bp_%s.hex" % s["name"]
        with open(fn, "w") as f:
            for w in words:
                f.write("%08x\n" % w)
        rows.append((s["name"], fn, s["reg"], s["exp"]))
        print("%-13s %3d instr   x%-2d == %-4d   %s"
              % (s["name"], len(words), s["reg"], s["exp"], s["note"]))

    with open("bp_scenarios.svh", "w") as f:
        f.write("// GENERATED by gen_bp_programs.py -- do not edit.\n")
        f.write("// Shared by tb_bp (in-order) and tb_bp_oo (out-of-order).\n\n")
        f.write("localparam int BP_DONE_WORD = %d;   // dmem word the epilogue writes\n\n"
                % (DONE_ADDR // 4))
        f.write("typedef struct {\n")
        f.write("    string       name;\n")
        f.write("    string       hex;\n")
        f.write("    int          chk_reg;\n")
        f.write("    logic [31:0] chk_val;\n")
        f.write("} bp_scn_t;\n\n")
        f.write("localparam int BP_N_SCN = %d;\n\n" % len(rows))
        f.write("bp_scn_t bp_scn [BP_N_SCN] = '{\n")
        for n, (name, fn, reg, exp) in enumerate(rows):
            f.write("    '{ \"%s\", \"%s\", %d, 32'd%d }%s\n"
                    % (name, fn, reg, exp, "," if n < len(rows) - 1 else ""))
        f.write("};\n")

    print("\n%d scenarios -> bp_*.hex + bp_scenarios.svh" % len(rows))
