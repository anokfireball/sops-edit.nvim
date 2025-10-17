local config = require("sops_edit.config")
local utils = require("sops_edit.utils")

local M = {}

function M.decrypt_buffer(args)
	local filepath = utils.normalize_path_abs(args.file)

	if not config.is_sops_file(filepath) then
		return
	end

	if vim.fn.filereadable(filepath) == 0 then
		return
	end

	if config.options.verbose then
		vim.notify("Decrypting SOPS file: " .. utils.normalize_path_display(filepath), vim.log.levels.INFO)
	end

	local cmd = string.format("sops -d %s", vim.fn.shellescape(filepath))
	local success, output, error_msg = utils.execute_command(cmd)

	if not success then
		vim.notify(
			string.format("SOPS decryption failed for %s:\n%s", utils.normalize_path_display(filepath), error_msg),
			vim.log.levels.ERROR
		)
		return
	end

	vim.bo[args.buf].buftype = "acwrite"
	vim.bo[args.buf].modifiable = true

	vim.bo[args.buf].swapfile = false
	vim.bo[args.buf].undofile = false
	vim.opt_local.backup = false
	vim.opt_local.writebackup = false
	vim.bo[args.buf].modeline = false

	vim.o.shada = ""
	vim.o.viminfo = ""

	local buf_group = vim.api.nvim_create_augroup("SopsEditBuf" .. args.buf, { clear = true })
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = buf_group,
		buffer = args.buf,
		callback = function(ev)
			local b = (ev and ev.buf) or args.buf
			require("sops_edit.core.encrypt").encrypt_buffer({ buf = b })
		end,
		desc = "Encrypt SOPS buffer on write",
	})

	vim.api.nvim_create_autocmd("BufUnload", {
		group = buf_group,
		buffer = args.buf,
		callback = function()
			utils.clear_all_registers()
			collectgarbage("collect")
		end,
		desc = "Clear registers when SOPS buffer is unloaded",
	})

	local lines = vim.split(output, "\n")

	utils.secure_wipe_string(output)

	vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, lines)

	utils.secure_wipe_table_strings(lines)

	collectgarbage("collect")

	vim.bo[args.buf].modified = false

	if config.options.verbose then
		vim.notify("SOPS file decrypted successfully", vim.log.levels.INFO)
	end
end

return M
