# Remove local build outputs, caches, and virtual environments.
clean:
    rm -rf go/vigenerecrack zig/zig-out zig/.zig-cache __pycache__ scripts/__pycache__ .venv
