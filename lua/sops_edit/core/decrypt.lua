local config = require("sops_edit.config")
local utils = require("sops_edit.utils")

local M = {}

function M.decrypt_buffer(args)
	local filepath = vim.fn.fnamemodify(args.file, ":p")

	if not config.is_sops_file(filepath) then
		return
	end

	if vim.fn.filereadable(filepath) == 0 then
		return
	end

	if config.options.verbose then
		vim.notify("Decrypting SOPS file: " .. vim.fn.fnamemodify(filepath, ":~"), vim.log.levels.INFO)
	end

	local cmd = string.format("sops -d %s", vim.fn.shellescape(filepath))
	local success, output, error_msg = utils.execute_command(cmd)

	if not success then
		vim.notify(
			string.format("SOPS decryption failed for %s:\n%s", vim.fn.fnamemodify(filepath, ":~"), error_msg),
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
			pcall(function()
				vim.fn.setreg('"', "")
				vim.fn.setreg("0", "")
				vim.fn.setreg("1", "")
				vim.fn.setreg("2", "")
				vim.fn.setreg("3", "")
				vim.fn.setreg("4", "")
				vim.fn.setreg("5", "")
				vim.fn.setreg("6", "")
				vim.fn.setreg("7", "")
				vim.fn.setreg("8", "")
				vim.fn.setreg("9", "")
				vim.fn.setreg("-", "")
				vim.fn.setreg(".", "")
				vim.fn.setreg(":", "")
				for i = 97, 122 do
					vim.fn.setreg(string.char(i), "")
				end
				collectgarbage("collect")
			end)
		end,
		desc = "Clear registers when SOPS buffer is unloaded",
	})

	local lines = vim.split(output, "\n")

	local output_len = #output
	output = string.rep("\0", output_len)
	output = nil

	vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, lines)

	for i = 1, #lines do
		local line_len = #lines[i]
		lines[i] = string.rep("\0", line_len)
	end
	for i = 1, #lines do
		lines[i] = nil
	end
	lines = nil

	collectgarbage("collect")

	vim.bo[args.buf].modified = false

	if config.options.verbose then
		vim.notify("SOPS file decrypted successfully", vim.log.levels.INFO)
	end
end

return M
