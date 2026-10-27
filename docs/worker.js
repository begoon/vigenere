import { createSolver } from "./solver.js";
import { createSegmenter, groupLetters } from "./segment.js";

async function load(path, binary = false) {
  const response = await fetch(new URL(path, import.meta.url));
  if (!response.ok) throw new Error(`Could not load ${path} (${response.status}).`);
  return binary ? response.arrayBuffer() : response.text();
}

let busy = false;
self.onmessage = async ({ data }) => {
  if (busy) return;
  busy = true;
  try {
    const language = data.language === "en" ? "en" : "ru";
    const bytes = await load(language === "en" ? "vigenere-en.wasm" : "vigenere.wasm", true);
    const crack = await createSolver(bytes, (progress) => self.postMessage({ type: "progress", progress }), language);
    const result = crack(data.text);
    // A dictionary failure must not discard a successfully recovered plaintext.
    let words = "";
    let warning = "";
    try {
      const compressed = await load(`${language}-frequency.txt.gz`, true);
      const stream = new Blob([compressed]).stream().pipeThrough(new DecompressionStream("gzip"));
      const segment = createSegmenter(await new Response(stream).text(), language);
      words = segment(result.plaintext);
    } catch (error) {
      warning = `Cracking succeeded, but word spacing is unavailable: ${error.message}`;
    }
    self.postMessage({ type: "result", ...result, grouped: groupLetters(result.plaintext), words, warning });
  } catch (error) {
    self.postMessage({ type: "error", message: error.message });
  } finally {
    busy = false;
  }
};
