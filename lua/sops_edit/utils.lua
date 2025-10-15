local M = {}

function M.execute_command(cmd, input)
	local exit_code
	local stdout
	local stderr

	if input then
		local result = vim.fn.system(cmd, input)
		exit_code = vim.v.shell_error
		stdout = result
		if exit_code ~= 0 then
			local err_result = vim.fn.system(cmd .. " 2>&1 >/dev/null", input)
			stderr = err_result
		else
			stderr = ""
		end
	else
		local result_list = vim.fn.systemlist(cmd)
		exit_code = vim.v.shell_error
		stdout = table.concat(result_list, "\n")
		if exit_code ~= 0 then
			local err_result_list = vim.fn.systemlist(cmd .. " 2>&1 >/dev/null")
			stderr = table.concat(err_result_list, "\n")
		else
			stderr = ""
		end
	end

	if exit_code == 0 then
		return true, stdout, ""
	else
		return false, "", stderr
	end
end

return M
