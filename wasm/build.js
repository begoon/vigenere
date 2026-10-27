import { mkdir, copyFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const result = Bun.spawnSync(["zig", "build", "-Doptimize=ReleaseFast"], {
  cwd: `${root}wasm`, stdout: "inherit", stderr: "inherit",
});
if (result.exitCode !== 0) process.exit(result.exitCode);
await mkdir(`${root}docs`, { recursive: true });
for (const [binary, sample] of [["vigenere", "ru"], ["vigenere-en", "en"]]) {
  await copyFile(`${root}wasm/zig-out/bin/${binary}.wasm`, `${root}docs/${binary}.wasm`);
  await copyFile(`${root}data/${sample}/crypted-${sample}.txt`, `${root}docs/crypted-${sample}.txt`);
}
console.log("Built Russian and English Wasm solvers and copied both samples.");
