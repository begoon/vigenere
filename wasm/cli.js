import { createSolver, formatResult } from "../docs/solver.js";

try {
  const filename = process.argv[2] || new URL("../data/ru/crypted-ru.txt", import.meta.url);
  const wasmPath = process.env.VIGENERE_WASM || new URL("../docs/vigenere.wasm", import.meta.url);
  const [bytes, text] = await Promise.all([
    Bun.file(wasmPath).arrayBuffer(), Bun.file(filename).text(),
  ]);
  const crack = await createSolver(bytes);
  process.stdout.write(formatResult(crack(text)));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
