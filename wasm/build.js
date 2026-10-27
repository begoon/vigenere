import { mkdir, copyFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const result = Bun.spawnSync(["zig", "build", "-Doptimize=ReleaseFast"], {
  cwd: `${root}wasm`, stdout: "inherit", stderr: "inherit",
});
if (result.exitCode !== 0) process.exit(result.exitCode);
await mkdir(`${root}docs`, { recursive: true });
await copyFile(`${root}wasm/zig-out/bin/vigenere.wasm`, `${root}docs/vigenere.wasm`);
await copyFile(`${root}data/crypted-ru.txt`, `${root}docs/crypted-ru.txt`);
console.log("Built docs/vigenere.wasm and copied the sample ciphertext.");
