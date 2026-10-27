export function groupLetters(text, groupsPerLine = 11) {
  const groups = text.match(/.{1,5}/gu) || [];
  const lines = [];
  for (let i = 0; i < groups.length; i += groupsPerLine) {
    lines.push(groups.slice(i, i + groupsPerLine).join(" "));
  }
  return lines.join("\n");
}

// Unigram Viterbi segmentation. Unknown letters remain literal, never corrected.
export function createSegmenter(data, language = "ru") {
  if (!["ru", "en"].includes(language)) throw new Error("Unsupported language.");
  const english = language === "en";
  const alphabet = english ? /^[A-Z]+$/ : /^[А-Я]+$/;
  const singles = english ? "AI" : "АВИКОСУЯ";
  const frequencies = new Map();
  let total = 0;
  let maxLength = 1;
  for (const line of data.split(/\r?\n/)) {
    const [raw, countText] = line.trim().split(/\s+/);
    if (!raw) continue;
    const word = raw.toUpperCase().replaceAll("Ё", "Е");
    const count = Number(countText);
    if (!alphabet.test(word) || !Number.isFinite(count) || count <= 0) continue;
    if (word.length === 1 && !singles.includes(word)) continue;
    frequencies.set(word, (frequencies.get(word) || 0) + count);
    total += count;
    maxLength = Math.max(maxLength, word.length);
  }
  if (!total) throw new Error(`The ${english ? "English" : "Russian"} dictionary is empty.`);
  // Productive forms of -овать/-ировать verbs, including rare technical verbs.
  // This is a general morphology fallback, not a list of expected puzzle words.
  for (const [word, count] of [...frequencies]) {
    if (english || !word.endsWith("ОВАТЬ")) continue;
    const stem = word.slice(0, -3);
    for (const ending of ["АЛ", "АЛА", "АЛО", "АЛИ", "АЛСЯ", "АЛАСЬ", "АЛОСЬ", "АЛИСЬ", "АН", "АНА", "АНО", "АНЫ"]) {
      const form = stem + ending;
      if (!frequencies.has(form)) frequencies.set(form, Math.max(1, count / 4));
      maxLength = Math.max(maxLength, form.length);
    }
  }
  const costs = new Map([...frequencies].map(([word, count]) => [word, Math.log(total / count)]));
  return (text) => {
    const score = new Float64Array(text.length + 1).fill(Infinity);
    const previous = new Int32Array(text.length + 1);
    const unknown = new Uint8Array(text.length + 1);
    score[0] = 0;
    for (let end = 1; end <= text.length; end++) {
      // An unknown span costs less than inventing a string of tiny words.
      for (let start = Math.max(0, end - 24); start < end; start++) {
        const cost = score[start] + 20 + 4 * (end - start);
        if (cost < score[end]) {
          score[end] = cost;
          previous[end] = start;
          unknown[end] = 1;
        }
      }
      for (let start = Math.max(0, end - maxLength); start < end; start++) {
        const cost = costs.get(text.slice(start, end));
        if (cost !== undefined && score[start] + cost < score[end]) {
          score[end] = score[start] + cost;
          previous[end] = start;
          unknown[end] = 0;
        }
      }
    }
    const tokens = [];
    for (let end = text.length; end > 0;) {
      const start = previous[end];
      tokens.push({ text: text.slice(start, end), unknown: !!unknown[end] });
      end = start;
    }
    tokens.reverse();
    const joined = [];
    let lastUnknown = false;
    for (const token of tokens) {
      if (token.unknown && lastUnknown) joined[joined.length - 1] += token.text;
      else joined.push(token.text);
      lastUnknown = token.unknown;
    }
    return joined.join(" ");
  };
}
