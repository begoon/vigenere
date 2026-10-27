# GitHub Pages site

This folder is a complete static site. In the repository's **Settings → Pages**,
choose **Deploy from a branch**, select the branch containing these files, and
select **`/docs`**. No Actions workflow, server, API key, or bundler is needed.
All asset paths are relative, including worker and Wasm URLs, so project-site
subpaths work. `.nojekyll` bypasses Jekyll processing.

## Local preview and rebuild

From the repository root:

```sh
bun wasm/build.js
python3 -m http.server 8000 --directory docs
```

Open <http://localhost:8000>. Use HTTP rather than opening `index.html` as a
`file:` URL, because browsers restrict workers and fetches on local files.
`just web-build` and `just web-serve` are equivalent shortcuts.

## Behavior

- The supplied Russian ciphertext is loaded into an editable textarea.
- **Crack the cipher** runs the shared Zig Wasm solver in a dedicated worker.
- Progress reflects completed restarts. **Cancel** terminates the worker;
  another search starts a fresh worker and fresh Wasm memory.
- Results include the recovered keyword, mixed alphabet, literal plaintext in
  groups of five (eleven groups per line), and a second text area with estimated
  Russian word boundaries. Copy buttons copy either reading.
- All input and computation remain in the browser. No third-party requests
  are needed at runtime. Modern browsers with WebAssembly, module workers, and
  `DecompressionStream` are supported. If the dictionary fails to load or
  decompress, the literal cracking result is still displayed.

Cracking is heuristic, especially for short or unusual inputs. Word spacing
uses a unigram frequency model with dynamic programming and a general
`-овать`/`-ировать` inflection fallback. It adds only spaces: it does not repair
letters, insert punctuation, or silently correct the puzzle's `ЧТЙ` anomaly.
Names, unknown words, and ambiguous boundaries may still split incorrectly.

## Word-frequency asset

`ru-frequency.txt.gz` contains 589,483 filtered entries from FrequencyWords /
OpenSubtitles 2018, approximately 3.55 MB compressed. It is fetched only after
successful cracking. See [`THIRD_PARTY.md`](THIRD_PARTY.md) for source, attribution,
and its separate CC BY-SA 4.0 data license.

To regenerate it, download the pinned source linked in that file, then run:

```sh
python3 scripts/build_dictionary.py /path/to/ru_full.txt
```

The script checks the original SHA-256 before filtering and compressing. The
sample plaintext is only a test fixture and is never used to generate this
dictionary or served as a result by the web app.
