"""Algorithm parity tests; VIGENERE_INTEGRATION=1 also runs the full search."""

import math
import os
from pathlib import Path
import unittest

import main as v

DATA = Path(__file__).resolve().parent.parent / "data"


class CrackerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tri, cls.quad = v.load_language_scores()

    def test_normalization(self):
        self.assertEqual(
            v.normalize("А я Ёё!".encode() + b"\xff" + "Б".encode() + b"\xd0"),
            [0, 31, 1],
        )
        for data in (b"", b"abc", "Ёё"):
            with self.assertRaisesRegex(ValueError, "no Russian letters"):
                v.normalize(data)

    def test_period(self):
        cipher = v.read_ciphertext(DATA / "crypted-ru.txt")
        self.assertEqual(len(cipher), 738)
        self.assertEqual(v.find_period(cipher), 7)
        self.assertEqual(v.find_period([0]), 1)
        self.assertEqual(v.index_of_coincidence([i % 7 for i in range(140)], 7), 1.0)

    def test_rotation_invariance(self):
        cipher, mapping, shifts = [0, 31, 2, 3], list(range(32)), [1, 3]
        plain = v.decode(cipher, mapping, shifts)
        self.assertEqual(plain, [31, 28, 1, 0])
        self.assertEqual(
            v.decode(cipher, [(x + 5) % 32 for x in mapping], [6, 8]), plain
        )

    def test_language_scores(self):
        code = 0
        for x in v.normalize("ЕНИЯ"):
            code = code * 32 + x
        self.assertAlmostEqual(self.quad[code], math.log(2173.02), delta=1e-12)
        self.assertEqual(v.language_score([0, 1], self.tri, self.quad), 0.0)
        self.assertEqual(self.quad[0], math.log(0.02))

    def test_rng(self):
        rng = v.Rng()
        self.assertEqual(
            [rng.next() for _ in range(3)],
            [
                0xDC1B77AE0BF34DAD,
                0x64F0EEB9026E6076,
                0x7B07CE91E5906136,
            ],
        )

    def test_incremental_scores(self):
        # Same lengths, periods, seed, mutations, and commit/rollback sequence
        # as Go's TestIncrementalScores and Zig's corresponding test.
        tri, quad = self.tri, self.quad
        for n in (1, 2, 3, 4, 17, 80, 738):
            for period in (1, 3, 7):
                with self.subTest(length=n, period=period):
                    random = v.Rng(12345)
                    cipher = [random.n(32) for _ in range(n)]
                    mapping = random.permutation()
                    shifts = [random.n(32) for _ in range(period)]
                    plain = v.decode(cipher, mapping, shifts)
                    plans, columns = v.mutation_plans(cipher, period)
                    cached = [0.0] * max(0, n - 2)
                    score = v.refresh_scores(plain, cached, tri, quad)
                    for step in range(3 * len(plans)):
                        idx = step % len(plans)
                        plan = plans[idx]
                        if idx < 1024:
                            x, y = divmod(idx, 32)
                            mapping[x], mapping[y] = mapping[y], mapping[x]
                        else:
                            col = idx - 1024
                            old_shift = shifts[col]
                            shifts[col] = random.n(32)
                        v.update_positions(
                            plan, cipher, columns, mapping, shifts, plain
                        )
                        proposed = []
                        delta = 0.0
                        for i in plan.windows:
                            value = v.window_score(plain, i, tri, quad)
                            proposed.append(value)
                            delta += value - cached[i]
                        self.assertAlmostEqual(
                            score + delta,
                            v.language_score(plain, tri, quad),
                            delta=1e-7,
                        )
                        if step % 3 == 0:
                            if idx < 1024:
                                mapping[x], mapping[y] = mapping[y], mapping[x]
                            else:
                                shifts[col] = old_shift
                            v.update_positions(
                                plan, cipher, columns, mapping, shifts, plain
                            )
                        else:
                            score += delta
                            for j, i in enumerate(plan.windows):
                                cached[i] = proposed[j]
                        self.assertEqual(plain, v.decode(cipher, mapping, shifts))
                        self.assertAlmostEqual(
                            score, v.language_score(plain, tri, quad), delta=1e-7
                        )
                        self.assertEqual(
                            cached,
                            [
                                v.window_score(plain, i, tri, quad)
                                for i in range(len(cached))
                            ],
                        )

    @unittest.skipUnless(
        os.environ.get("VIGENERE_INTEGRATION") == "1", "full search is opt-in"
    )
    def test_full_recovery(self):
        cipher = v.read_ciphertext(DATA / "crypted-ru.txt")
        period = v.find_period(cipher)
        answer = v.crack(cipher, period, self.tri, self.quad)
        expected = (
            "Detected key length: 7\nKeyword: РЕДИСКА\n"
            "Base alphabet: ЕХЭЦРБТИОНЪДФГЩЯВУЗШЬЖКЛМПЫЮСЙЧА\nDecrypted text:\n"
            + (DATA / "decrypted-ru.txt").read_text(encoding="utf-8").strip()
            + "\n"
        )
        self.assertEqual(
            v.format_solution(answer, period, self.tri, self.quad), expected
        )


if __name__ == "__main__":
    unittest.main()
