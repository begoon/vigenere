import { createSolver, formatResult } from "../docs/solver.js";

try {
  const args = process.argv.slice(2);
  const language = args[0] === "--english" ? (args.shift(), "en") : "ru";
  const filename = args[0] || new URL(`../data/${language}/crypted-${language}.txt`, import.meta.url);
  const wasmPath = process.env.VIGENERE_WASM || new URL(`../docs/${language === "en" ? "vigenere-en" : "vigenere"}.wasm`, import.meta.url);
  const [bytes, text] = await Promise.all([
    Bun.file(wasmPath).arrayBuffer(), Bun.file(filename).text(),
  ]);
  const crack = await createSolver(bytes, undefined, language);
  process.stdout.write(formatResult(crack(text)));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
