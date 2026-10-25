#!/usr/bin/env python3
"""Ciphertext-only mixed-alphabet Vigenere attack, matching Go and Zig."""

from dataclasses import dataclass
from math import exp, inf, log
from pathlib import Path
import sys

ALPHABET = "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
MASK64 = (1 << 64) - 1
RESTARTS, ITERATIONS, EPOCH = 48, 240_000, 30_000


class Rng:
    def __init__(self, state=0x9E3779B97F4A7C15):
        self.state = state

    def next(self):
        x = self.state
        x ^= (x << 13) & MASK64
        x ^= x >> 7
        x ^= (x << 17) & MASK64
        self.state = x
        return x

    def n(self, limit):
        return self.next() % limit

    def unit(self):
        return (self.next() >> 11) / (1 << 53)

    def permutation(self):
        p = list(range(32))
        for i in range(31, 0, -1):
            j = self.n(i + 1)
            p[i], p[j] = p[j], p[i]
        return p


def normalize(data):
    if isinstance(data, bytes):
        data = data.decode("utf-8", errors="replace")
    result = []
    for c in data:
        if "А" <= c <= "Я":
            result.append(ord(c) - ord("А"))
        elif "а" <= c <= "я":
            result.append(ord(c) - ord("а"))
    if not result:
        raise ValueError("no Russian letters in input")
    return result


def read_ciphertext(filename):
    return normalize(Path(filename).read_bytes())


def index_of_coincidence(cipher, period):
    total = 0.0
    for col in range(period):
        counts = [0] * 32
        n = 0
        for i in range(col, len(cipher), period):
            counts[cipher[i]] += 1
            n += 1
        if n >= 2:
            total += sum(c * (c - 1) for c in counts) / (n * (n - 1))
    return total / period


def find_period(cipher):
    best, best_ic = 1, 0.0
    for period in range(1, min(20, len(cipher) // 20) + 1):
        ic = index_of_coincidence(cipher, period)
        if ic > 0.045:
            return period
        if ic > best_ic:
            best, best_ic = period, ic
    return best


def load_language_scores():
    tables = []
    for name, size, smoothing in (("tri", 3, 0.05), ("quad", 4, 0.02)):
        table = [log(smoothing)] * (32**size)
        for line in (
            Path(__file__)
            .with_name(name + ".txt")
            .read_text(encoding="utf-8")
            .splitlines()
        ):
            count, data = line.split(" ", 1)
            values = normalize(data)
            value = log(int(count) + smoothing)
            for start in range(0, len(values), size):
                code = 0
                for x in values[start : start + size]:
                    code = code * 32 + x
                table[code] = value
        tables.append(table)
    return tuple(tables)


def language_score(text, tri, quad):
    score = 0.0
    for i in range(len(text) - 2):
        score += 0.25 * tri[(text[i] * 32 + text[i + 1]) * 32 + text[i + 2]]
    for i in range(len(text) - 3):
        score += quad[
            ((text[i] * 32 + text[i + 1]) * 32 + text[i + 2]) * 32 + text[i + 3]
        ]
    return score


def decode(cipher, mapping, shifts):
    return [
        (mapping[c] + 32 - shifts[i % len(shifts)]) % 32 for i, c in enumerate(cipher)
    ]


@dataclass
class MutationPlan:
    positions: list
    windows: list


def make_plan(cipher, positions):
    touched = set()
    for pos in positions:
        touched.update(range(max(0, pos - 3), min(pos + 1, len(cipher) - 2)))
    return MutationPlan(positions, sorted(touched))


def mutation_plans(cipher, period):
    plans = [MutationPlan([], []) for _ in range(1024 + period)]
    columns = [i % period for i in range(len(cipher))]
    for x in range(32):
        for y in range(x + 1, 32):
            plan = make_plan(
                cipher, [i for i, c in enumerate(cipher) if c == x or c == y]
            )
            plans[x * 32 + y] = plans[y * 32 + x] = plan
    for col in range(period):
        plans[1024 + col] = make_plan(cipher, list(range(col, len(cipher), period)))
    return plans, columns


def window_score(plain, i, tri, quad):
    code = (plain[i] * 32 + plain[i + 1]) * 32 + plain[i + 2]
    score = 0.25 * tri[code]
    if i + 3 < len(plain):
        score += quad[code * 32 + plain[i + 3]]
    return score


def refresh_scores(plain, cached, tri, quad):
    score = 0.0
    for i in range(len(cached)):
        cached[i] = window_score(plain, i, tri, quad)
        score += cached[i]
    return score


def update_positions(plan, cipher, columns, mapping, shifts, plain):
    for i in plan.positions:
        plain[i] = (mapping[cipher[i]] + 32 - shifts[columns[i]]) % 32


@dataclass
class Solution:
    score: float
    mapping: list
    shifts: list
    plain: list


def crack(cipher, period, tri, quad):
    random = Rng()
    best = Solution(-inf, [], [], [])
    plans, columns = mutation_plans(cipher, period)
    cached = [0.0] * max(0, len(cipher) - 2)
    proposed = [0.0] * len(cached)
    empty_plan = MutationPlan([], [])
    for _ in range(RESTARTS):
        mapping = random.permutation()
        shifts = [0] + [random.n(32) for _ in range(period - 1)]
        plain = decode(cipher, mapping, shifts)
        score = refresh_scores(plain, cached, tri, quad)
        for iteration in range(ITERATIONS):
            if iteration % EPOCH == 0:
                score = refresh_scores(plain, cached, tri, quad)
            phase = (iteration % EPOCH) / EPOCH
            temp = 14 * (1 - phase) + 0.25
            swap = random.n(4) != 0 or period == 1
            if swap:
                x, y = random.n(32), random.n(32)
                mapping[x], mapping[y] = mapping[y], mapping[x]
                plan = plans[x * 32 + y]
            else:
                col = 1 + random.n(period - 1)
                old_shift = shifts[col]
                shifts[col] = random.n(32)
                plan = plans[1024 + col] if shifts[col] != old_shift else empty_plan
            update_positions(plan, cipher, columns, mapping, shifts, plain)
            delta = 0.0
            for j, i in enumerate(plan.windows):
                proposed[j] = window_score(plain, i, tri, quad)
                delta += proposed[j] - cached[i]
            if delta < 0 and random.unit() > exp(delta / temp):
                if swap:
                    mapping[x], mapping[y] = mapping[y], mapping[x]
                else:
                    shifts[col] = old_shift
                update_positions(plan, cipher, columns, mapping, shifts, plain)
            else:
                score += delta
                for j, i in enumerate(plan.windows):
                    cached[i] = proposed[j]
            if score > best.score:
                best = Solution(score, mapping.copy(), shifts.copy(), plain.copy())
    return best


def choose_key_rotation(solution, tri, quad):
    best, best_score = 0, -inf
    for rotation in range(32):
        candidate = [(x + rotation) % 32 for x in solution.shifts]
        score = language_score(candidate, tri, quad)
        if score > best_score:
            best, best_score = rotation, score
    return best


def letters(values):
    return "".join(ALPHABET[x] for x in values)


def format_solution(answer, period, tri, quad):
    rotation = choose_key_rotation(answer, tri, quad)
    key = letters([(x + rotation) % 32 for x in answer.shifts])
    mixed = [0] * 32
    for encrypted, pos in enumerate(answer.mapping):
        mixed[(pos + rotation) % 32] = encrypted
    return (
        f"Detected key length: {period}\nKeyword: {key}\n"
        f"Base alphabet: {letters(mixed)}\nDecrypted text:\n{letters(answer.plain)}\n"
    )


def main():
    filename = (
        sys.argv[1]
        if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "data/crypted-ru.txt"
    )
    try:
        cipher = read_ciphertext(filename)
    except (OSError, ValueError) as err:
        print(err, file=sys.stderr)
        return 1
    tri, quad = load_language_scores()
    period = find_period(cipher)
    answer = crack(cipher, period, tri, quad)
    print(format_solution(answer, period, tri, quad), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
