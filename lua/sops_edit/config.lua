local M = {}

M.defaults = {
	sops_patterns = {
		"%.sops%.ya?ml$",
		"%.sops%.json$",
		"%.sops%.env$",
		"%.sops%.ini$",
	},
	verbose = false,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(user_opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, user_opts or {})
	return M.options
end

function M.is_sops_file(filepath)
	if not filepath or filepath == "" then
		return false
	end

	for _, pattern in ipairs(M.options.sops_patterns) do
		if filepath:match(pattern) then
			return true
		end
	end

	return false
end

function M.get_autocommand_pattern()
	local patterns = {}
	for _, lua_pattern in ipairs(M.options.sops_patterns) do
		if lua_pattern == "%.sops%.ya?ml$" then
			table.insert(patterns, "*.sops.yaml")
			table.insert(patterns, "*.sops.yml")
		elseif lua_pattern == "%.sops%.json$" then
			table.insert(patterns, "*.sops.json")
		elseif lua_pattern == "%.sops%.env$" then
			table.insert(patterns, "*.sops.env")
		elseif lua_pattern == "%.sops%.ini$" then
			table.insert(patterns, "*.sops.ini")
		else
			vim.notify(
				string.format(
					"Warning: Unknown SOPS pattern '%s' in sops_patterns config - cannot convert to autocommand pattern",
					lua_pattern
				),
				vim.log.levels.WARN
			)
		end
	end
	return table.concat(patterns, ",")
end

return M
