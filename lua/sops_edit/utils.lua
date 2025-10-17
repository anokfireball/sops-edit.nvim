local M = {}

function M.secure_wipe_string(str)
	if not str then
		return
	end
	local len = #str
	str = string.rep("\0", len)
	str = nil
end

function M.secure_wipe_table_strings(tbl)
	if not tbl then
		return
	end
	for i = 1, #tbl do
		if type(tbl[i]) == "string" then
			local len = #tbl[i]
			tbl[i] = string.rep("\0", len)
		end
	end
	for i = 1, #tbl do
		tbl[i] = nil
	end
	tbl = nil
end

function M.clear_all_registers()
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
	end)
end

function M.get_file_extension(filepath)
	return (filepath:match("%.([^%.]+)$") or ""):lower()
end

function M.normalize_path_abs(path)
	return vim.fn.fnamemodify(path, ":p")
end

function M.normalize_path_display(path)
	return vim.fn.fnamemodify(path, ":~")
end

function M.execute_command(cmd, input)
	if input then
		local result = vim.fn.system(cmd .. " 2>&1", input)
		local exit_code = vim.v.shell_error

		M.secure_wipe_string(input)

		if exit_code == 0 then
			return true, result, ""
		else
			return false, "", result
		end
	else
		local result_list = vim.fn.systemlist(cmd .. " 2>&1")
		local exit_code = vim.v.shell_error
		local output = table.concat(result_list, "\n")
		if exit_code == 0 then
			return true, output, ""
		else
			return false, "", output
		end
	end
end

return M
