// Shared by Bun and the browser worker. All views are recreated after memory growth.
export async function createSolver(bytes, onProgress = () => {}) {
  const { instance } = await WebAssembly.instantiate(bytes, {
    env: { progress: (completed) => onProgress(completed / 48) },
  });
  const api = instance.exports;
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  function read(pointer, length) {
    return decoder.decode(new Uint8Array(api.memory.buffer, pointer, length));
  }
  return (text) => {
    const input = encoder.encode(text);
    if (input.length > api.input_capacity()) throw new Error("Input exceeds 32 KiB.");
    const count = (text.match(/[А-Яа-я]/g) || []).length;
    if (!count) throw new Error("No Russian letters in input.");
    if (count > 4096) throw new Error("Use at most 4,096 Russian letters.");
    new Uint8Array(api.memory.buffer, api.input_ptr(), input.length).set(input);
    const status = api.crack(input.length);
    if (status) throw new Error([
      "", "No Russian letters in input.", "Input is too long.", "Solver ran out of memory.",
    ][status] || "Solver failed.");
    const period = api.key_length();
    return {
      period,
      keyword: read(api.keyword_ptr(), period * 2),
      alphabet: read(api.alphabet_ptr(), 64),
      plaintext: read(api.plaintext_ptr(), api.plaintext_len()),
    };
  };
}

export function formatResult(result) {
  return `Detected key length: ${result.period}\nKeyword: ${result.keyword}\nBase alphabet: ${result.alphabet}\nDecrypted text:\n${result.plaintext}\n`;
}
