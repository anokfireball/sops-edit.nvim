# sops-edit.nvim

Transparent editing of SOPS-encrypted files in Neovim without ever writing plaintext to disk.

## Features

- 🔒 **Zero plaintext on disk** — All encryption/decryption happens in-memory via stdin/stdout
- 🚀 **Transparent workflow** — Edit encrypted files as if they were plain text
- 🛡️ **Security hardening** — Automatically disables swap, undo, backup, and modeline for SOPS buffers
- 🎯 **Pattern-based detection** — Flexible file matching (e.g., `*.sops.yaml`, `*.sops.json`)
- 🔑 **No .sops.yaml required** — Automatically extracts encryption keys from existing files for re-encryption

## Requirements

- Neovim >= 0.7.0
- [`sops`](https://github.com/getsops/sops) binary in `$PATH`
- POSIX-compliant `cat` command (standard on Linux, macOS, BSD, WSL)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "ntauthority/sops-edit.nvim",
  config = function()
    require("sops_edit").setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "ntauthority/sops-edit.nvim",
  config = function()
    require("sops_edit").setup()
  end,
}
```

### Manual

1. Clone this repository into your Neovim runtime path:
   ```bash
   git clone https://github.com/ntauthority/sops-edit.nvim ~/.local/share/nvim/site/pack/plugins/start/sops-edit.nvim
   ```

2. Add to your `init.lua`:
   ```lua
   require("sops_edit").setup()
   ```

## Configuration

Default configuration:

```lua
require("sops_edit").setup({
  sops_patterns = {
    "%.sops%.ya?ml$",  -- Matches *.sops.yaml and *.sops.yml
    "%.sops%.json$",   -- Matches *.sops.json
    "%.sops%.toml$",   -- Matches *.sops.toml
    "%.sops%.env$",    -- Matches *.sops.env
  },
  verbose = false,     -- Enable verbose notifications for debugging
})
```

### Supported File Formats

The plugin automatically detects the file format based on extension and uses the appropriate SOPS input/output type:

| Extension | SOPS Format | Notes |
|-----------|-------------|-------|
| `.yaml`, `.yml` | `yaml` | Default if extension is unknown |
| `.json` | `json` | Also used for JSON metadata parsing |
| `.toml` | `toml` | TOML format support |
| `.env` | `dotenv` | Environment file format |

### Adding Custom Patterns

You can add custom file patterns to detect SOPS files:

```lua
require("sops_edit").setup({
  sops_patterns = {
    "%.sops%.ya?ml$",
    "%.sops%.json$",
    "%.secrets%.yaml$",  -- Custom pattern for *.secrets.yaml
    "^secrets/.*%.yaml$", -- All YAML files in secrets/ directory
  },
})
```

**Note**: Patterns use Lua regex syntax, not glob patterns.

## Usage

1. **Create a SOPS file**:
   ```bash
   echo "password: supersecret" > secrets.sops.yaml
   sops -e -i secrets.sops.yaml
   ```

2. **Edit in Neovim**:
   ```bash
   nvim secrets.sops.yaml
   ```
   
   The file will be automatically decrypted into memory. Edit as usual, then `:w` to save (automatic re-encryption).

3. **Verify encryption**:
   ```bash
   cat secrets.sops.yaml  # Shows encrypted content
   ```

## Editing Without .sops.yaml (Key Extraction)

One of the key features of sops-edit.nvim is the ability to edit SOPS files without needing a `.sops.yaml` configuration file in the current directory. This is particularly useful when:

- Working with encrypted files from different repositories
- Editing files outside of their original project context
- Collaborating across teams with different SOPS configurations

### How It Works

When you save a SOPS file, the plugin:

1. **Parses the encrypted file** to extract encryption metadata:
   - Age recipients (`age1...`)
   - AWS KMS ARNs (`arn:aws:kms:...`)
   - GCP KMS resource IDs (`projects/.../keyRings/.../cryptoKeys/...`)
   - Azure Key Vault URLs (`https://.../keys/...`)

2. **Re-encrypts using extracted keys** with the command:
   ```bash
   sops --config /dev/null --encrypt --age <recipients> --kms <arns> ... /dev/stdin
   ```
   
   The `--config /dev/null` flag bypasses SOPS config file loading entirely.

3. **Falls back to creation rules** if key extraction fails (requires `.sops.yaml`)

### Example

```bash
# Create and encrypt a file in one directory
cd ~/project-a
echo "password: secret" > config.sops.yaml
sops --age age1ahng4l4v... -e -i config.sops.yaml

# Edit it from a completely different directory - no .sops.yaml needed!
cd /tmp
nvim ~/project-a/config.sops.yaml  # Works! Keys extracted from file itself
```

### Verification

Enable verbose mode to see which method is being used:

```lua
require("sops_edit").setup({ verbose = true })
```

When saving, you'll see either:
- `"Using extracted keys from original file for encryption"` ✅ Key extraction succeeded
- `"No keys found in file, using creation rules from .sops.yaml"` ⚠️  Fallback to creation rules

### Limitations

- **Regex-based parsing**: Uses pattern matching instead of full YAML/JSON parsing
- **Format-sensitive**: Unusual formatting or comments may cause extraction to fail
- **Best-effort**: Always verify recipients are preserved after first edit in a new location
- **Multi-provider complexity**: Files using multiple key types (age + KMS) have more parsing complexity

## Security Model

sops-edit.nvim implements multiple layers of protection:

| Protection | Implementation | Purpose |
|------------|----------------|---------|
| **No plaintext writes** | `buftype=acwrite` | Intercepts all write operations |
| **No swap files** | `noswapfile` | Prevents plaintext in `.swp` files |
| **No undo files** | `noundofile` | Prevents plaintext in undo history |
| **No backups** | `nobackup`, `nowritebackup` | Prevents plaintext in backup files |
| **No modelines** | `nomodeline` | Prevents modeline injection attacks |
| **Atomic encrypted writes** | temp + fsync + rename | Prevents corruption and ensures integrity |

### Important Security Notes

⚠️ **What this plugin does NOT protect against:**

- `:w !command` or `:saveas` bypassing buffer protections
- Session files (`:mksession`) that may contain buffer content
- Neovim crash dumps or core files
- Terminal scrollback buffers showing plaintext
- Clipboard managers capturing yanked secrets
- Screen sharing or screenshot tools
- ShaDa (shared data) files potentially storing buffer content

⚠️ **Key Extraction Limitations:**

- Uses regex-based parsing of SOPS metadata (not a full YAML/JSON parser)
- Complex or non-standard formatting may cause incomplete key extraction
- Partial extraction may result in fewer recipients than the original file
- When verbose mode is enabled, watch for "Using extracted keys" vs "using creation rules" messages
- Verify recipients are preserved after first save when working with multi-recipient files

🔐 **Best Practices:**

1. Always verify your SOPS configuration (`.sops.yaml`) before committing
2. Use age or PGP keys with proper access controls
3. Rotate keys when team members leave
4. Audit git history for accidentally committed plaintext
5. Use `git-crypt` or `git-secret` as additional layers

## How It Works

1. **On `BufReadPost`**: Detects SOPS files by pattern matching
2. **Decryption**: Runs `sops -d <file>` and loads output into buffer
3. **Buffer Setup**: Sets `acwrite` mode and disables all persistence mechanisms
4. **On `BufWriteCmd`**: Intercepts write, encrypts buffer via one of two methods:
   - **With extracted keys** (preferred): Parses SOPS metadata from the encrypted file to extract age/KMS/GCP KMS/Azure Key Vault recipients, then pipes buffer through `cat | sops --config /dev/null --encrypt --input-type <type> --output-type <type> [--age <keys>] [--kms <keys>] [--gcp-kms <keys>] [--azure-kv <keys>] /dev/stdin`
   - **Fallback to creation rules**: If key extraction fails, uses `cat | sops --encrypt --input-type <type> --output-type <type> --filename-override <file> /dev/stdin` (requires `.sops.yaml` with creation rules)
5. **Atomic Write**: Saves encrypted output to temporary file, syncs to disk (fsync), then atomically renames to original file
6. **Buffer Update**: Marks buffer as unmodified

**Encryption Pipeline:**
- Plaintext is fed to `cat` via stdin (no command-line arguments)
- `cat` streams to SOPS through a shell pipeline
- SOPS reads from `/dev/stdin` (valid within the pipeline context)
- No plaintext written to temporary files or visible in process arguments
- Only encrypted output is written to disk using atomic write pattern
- **Synchronous execution**: The `BufWriteCmd` callback completes before returning, ensuring the buffer's `modified` flag is properly cleared for commands like `:wq` to work correctly

**Key Extraction (No .sops.yaml Required):**
- Parses YAML/JSON SOPS metadata sections from encrypted files
- Extracts age recipients, AWS KMS ARNs, GCP KMS resource IDs, and Azure Key Vault URLs
- Allows editing SOPS files anywhere without needing local `.sops.yaml` configuration
- Falls back to creation rules if extraction fails or returns no keys
- **Important**: Uses regex-based parsing; complex/malformed metadata may cause partial extraction

## Troubleshooting

### "sops binary not found"
Install SOPS: https://github.com/getsops/sops#download

### Decryption fails
- Verify you have access to the decryption keys (age/PGP/KMS)
- Check SOPS configuration with `sops -d <file>`
- Ensure `SOPS_AGE_KEY_FILE` or other key environment variables are set

### File not detected as SOPS file
- Ensure filename matches a pattern in `sops_patterns`
- Enable `verbose = true` to see detection logs

### Changes not saving / Wrong recipients after save
- Enable `verbose = true` to see which encryption method is being used
- Check for "Using extracted keys" vs "using creation rules" messages
- Verify the original encrypted file has valid SOPS metadata
- If key extraction is failing, ensure you have a `.sops.yaml` file with creation rules
- For multi-recipient files, verify all recipients after first edit with: `sops -d <file> | grep -A 20 sops:`

### File won't save: "no matching creation rules"
This occurs when:
1. Key extraction from the file metadata fails (malformed or missing metadata)
2. AND no `.sops.yaml` file exists with creation rules for the filename

**Solutions:**
- Create a `.sops.yaml` file with appropriate creation rules
- Or ensure the encrypted file has valid SOPS metadata (check with `cat <file> | grep -A 10 sops:`)
- Enable `verbose = true` to see detailed encryption method selection

## Contributing

Contributions welcome! Please ensure:
- Security-focused changes include threat model analysis
- Code follows existing style (run stylua if available)
- Documentation updated for new features

## License

MIT License - see [LICENSE](LICENSE)

## Related Projects

- [SOPS](https://github.com/getsops/sops) — Secrets OPerationS
- [vim-gnupg](https://github.com/jamessan/vim-gnupg) — GPG encryption for Vim
- [age.nvim](https://github.com/FiloSottile/age) — age encryption support
