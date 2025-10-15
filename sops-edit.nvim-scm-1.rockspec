package = "sops-edit.nvim"
version = "scm-1"

source = {
	url = "git://github.com/ntauthority/sops-edit.nvim",
}

description = {
	summary = "Transparent editing of SOPS-encrypted files in Neovim",
	detailed = [[
		sops-edit.nvim enables seamless editing of SOPS-encrypted files directly in Neovim
		without ever writing plaintext to disk. It automatically decrypts files on open,
		disables persistence mechanisms (swap, undo, backup), and re-encrypts on save.
		
		Features:
		- Zero plaintext on disk
		- Transparent workflow
		- Security hardening
		- Pattern-based detection
		- No .sops.yaml required (extracts keys from files)
	]],
	homepage = "https://github.com/ntauthority/sops-edit.nvim",
	license = "MIT",
}

dependencies = {
	"lua >= 5.1",
	"lyaml >= 6.0",
}

build = {
	type = "builtin",
	modules = {},
	copy_directories = {
		"doc",
		"plugin",
		"lua",
	},
}
