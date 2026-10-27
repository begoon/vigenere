# Remove local build outputs, caches, and virtual environments.
clean:
    rm -rf go/vigenerecrack vlang/vigenerecrack zig/zig-out zig/.zig-cache zig-english/zig-out zig-english/.zig-cache wasm/zig-out wasm/.zig-cache __pycache__ scripts/__pycache__ .venv

# Rebuild the WebAssembly executable served by GitHub Pages.
web-build:
    bun wasm/build.js

web-serve:
    python3 -m http.server 8000 --directory docs
