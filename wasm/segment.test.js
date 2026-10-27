import { test, expect } from "bun:test";
import { gunzipSync } from "node:zlib";
import { createSegmenter, groupLetters } from "../docs/segment.js";

test("five-letter layout preserves every character and wraps at eleven groups", () => {
  const text = "АБВГД".repeat(12) + "ЕЖ";
  const grouped = groupLetters(text);
  expect(grouped.split("\n")[0].split(" ")).toHaveLength(11);
  expect(grouped.replace(/\s/g, "")).toBe(text);
  expect(groupLetters("")).toBe("");
});

test("frequency segmentation handles ambiguity, unknown spans, and productive verb forms", () => {
  const segment = createSegmenter("мама 100\nмыла 70\nраму 40\nтестировать 20\n");
  expect(segment("МАМАМЫЛАРАМУ")).toBe("МАМА МЫЛА РАМУ");
  expect(segment("ТЕСТИРОВАЛИСЬ")).toBe("ТЕСТИРОВАЛИСЬ");
  expect(segment("МАМАЧТЙМЫЛАРАМУ")).toBe("МАМА ЧТЙ МЫЛА РАМУ");
  expect(segment("")).toBe("");
  expect(() => createSegmenter("not-russian 2")).toThrow("empty");
});

test("vendored Russian dictionary preserves the golden text and recognizes technical words", async () => {
  const data = await Bun.file(new URL("../docs/ru-frequency.txt.gz", import.meta.url)).arrayBuffer();
  const segment = createSegmenter(gunzipSync(data).toString());
  const plain = (await Bun.file(new URL("../data/decrypted-ru.txt", import.meta.url)).text()).trim();
  const words = segment(plain);
  expect(words.replaceAll(" ", "")).toBe(plain);
  expect(words).toStartWith("ЕДИНИЦА КОМПИЛЯЦИИ ЭТО ЦЕПОЧКА ЗАМКНУТЫХ ПРОГРАММНЫХ СЕГМЕНТОВ");
  expect(words).toContain(" КОМПИЛИРОВАЛИСЬ ");
  expect(words).toContain(" ВСЕ ЧТЙ ОБЫЧНО ");
});
