local M = {}

function M.execute_command(cmd, input)
	if input then
		local result = vim.fn.system(cmd .. " 2>&1", input)
		local exit_code = vim.v.shell_error
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
