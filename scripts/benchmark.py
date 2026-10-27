"""Benchmark matching ciphertext-only implementations; builds are not timed."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent


def command(args, cwd=ROOT, **kwargs):
    return subprocess.run(args, cwd=cwd, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--languages",
        nargs="+",
        choices=("go", "zig", "vlang", "wasm"),
        default=["go", "zig", "vlang", "wasm"],
    )
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--input", type=Path, default=ROOT / "data/crypted-ru.txt")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.runs < 1 or args.warmups < 0:
        parser.error("--runs must be positive and --warmups must be nonnegative")
    ciphertext = args.input.resolve()
    with tempfile.TemporaryDirectory(prefix="vigenere-bench-") as tmp:
        tmp = Path(tmp)
        env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(tmp / "zig-cache"))
        commands = {}
        versions = {}
        if "go" in args.languages:
            command(["go", "build", "-o", str(tmp / "go-crack"), "."], ROOT / "go")
            commands["Go"] = [str(tmp / "go-crack")]
            versions["Go"] = command(
                ["go", "version"], capture_output=True, text=True
            ).stdout.strip()
        if "zig" in args.languages:
            command(
                [
                    "zig",
                    "build",
                    "-Doptimize=ReleaseFast",
                    "--prefix",
                    str(tmp / "zig"),
                ],
                ROOT / "zig",
                env=env,
            )
            commands["Zig"] = [str(tmp / "zig/bin/vigenerecrack")]
            versions["Zig"] = command(
                ["zig", "version"], capture_output=True, text=True
            ).stdout.strip()
        if "vlang" in args.languages:
            command(["v", "-prod", "-o", str(tmp / "v-crack"), str(ROOT / "vlang")])
            commands["V"] = [str(tmp / "v-crack")]
            versions["V"] = command(
                ["v", "version"], capture_output=True, text=True
            ).stdout.strip()
        if "wasm" in args.languages:
            command(
                [
                    "zig",
                    "build",
                    "-Doptimize=ReleaseFast",
                    "--prefix",
                    str(tmp / "wasm"),
                ],
                ROOT / "wasm",
                env=env,
            )
            commands["Wasm (Bun)"] = ["bun", str(ROOT / "wasm/cli.js")]
            env["VIGENERE_WASM"] = str(tmp / "wasm/bin/vigenere.wasm")
            versions["Wasm (Bun)"] = (
                "Zig "
                + command(
                    ["zig", "version"], capture_output=True, text=True
                ).stdout.strip()
                + "; Bun "
                + command(
                    ["bun", "--version"], capture_output=True, text=True
                ).stdout.strip()
            )
        expected = None
        known_input = (
            hashlib.sha256(ciphertext.read_bytes()).digest()
            == hashlib.sha256((ROOT / "data/crypted-ru.txt").read_bytes()).digest()
        )
        if known_input:
            expected = (
                "Detected key length: 7\nKeyword: РЕДИСКА\n"
                "Base alphabet: ЕХЭЦРБТИОНЪДФГЩЯВУЗШЬЖКЛМПЫЮСЙЧА\nDecrypted text:\n"
                + (ROOT / "data/decrypted-ru.txt").read_text(encoding="utf-8").strip()
                + "\n"
            ).encode()
        samples = {name: [] for name in commands}
        for round_number in range(args.warmups + args.runs):
            order = (
                list(commands) if round_number % 2 == 0 else list(reversed(commands))
            )
            for name in order:
                label = (
                    "warmup"
                    if round_number < args.warmups
                    else f"run {round_number - args.warmups + 1}"
                )
                print(f"Starting {name} {label}...", flush=True)
                start = time.perf_counter()
                result = command(
                    [*commands[name], str(ciphertext)], stdout=subprocess.PIPE, env=env
                )
                elapsed = time.perf_counter() - start
                if expected is None:
                    expected = result.stdout
                if result.stdout != expected:
                    raise RuntimeError(
                        f"{name} output differs from the expected solution"
                    )
                if round_number >= args.warmups:
                    samples[name].append(elapsed)
                print(f"{name} {label}: {elapsed:.3f}s (output verified)", flush=True)
        report = {
            "implementation": "precomputed mutation plans and incremental scoring",
            "platform": platform.platform(),
            "versions": versions,
            "input": (
                str(ciphertext.relative_to(ROOT))
                if ciphertext.is_relative_to(ROOT)
                else str(ciphertext)
            ),
            "input_sha256": hashlib.sha256(ciphertext.read_bytes()).hexdigest(),
            "output_sha256": hashlib.sha256(expected).hexdigest(),
            "warmups_per_implementation": args.warmups,
            "seconds": samples,
            "median_seconds": {
                name: statistics.median(values) for name, values in samples.items()
            },
        }
        print(json.dumps(report, indent=2))
        if args.output:
            args.output.write_text(
                json.dumps(report, indent=2) + "\n", encoding="utf-8"
            )


if __name__ == "__main__":
    main()
