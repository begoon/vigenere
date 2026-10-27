import { test, expect } from "bun:test";
import { createSolver, formatResult } from "../docs/solver.js";

const bytes = await Bun.file(new URL("../docs/vigenere.wasm", import.meta.url)).arrayBuffer();

test("ABI rejects empty and oversized inputs and clears stale result lengths", async () => {
  const { instance } = await WebAssembly.instantiate(bytes, { env: { progress() {} } });
  const api = instance.exports;
  expect(api.crack(0)).toBe(1);
  expect(api.crack(api.input_capacity() + 1)).toBe(2);
  const input = new TextEncoder().encode("А".repeat(4097));
  new Uint8Array(api.memory.buffer, api.input_ptr(), input.length).set(input);
  expect(api.crack(input.length)).toBe(2);
  expect(api.plaintext_len()).toBe(0);
  expect(api.key_length()).toBe(0);
});

test("wrapper validates input and supports repeated calls after memory growth", async () => {
  const progress = [];
  const crack = await createSolver(bytes, (value) => progress.push(value));
  expect(() => crack("abc Ёё")).toThrow("No Russian letters");
  expect(() => crack("А".repeat(4097))).toThrow("4,096");
  expect(() => crack(" ".repeat(32769))).toThrow("32 KiB");
  for (const text of ["аЁя!", "А"]) {
    const result = crack(text);
    expect(result.period).toBe(1);
    expect(result.plaintext.length).toBe(text === "А" ? 1 : 2);
    expect(result.alphabet.length).toBe(32);
    expect(new Set(result.alphabet).size).toBe(32);
    expect(progress.at(-1)).toBe(1);
  }
});

const integration = process.env.VIGENERE_INTEGRATION === "1" ? test : test.skip;
integration("full search matches the native CLI and every golden plaintext letter", async () => {
  const cipher = await Bun.file(new URL("../data/ru/crypted-ru.txt", import.meta.url)).text();
  const expected = (await Bun.file(new URL("../data/ru/decrypted-ru.txt", import.meta.url)).text()).trim();
  const crack = await createSolver(bytes);
  const result = crack(cipher);
  expect(formatResult(result)).toBe(
    `Detected key length: 7\nKeyword: РЕДИСКА\nBase alphabet: ЕХЭЦРБТИОНЪДФГЩЯВУЗШЬЖКЛМПЫЮСЙЧА\nDecrypted text:\n${expected}\n`,
  );
}, 120000);

const englishBytes = await Bun.file(new URL("../docs/vigenere-en.wasm", import.meta.url)).arrayBuffer();
test("English ABI and wrapper enforce their alphabet and input limits", async () => {
  const { instance } = await WebAssembly.instantiate(englishBytes, { env: { progress() {} } });
  const api = instance.exports;
  expect(api.crack(0)).toBe(1);
  expect(api.crack(api.input_capacity() + 1)).toBe(2);
  expect(api.alphabet_len()).toBe(26);
  const input = new TextEncoder().encode("A".repeat(4097));
  new Uint8Array(api.memory.buffer, api.input_ptr(), input.length).set(input);
  expect(api.crack(input.length)).toBe(2);
  expect(api.plaintext_len()).toBe(0);
  const crack = await createSolver(englishBytes, undefined, "en");
  expect(() => crack("АБВ Ёё")).toThrow("No English letters");
  expect(() => crack("A".repeat(4097))).toThrow("4,096");
});
integration("English search returns all 650 fixture letters and supports reuse", async () => {
  const progress = [];
  const crack = await createSolver(englishBytes, x => progress.push(x), "en");
  const cipher = await Bun.file(new URL("../data/en/crypted-en.txt", import.meta.url)).text();
  const plain = (await Bun.file(new URL("../data/en/decrypted-en.txt", import.meta.url)).text()).trim();
  const result = crack(cipher);
  expect(result.keyword).toBe("COMPILE");
  expect(result.alphabet).toBe("EXACRBTIONDFGWVYZHJKLMPQUS");
  expect(result.plaintext).toBe(plain);
  expect(result.plaintext).toEndWith("FINIHARI");
  expect(progress.at(-1)).toBe(1);
  expect(progress.every((x, i) => !i || x >= progress[i - 1])).toBe(true);
  const short = crack("a");
  expect(short.plaintext).toHaveLength(1);
  expect(short.period).toBe(1);
}, 120000);
