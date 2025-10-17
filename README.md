# sops-edit.nvim

Edit SOPS-encrypted files in Neovim safely and transparently without ever writing plaintext to disk.

## Why use this plugin?

- 🔒 Safe by default: avoids common plaintext leaks (swap, undo, backups, registers, shada/viminfo, modelines) and writes only encrypted data to disk.
- 🧠 Zero mental overhead: open, edit, and save SOPS files like any other buffer.
- 🧭 Sensible behavior, no surprises: unknown formats and misconfigurations return clear errors, no silent fallbacks.
- 🔑 Portable workflows: reuses recipients embedded in existing SOPS files, so you can edit files outside their original repo without a local `.sops.yaml`.
- 🧱 Robust saves: atomic writes help prevent corruption and keep ciphertext consistent on disk.

## Features

- Transparent decrypt-on-read, encrypt-on-write flow
- No plaintext written to disk; encryption happens in-memory
- Disables swap/undo/backups/modelines for SOPS buffers; clears registers on unload
- Explicit errors for unsupported file formats (no implicit YAML fallback)
- Pattern-based file detection (`*.sops.yaml`, `*.sops.json`, etc.) with warnings for unknown patterns
- Works with or without `.sops.yaml` via recipient extraction from the encrypted file

## Supported formats

- `.yaml`, `.yml`
- `.json`
- `.env`
- `.ini`

If a file uses a different or unknown extension, the plugin stops with a clear error instead of guessing.

## Requirements

- Neovim >= 0.7.0
- [`sops`](https://github.com/getsops/sops) available in `$PATH`
- [`lyaml`](https://github.com/gvvaughan/lyaml) (required for YAML metadata extraction)

## Install

### lazy.nvim

```lua
{
  "ntauthority/sops-edit.nvim",
  config = function()
    require("sops_edit").setup()
  end,
}
```

If your lazy.nvim setup does not install rockspec dependencies, install `lyaml` manually (required for YAML):

```bash
luarocks install --local lyaml
```

### packer.nvim

```lua
use {
  "ntauthority/sops-edit.nvim",
  config = function()
    require("sops_edit").setup()
  end,
  rocks = { "lyaml" },  -- required for YAML recipient extraction
}
```

### Manual

1) Clone the repo into your runtime path, 2) add `require("sops_edit").setup()` to your config.

## Quick start

- Open any supported SOPS file (`*.sops.yaml`, `*.sops.json`, `*.sops.env`, `*.sops.ini`).
- The buffer is decrypted in-memory and protected from persistence leaks.
- Save as usual. The buffer is re-encrypted and written atomically, never exposing plaintext on disk.

## Configuration

```lua
require("sops_edit").setup({
  sops_patterns = {
    "%.sops%.ya?ml$",
    "%.sops%.json$",
    "%.sops%.env$",
    "%.sops%.ini$",
  },
  verbose = false,
})
```

- Patterns are Lua patterns (not globs). Unknown or malformed patterns trigger a warning instead of being silently ignored.
- Set `verbose = true` to see brief status messages during decrypt/encrypt.

## How it feels

- Open: you see plaintext in your buffer, but it never touches disk.
- Edit: Neovim behaves normally; the plugin keeps persistence features off for this buffer.
- Save: the plugin reuses recipients from the file when possible; otherwise it relies on your `.sops.yaml` creation rules. If neither applies, it fails loudly and safely.

## Security posture

This plugin aims to reduce accidental plaintext exposure during normal editing:

- No plaintext writes to disk
- Disables swap/undo/backups/modelines for SOPS buffers
- Clears registers on buffer unload; avoids shada/viminfo persistence
- Performs atomic encrypted writes
- Explicit errors for unsupported formats and misconfigurations

Security is a shared responsibility. It does not protect against intentional exfiltration (e.g. `:w !cmd`, clipboard managers, terminal scrollback, screenshots). Use sound operational practices and review SOPS recipients regularly.

## Key extraction (no local .sops.yaml required)

When saving, the plugin tries to reuse recipients stored in the encrypted file’s metadata (age/KMS/PGP/etc.). This lets you edit files outside their original repository without a local `.sops.yaml`.

- Works across supported formats. For YAML, `lyaml` is required for extracting recipients from the encrypted file.
- If recipients cannot be determined, `.sops.yaml` creation rules are required.
- Behavior is explicit: you’ll see a clear error when neither path is possible.

## Troubleshooting

- “sops not found”: install SOPS and ensure it’s on your `$PATH`.
- Unsupported file format/extension: rename to a supported extension or add a supported pattern and use that extension.
- Save fails and mentions creation rules: add appropriate rules to `.sops.yaml` or ensure the encrypted file contains valid recipient metadata.
- Not detected as SOPS file: adjust `sops_patterns` and/or enable `verbose = true` to see detection messages.

## Related

- [SOPS](https://github.com/getsops/sops)
- [vim-gnupg](https://github.com/jamessan/vim-gnupg)
- [age](https://github.com/FiloSottile/age)
