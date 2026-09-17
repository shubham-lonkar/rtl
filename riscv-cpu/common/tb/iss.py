# Copyright (c) 2026 Shubham Lonkar
# SPDX-License-Identifier: MIT

"""RV32I instruction set simulator -- the golden model.

Architectural only: no pipeline, no timing, no hazards. That is the point. The
RTL has to agree with this on *what* every instruction does; how many cycles it
took is a separate question, and one this model deliberately cannot answer.

Emits a retire trace, one line per instruction:

    <pc:08x> <rd:d> <value:08x>

rd = 0 means the instruction changed no architectural register -- either it has
no rd (stores, branches) or its rd is x0, which RV32I discards. Both cases look
identical from outside the machine, which is exactly what the RTL's writeback
port does too, so the comparison stays honest.

Halt is a branch-to-self: the trace ends with that instruction's first retire.

    python iss.py program.hex              -> program.trace
    python iss.py program.hex -o out.trace
"""

import argparse
import sys

MASK = 0xFFFFFFFF

def sext(value, bits):
    """Sign-extend a `bits`-wide value to a Python int."""
    sign = 1 << (bits - 1)
    return (value & (sign - 1)) - (value & sign)

class Memory:
    """Byte-addressable, sparse, little-endian. Unwritten bytes read as 0.

    Sparse because the RTL's dmem is 256 words that the testbench explicitly
    zeroes; a dict with a 0 default matches that without fixing a size here.
    """

    def __init__(self):
        self.data = {}

    def read(self, addr, nbytes):
        return sum(self.data.get(addr + k, 0) << (8 * k) for k in range(nbytes))

    def write(self, addr, value, nbytes):
        for k in range(nbytes):
            self.data[addr + k] = (value >> (8 * k)) & 0xFF

    def word(self, addr):
        return self.read(addr, 4)

class ISS:
    def __init__(self, imem_words):
        self.imem = imem_words
        self.regs = [0] * 32
        self.mem = Memory()
        self.pc = 0

    def fetch(self):
        idx = self.pc >> 2
        return self.imem[idx] if idx < len(self.imem) else 0

    def step(self):
        """Execute one instruction. Returns (pc, rd, value, halted)."""
        pc = self.pc
        instr = self.fetch()

        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        funct3 = (instr >> 12) & 0x07
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        funct7 = (instr >> 25) & 0x7F

        a = self.regs[rs1]
        b = self.regs[rs2]

        imm_i = sext(instr >> 20, 12)
        imm_s = sext(((instr >> 25) << 5) | ((instr >> 7) & 0x1F), 12)
        imm_b = sext((((instr >> 31) & 1) << 12) | (((instr >> 7) & 1) << 11) |
                     (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1), 13)
        imm_u = (instr & 0xFFFFF000)
        imm_j = sext((((instr >> 31) & 1) << 20) | (((instr >> 12) & 0xFF) << 12) |
                     (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1), 21)

        next_pc = (pc + 4) & MASK
        value = None                      # None = writes no register

        alt = bool(funct7 >> 5 & 1)

        if opcode == 0x33:                                        # R-type
            value = self.alu(funct3, alt, a, b)
        elif opcode == 0x13:                                      # I-type ALU
            is_shift = funct3 in (0x1, 0x5)
            operand = (imm_i & 0x1F) if is_shift else (imm_i & MASK)
            value = self.alu(funct3, alt and funct3 == 0x5, a, operand)
        elif opcode == 0x03:                                      # loads
            value = self.load(funct3, (a + imm_i) & MASK)
        elif opcode == 0x23:                                      # stores
            self.store(funct3, (a + imm_s) & MASK, b)
        elif opcode == 0x63:                                      # branches
            if self.branch_taken(funct3, a, b):
                next_pc = (pc + imm_b) & MASK
        elif opcode == 0x6F:                                      # JAL
            value = (pc + 4) & MASK
            next_pc = (pc + imm_j) & MASK
        elif opcode == 0x67:                                      # JALR
            value = (pc + 4) & MASK
            next_pc = (a + imm_i) & MASK & ~1        # bit 0 cleared, per spec
        elif opcode == 0x37:                                      # LUI
            value = imm_u
        elif opcode == 0x17:                                      # AUIPC
            value = (pc + imm_u) & MASK

        if value is not None and rd != 0:
            self.regs[rd] = value & MASK
            retire_rd, retire_val = rd, value & MASK
        else:
            retire_rd, retire_val = 0, 0

        self.pc = next_pc
        return pc, retire_rd, retire_val, next_pc == pc

    def alu(self, funct3, alt, a, b):
        if funct3 == 0x0:
            return (a - b) & MASK if alt else (a + b) & MASK
        if funct3 == 0x1:
            return (a << (b & 0x1F)) & MASK
        if funct3 == 0x2:
            return 1 if sext(a, 32) < sext(b, 32) else 0
        if funct3 == 0x3:
            return 1 if (a & MASK) < (b & MASK) else 0
        if funct3 == 0x4:
            return (a ^ b) & MASK
        if funct3 == 0x5:
            return (sext(a, 32) >> (b & 0x1F)) & MASK if alt else (a & MASK) >> (b & 0x1F)
        if funct3 == 0x6:
            return (a | b) & MASK
        return (a & b) & MASK                                     # 0x7

    def load(self, funct3, addr):
        if funct3 == 0x0:
            return sext(self.mem.read(addr, 1), 8) & MASK         # LB
        if funct3 == 0x1:
            return sext(self.mem.read(addr, 2), 16) & MASK        # LH
        if funct3 == 0x2:
            return self.mem.read(addr, 4)                         # LW
        if funct3 == 0x4:
            return self.mem.read(addr, 1)                         # LBU
        if funct3 == 0x5:
            return self.mem.read(addr, 2)                         # LHU
        return 0

    def store(self, funct3, addr, data):
        nbytes = {0x0: 1, 0x1: 2, 0x2: 4}.get(funct3)
        if nbytes:
            self.mem.write(addr, data, nbytes)

    def branch_taken(self, funct3, a, b):
        if funct3 == 0x0:
            return a == b                                         # BEQ
        if funct3 == 0x1:
            return a != b                                         # BNE
        if funct3 == 0x4:
            return sext(a, 32) < sext(b, 32)                      # BLT
        if funct3 == 0x5:
            return sext(a, 32) >= sext(b, 32)                     # BGE
        if funct3 == 0x6:
            return a < b                                          # BLTU
        if funct3 == 0x7:
            return a >= b                                         # BGEU
        return False

    def run(self, max_instr=100000):
        """Execute to the halt loop. Returns the retire trace."""
        trace = []
        for _ in range(max_instr):
            pc, rd, val, halted = self.step()
            trace.append((pc, rd, val))
            if halted:
                return trace
        raise RuntimeError(f"no halt within {max_instr} instructions -- "
                           "the program needs a branch-to-self to terminate")

def load_hex(path):
    words = []
    with open(path) as f:
        for line in f:
            line = line.split("//")[0].strip()
            if line:
                words.append(int(line, 16))
    return words

def main():
    ap = argparse.ArgumentParser(description="RV32I ISS -- emits a retire trace")
    ap.add_argument("hexfile")
    ap.add_argument("-o", "--out", help="trace file (default: <hexfile>.trace)")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="also print the trace and final register state")
    args = ap.parse_args()

    iss = ISS(load_hex(args.hexfile))
    trace = iss.run()

    out = args.out or args.hexfile.rsplit(".", 1)[0] + ".trace"
    with open(out, "w") as f:
        for pc, rd, val in trace:
            f.write(f"{pc:08x} {rd:d} {val:08x}\n")

    print(f"{len(trace)} instructions retired -> {out}")

    if args.verbose:
        for pc, rd, val in trace:
            change = f"x{rd} = 0x{val:08x}" if rd else "-"
            print(f"  {pc:4d}  {change}")
        print("\nfinal registers:")
        for k in range(32):
            if iss.regs[k]:
                print(f"  x{k:<2d} = 0x{iss.regs[k]:08x}")
        print("\nfinal memory (non-zero words):")
        addrs = sorted({a & ~3 for a in iss.mem.data})
        for a in addrs:
            if iss.mem.word(a):
                print(f"  mem[0x{a:04x}] = 0x{iss.mem.word(a):08x}")

    return 0

if __name__ == "__main__":
    sys.exit(main())
