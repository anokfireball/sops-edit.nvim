local config = require("sops_edit.config")
local decrypt = require("sops_edit.core.decrypt")

local M = {}

local setup_complete = false

function M.setup(opts)
	if setup_complete then
		if config.options.verbose then
			vim.notify("sops_edit: setup() already called, skipping", vim.log.levels.WARN)
		end
		return
	end

	config.setup(opts or {})

	if vim.fn.executable("sops") == 0 then
		vim.notify("sops_edit: `sops` binary not found in $PATH. Plugin disabled.", vim.log.levels.ERROR)
		return
	end

	local group = vim.api.nvim_create_augroup("SopsEdit", { clear = true })

	local pattern = config.get_autocommand_pattern()

	vim.api.nvim_create_autocmd("BufReadPost", {
		group = group,
		pattern = pattern,
		callback = decrypt.decrypt_buffer,
		desc = "Decrypt SOPS files on read",
	})

	setup_complete = true

	if config.options.verbose then
		vim.notify("sops_edit: plugin loaded", vim.log.levels.INFO)
	end
end

return M
