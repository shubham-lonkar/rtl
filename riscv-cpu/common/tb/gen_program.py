# Copyright (c) 2026 Shubham Lonkar
# SPDX-License-Identifier: MIT

"""Tiny RV32I assembler -> program.hex for $readmemh.

Exists because hand-encoding B and J immediates is where bring-up time goes.
Run:  python gen_program.py
"""

R_OPS = {  # name: (funct7, funct3)
    "add": (0x00, 0b000), "sub": (0x20, 0b000), "sll": (0x00, 0b001),
    "slt": (0x00, 0b010), "sltu": (0x00, 0b011), "xor": (0x00, 0b100),
    "srl": (0x00, 0b101), "sra": (0x20, 0b101), "or": (0x00, 0b110),
    "and": (0x00, 0b111),
}
I_OPS = {"addi": 0b000, "slti": 0b010, "sltiu": 0b011, "xori": 0b100,
         "ori": 0b110, "andi": 0b111}
B_OPS = {"beq": 0b000, "bne": 0b001, "blt": 0b100,
         "bge": 0b101, "bltu": 0b110, "bgeu": 0b111}

def r(name, rd, rs1, rs2):
    f7, f3 = R_OPS[name]
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0b0110011

def i(name, rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (I_OPS[name] << 12) | (rd << 7) | 0b0010011

LOAD_OPS = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
STORE_OPS = {"sb": 0b000, "sh": 0b001, "sw": 0b010}

def load(name, rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (LOAD_OPS[name] << 12) | \
           (rd << 7) | 0b0000011

def store(name, rs2, rs1, imm):
    imm &= 0xFFF
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (STORE_OPS[name] << 12) | ((imm & 0x1F) << 7) | 0b0100011

def lw(rd, rs1, imm):
    return load("lw", rd, rs1, imm)

def sw(rs2, rs1, imm):
    return store("sw", rs2, rs1, imm)

def slli(rd, rs1, shamt):
    return ((shamt & 0x1F) << 20) | (rs1 << 15) | (0b001 << 12) | (rd << 7) | 0b0010011

def srli(rd, rs1, shamt):
    return ((shamt & 0x1F) << 20) | (rs1 << 15) | (0b101 << 12) | (rd << 7) | 0b0010011

def srai(rd, rs1, shamt):
    return (0x20 << 25) | ((shamt & 0x1F) << 20) | (rs1 << 15) | \
           (0b101 << 12) | (rd << 7) | 0b0010011

def jalr(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0b000 << 12) | (rd << 7) | 0b1100111

def b(name, rs1, rs2, off):
    off &= 0x1FFF                       # 13-bit signed, bit 0 implicit 0
    return (((off >> 12) & 1) << 31) | (((off >> 5) & 0x3F) << 25) | \
           (rs2 << 20) | (rs1 << 15) | (B_OPS[name] << 12) | \
           (((off >> 1) & 0xF) << 8) | (((off >> 11) & 1) << 7) | 0b1100011

def jal(rd, off):
    off &= 0x1FFFFF                     # 21-bit signed, bit 0 implicit 0
    return (((off >> 20) & 1) << 31) | (((off >> 1) & 0x3FF) << 21) | \
           (((off >> 11) & 1) << 20) | (((off >> 12) & 0xFF) << 12) | \
           (rd << 7) | 0b1101111

def lui(rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | 0b0110111

def auipc(rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | 0b0010111

# the program Every line is here to exercise one mechanism; the comment says which
PROGRAM = [
    (i("addi", 1, 0, 5),      "x1 = 5"),
    (i("addi", 2, 0, 7),      "x2 = 7"),
    (r("add", 3, 1, 2),       "x3 = 12   forward dist 1 and dist 2"),
    (r("sub", 4, 3, 1),       "x4 = 7    forward dist 1 from x3"),
    (i("addi", 5, 0, 0),      "x5 = 0    base address"),
    (sw(3, 5, 0),             "mem[0] = 12"),
    (lw(6, 5, 0),             "x6 = 12"),
    (r("add", 7, 6, 2),       "x7 = 19   LOAD-USE stall"),
    (b("beq", 1, 1, 8),       "taken, skip the next instruction"),
    (i("addi", 8, 0, 99),     "skipped"),
    (i("addi", 8, 0, 42),     "x8 = 42"),
    (b("bne", 1, 1, 8),       "not taken"),
    (i("addi", 9, 0, 1),      "x9 = 1"),
    (jal(10, 8),              "x10 = pc+4 = 56, jump over the next"),
    (i("addi", 11, 0, 77),    "skipped"),
    (i("addi", 11, 0, 3),     "x11 = 3"),
    (i("addi", 13, 0, 9),     "x13 = 9   producer for the distance-3 test"),
    (i("addi", 14, 0, 1),     "filler"),
    (i("addi", 15, 0, 2),     "filler"),
    (r("add", 16, 13, 0),     "x16 = 9   DISTANCE 3 -- needs the regfile bypass"),
    (lui(17, 0x12345),        "x17 = 0x12345000"),
    (auipc(18, 0),            "x18 = 84  pc-relative"),
    (b("beq", 0, 0, 0),       "halt -- branch to self"),
]

# the sub-word memory program program.hex above is LW/SW only, so it proves nothing about the aligner
MEM_BASE_WORD = 0x80817F01

def find(program, prefix):
    """Index of the one instruction whose note starts with `prefix`.

    PC-relative instructions are patched by name rather than written with a
    literal offset, so inserting an instruction anywhere above a jump cannot
    silently retarget it. Raises rather than guessing if the note is ambiguous.
    """
    hits = [n for n, (_, note) in enumerate(program) if note.startswith(prefix)]
    if len(hits) != 1:
        raise ValueError(f"{prefix!r} matched {len(hits)} instructions, need exactly 1")
    return hits[0]

def patch(program, idx, word):
    program[idx] = (word, program[idx][1])

MEM_PROGRAM = [
    (i("addi", 5, 0, 0),         "x5 = 0    base address"),
    (lui(1, 0x80818),            "upper, pre-incremented for the borrow"),
    (i("addi", 1, 1, -255),      "x1 = 0x80817F01"),
    (sw(1, 5, 0),                "mem[0] = 0x80817F01"),

    (load("lb",  6, 5, 0),       "x6  = 0x00000001   byte 0, positive"),
    (load("lb",  7, 5, 1),       "x7  = 0x0000007f   byte 1, offset 1"),
    (load("lb",  8, 5, 2),       "x8  = 0xffffff81   byte 2, SIGN EXTEND"),
    (load("lb",  9, 5, 3),       "x9  = 0xffffff80   byte 3, SIGN EXTEND"),
    (load("lbu", 10, 5, 2),      "x10 = 0x00000081   same byte, ZERO EXTEND"),
    (load("lbu", 11, 5, 3),      "x11 = 0x00000080"),

    (load("lh",  12, 5, 0),      "x12 = 0x00007f01   half 0, positive"),
    (load("lh",  13, 5, 2),      "x13 = 0xffff8081   half 1, SIGN EXTEND"),
    (load("lhu", 14, 5, 2),      "x14 = 0x00008081   same half, ZERO EXTEND"),

    (i("addi", 2, 0, 0xAA),      "x2 = 0xaa   store payload"),
    (sw(1, 5, 4),                "mem[4] = 0x80817F01   fresh copy"),
    (store("sb", 2, 5, 4),       "byte store, lane 0"),
    (lw(15, 5, 4),               "x15 = 0x80817faa   OTHER LANES MUST SURVIVE"),
    (store("sb", 2, 5, 6),       "byte store, lane 2"),
    (lw(16, 5, 4),               "x16 = 0x80aa7faa"),

    (i("addi", 3, 0, 0x123),     "x3 = 0x123"),
    (sw(1, 5, 8),                "mem[8] = 0x80817F01"),
    (store("sh", 3, 5, 8),       "half store, lower"),
    (lw(17, 5, 8),               "x17 = 0x80810123   upper half must survive"),
    (store("sh", 3, 5, 10),      "half store, upper"),
    (lw(18, 5, 8),               "x18 = 0x01230123"),

    (load("lb", 19, 5, 2),       "x19 = 0xffffff81"),
    (i("addi", 20, 19, 1),       "x20 = 0xffffff82  LOAD-USE on a sub-word load"),

    (srai(21, 1, 4),             "x21 = 0xf80817f0  arithmetic shift, negative"),
    (srli(22, 1, 4),             "x22 = 0x080817f0  logical shift, same operand"),
    (slli(23, 2, 4),             "x23 = 0x00000aa0"),
    (r("slt",  24, 1, 0),        "x24 = 1   x1 is negative signed"),
    (r("sltu", 25, 1, 0),        "x25 = 0   x1 is large unsigned"),

    (auipc(26, 0),               "x26 = auipc, this instruction's pc"),
    (0,                          "x27 = link; JALR jumps over the next"),
    (i("addi", 28, 0, 99),       "skipped"),
    (i("addi", 28, 0, 7),        "x28 = 7   JALR target"),

    (b("beq", 0, 0, 0),          "halt -- branch to self"),
]

_auipc = find(MEM_PROGRAM, "x26 = auipc")
_jalr = find(MEM_PROGRAM, "x27 = link")
patch(MEM_PROGRAM, _jalr,
      jalr(27, 26, (find(MEM_PROGRAM, "x28 = 7") - _auipc) * 4))

# the coverage program The two programs above leave holes that are invisible from a pass/fail line: only BEQ and BNE are ever used, no byte store lands on an odd offset, and no store or jump register ever takes a forwarded operand
COV_LOOP_ITERS = 6

COV_PROGRAM = [
    (i("addi", 1, 0, 5),       "x1 = 5"),
    (i("addi", 2, 0, 7),       "x2 = 7"),
    (i("addi", 3, 0, -3),      "x3 = -3   negative: separates signed from unsigned"),
    (i("addi", 28, 0, COV_LOOP_ITERS), "x28 = loop counter"),

    # Each condition twice: once taken, once not
    (b("beq", 1, 1, 8),        "BEQ taken"),
    (i("addi", 10, 0, 99),     "skipped"),
    (b("beq", 1, 2, 8),        "BEQ not taken"),
    (i("addi", 11, 0, 1),      "x11 = 1"),
    (b("bne", 1, 2, 8),        "BNE taken"),
    (i("addi", 12, 0, 99),     "skipped"),
    (b("bne", 1, 1, 8),        "BNE not taken"),
    (i("addi", 13, 0, 1),      "x13 = 1"),
    (b("blt", 3, 1, 8),        "BLT taken      -3 < 5 signed"),
    (i("addi", 14, 0, 99),     "skipped"),
    (b("blt", 1, 3, 8),        "BLT not taken"),
    (i("addi", 15, 0, 1),      "x15 = 1"),
    (b("bge", 1, 3, 8),        "BGE taken       5 >= -3 signed"),
    (i("addi", 16, 0, 99),     "skipped"),
    (b("bge", 3, 1, 8),        "BGE not taken"),
    (i("addi", 17, 0, 1),      "x17 = 1"),
    (b("bltu", 1, 3, 8),       "BLTU taken      5 < 0xfffffffd unsigned"),
    (i("addi", 18, 0, 99),     "skipped"),
    (b("bltu", 3, 1, 8),       "BLTU not taken"),
    (i("addi", 19, 0, 1),      "x19 = 1"),
    (b("bgeu", 3, 1, 8),       "BGEU taken      0xfffffffd >= 5 unsigned"),
    (i("addi", 20, 0, 99),     "skipped"),
    (b("bgeu", 1, 3, 8),       "BGEU not taken"),
    (i("addi", 21, 0, 1),      "x21 = 1"),

    (i("addi", 28, 28, -1),    "decrement"),
    (0,                        "loop back -- BRANCH on a forwarded operand"),

    (i("addi", 5, 0, 0),       "x5 = 0    base address"),
    (r("add", 22, 1, 2),       "x22 = 12"),
    (sw(22, 5, 0),             "STORE with forwarded rs2, distance 1"),
    (i("addi", 23, 0, 0xAA),   "x23 = 0xaa"),
    (store("sb", 23, 5, 1),    "byte store, ODD offset 1"),
    (store("sb", 23, 5, 3),    "byte store, offset 3 -- top lane"),
    (load("lbu", 24, 5, 0),    "x24 = 0x0000000c   LBU offset 0"),
    (load("lbu", 25, 5, 1),    "x25 = 0x000000aa   LBU offset 1"),
    (load("lhu", 26, 5, 0),    "x26 = 0x0000aa0c   LHU offset 0"),
    (load("lh",  27, 5, 0),    "x27 = 0x0000aa0c   LH offset 0"),

    # the forwarding matrix Every instruction class that reads a register, against both forwarding paths
    (i("addi", 9, 0, 0),       "base for the load/store forwarding cases"),
    (lw(30, 9, 0),             "LOAD  rs1 forwarded, distance 1"),
    (i("addi", 9, 0, 0),       "base again"),
    (i("addi", 31, 0, 0),      "filler -- pushes the producer to MEM/WB"),
    (lw(30, 9, 0),             "LOAD  rs1 forwarded, distance 2"),

    (i("addi", 9, 0, 24),      "base"),
    (sw(1, 9, 0),              "STORE rs1 forwarded, distance 1"),
    (i("addi", 9, 0, 28),      "base"),
    (i("addi", 31, 0, 0),      "filler"),
    (sw(1, 9, 0),              "STORE rs1 forwarded, distance 2"),
    (i("addi", 9, 0, 32),      "data"),
    (i("addi", 31, 0, 0),      "filler"),
    (sw(9, 5, 32),             "STORE rs2 forwarded, distance 2"),

    (i("addi", 9, 0, 5),       "x9 = 5, matches x1"),
    (b("beq", 1, 9, 8),        "BRANCH rs2 forwarded, distance 1 -- taken"),
    (i("addi", 31, 0, 99),     "skipped"),
    (i("addi", 9, 0, 5),       "x9 = 5"),
    (i("addi", 31, 0, 0),      "filler"),
    (b("beq", 9, 1, 8),        "BRANCH rs1 forwarded, distance 2 -- taken"),
    (i("addi", 31, 0, 99),     "skipped"),

    (i("addi", 9, 0, 5),       "x9 = 5"),
    (i("addi", 31, 0, 0),      "filler"),
    (b("beq", 1, 9, 8),        "BRANCH rs2 forwarded, distance 2 -- taken"),
    (i("addi", 31, 0, 99),     "skipped"),

    (i("addi", 9, 0, 3),       "x9 = 3"),
    (i("addi", 31, 0, 0),      "filler"),
    (r("add", 30, 1, 9),       "R-type rs2 forwarded, distance 2"),

    (auipc(6, 0),              "x6 = auipc, this instruction's pc"),
    (0,                        "x7 = link; JALR on a forwarded rs1, distance 1"),
    (i("addi", 8, 0, 99),      "skipped"),
    (i("addi", 8, 0, 7),       "x8 = 7    JALR target"),

    (auipc(6, 0),              "x6 = auipc again, for the distance-2 case"),
    (i("addi", 31, 0, 0),      "filler"),
    (0,                        "x7 = link; JALR on a forwarded rs1, distance 2"),
    (i("addi", 8, 0, 99),      "skipped"),
    (i("addi", 8, 0, 21),      "x8 = 21   second JALR target"),

    # Third JALR with its producer four back -- past both forwarding paths and past the regfile's distance-3 bypass, so this is the plain register read
    (auipc(6, 0),              "x6 = auipc, far from its JALR"),
    (i("addi", 31, 0, 0),      "filler"),
    (i("addi", 31, 0, 0),      "filler"),
    (i("addi", 31, 0, 0),      "filler"),
    (0,                        "x7 = link; JALR with NO forwarding"),
    (i("addi", 8, 0, 99),      "skipped"),
    (i("addi", 8, 0, 35),      "x8 = 35   third JALR target"),

    (b("beq", 0, 0, 0),        "halt -- branch to self"),
]

patch(COV_PROGRAM, find(COV_PROGRAM, "loop back"),
      b("bne", 28, 0,
        (find(COV_PROGRAM, "BEQ taken") - find(COV_PROGRAM, "loop back")) * 4))

_cov_auipc1 = find(COV_PROGRAM, "x6 = auipc, this")
patch(COV_PROGRAM, find(COV_PROGRAM, "x7 = link; JALR on a forwarded rs1, distance 1"),
      jalr(7, 6, (find(COV_PROGRAM, "x8 = 7") - _cov_auipc1) * 4))

_cov_auipc2 = find(COV_PROGRAM, "x6 = auipc again")
patch(COV_PROGRAM, find(COV_PROGRAM, "x7 = link; JALR on a forwarded rs1, distance 2"),
      jalr(7, 6, (find(COV_PROGRAM, "x8 = 21") - _cov_auipc2) * 4))

_cov_auipc3 = find(COV_PROGRAM, "x6 = auipc, far")
patch(COV_PROGRAM, find(COV_PROGRAM, "x7 = link; JALR with NO forwarding"),
      jalr(7, 6, (find(COV_PROGRAM, "x8 = 35") - _cov_auipc3) * 4))

def emit(program, path):
    with open(path, "w") as f:
        for n, (word, note) in enumerate(program):
            f.write(f"{word:08x}\n")
            print(f"{n*4:4d}  {word:08x}  {note}")
    print(f"\n{len(program)} instructions -> {path}\n")

if __name__ == "__main__":
    emit(PROGRAM, "program.hex")
    emit(MEM_PROGRAM, "mem_program.hex")
    emit(COV_PROGRAM, "cov_program.hex")
