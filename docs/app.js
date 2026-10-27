const $ = (id) => document.getElementById(id);
let worker = null;
let started = 0;
let sample = "";
function fitTextarea(textarea) {
  const borders = textarea.offsetHeight - textarea.clientHeight;
  textarea.style.height = "auto";
  textarea.style.height = `${textarea.scrollHeight + borders}px`;
}
function fitTextareas() {
  for (const textarea of document.querySelectorAll("textarea")) fitTextarea(textarea);
}
window.addEventListener("resize", fitTextareas);
document.fonts.ready.then(fitTextareas);
const count = () => {
  const letters = ($("ciphertext").value.match(/[А-Яа-я]/g) || []).length;
  $("letter-count").textContent = `${letters.toLocaleString()} letters`;
  fitTextarea($("ciphertext"));
};
function status(text, error = false) {
  $("status").textContent = text;
  $("status").classList.toggle("error", error);
}
function busy(value) {
  $("crack").disabled = value;
  $("sample").disabled = value || !sample;
  $("ciphertext").readOnly = value;
  $("cancel").hidden = !value;
  $("progress").hidden = !value;
}
function clearResult() {
  $("keyword").textContent = "—";
  $("alphabet").textContent = "—";
  $("period").textContent = "Waiting for a discovery";
  $("grouped").value = "";
  $("words").value = "";
  fitTextareas();
  for (const button of document.querySelectorAll(".copy")) button.disabled = true;
}
function finish() {
  worker?.terminate();
  worker = null;
  busy(false);
}
$("ciphertext").addEventListener("input", () => { count(); clearResult(); });
$("sample").addEventListener("click", () => {
  $("ciphertext").value = sample;
  clearResult(); count(); status("Example loaded. Ready when you are.");
});
$("cancel").addEventListener("click", () => { finish(); status("Search cancelled. You can try again."); });
$("crack").addEventListener("click", () => {
  const text = $("ciphertext").value;
  const letters = (text.match(/[А-Яа-я]/g) || []).length;
  if (!letters || letters > 4096) {
    status(letters ? "Use at most 4,096 Russian letters." : "Enter some Russian letters to start.", true);
    return;
  }
  clearResult(); busy(true); $("progress").value = 0;
  status("Loading the solver…"); started = performance.now();
  try {
    worker = new Worker(new URL("worker.js", import.meta.url), { type: "module" });
    worker.onmessage = ({ data }) => {
      if (data.type === "progress") {
        $("progress").value = data.progress;
        status(`Searching for the key… ${Math.round(data.progress * 100)}%`);
      } else if (data.type === "result") {
        $("keyword").textContent = data.keyword;
        $("alphabet").textContent = data.alphabet;
        $("period").textContent = `${data.period}-letter key · ${data.plaintext.length} decrypted letters`;
        $("grouped").value = data.grouped;
        $("words").value = data.words;
        fitTextareas();
        for (const button of document.querySelectorAll(".copy")) button.disabled = !$(button.dataset.copy).value;
        status(data.warning || `Recovered in ${((performance.now() - started) / 1000).toFixed(1)} seconds.`, !!data.warning);
        finish();
      } else if (data.type === "error") {
        status(data.message, true); finish();
      }
    };
    worker.onerror = () => { status("The solver could not run. Reload the page and try again.", true); finish(); };
    worker.postMessage({ text });
  } catch (error) { status(error.message, true); finish(); }
});
for (const button of document.querySelectorAll(".copy")) {
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText($(button.dataset.copy).value);
      status("Copied to clipboard.");
    } catch { status("Select the text and copy it with your keyboard."); }
  });
}
$("sample").disabled = true;
try {
  const response = await fetch(new URL("crypted-ru.txt", import.meta.url));
  if (!response.ok) throw new Error();
  sample = (await response.text()).trim();
  if (!$("ciphertext").value) $("ciphertext").value = sample;
  $("sample").disabled = !!worker;
  count();
} catch {
  $("ciphertext").placeholder = "Paste Russian ciphertext here.";
  status("The example could not load. Paste your own ciphertext to continue.", true);
}
