local config = require("sops_edit.config")
local utils = require("sops_edit.utils")

local M = {}

local function setup_luarocks_path()
	local home = os.getenv("HOME")
	if not home then
		return
	end

	local lua_version = _VERSION:match("Lua (%d+%.%d+)")
	if not lua_version then
		return
	end

	local versions = { lua_version, "5.4", "5.3", "5.2", "5.1" }
	for _, version in ipairs(versions) do
		local luarocks_share = home .. "/.luarocks/share/lua/" .. version
		local luarocks_lib = home .. "/.luarocks/lib/lua/" .. version
		package.path = luarocks_share .. "/?.lua;" .. luarocks_share .. "/?/init.lua;" .. package.path
		package.cpath = luarocks_lib .. "/?.so;" .. package.cpath
	end
end

local lyaml = nil
pcall(function()
	setup_luarocks_path()
	lyaml = require("lyaml")
end)

local toml = nil
pcall(function()
	setup_luarocks_path()
	toml = require("tinytoml")
end)

local KEY_TYPE_SPECS = {
	age = { field = "recipient", flag = "--age" },
	kms = { field = "arn", flag = "--kms" },
	gcp_kms = { field = "resource_id", flag = "--gcp-kms" },
	azure_kv = { field = "vault_url", flag = "--azure-kv" },
	pgp = { field = "fp", flag = "--pgp" },
	hc_vault_transit = { field = "vault_address", flag = "--hc-vault-transit" },
}

local function parse_yaml_sops_metadata(content)
	if not lyaml then
		return nil
	end

	local ok, docs = pcall(lyaml.load, content)
	if not ok or not docs then
		return nil
	end

	local doc = type(docs) == "table" and docs[1] or docs
	if not doc or not doc.sops then
		return nil
	end

	local keys = {}
	for key_type, spec in pairs(KEY_TYPE_SPECS) do
		local key_section = doc.sops[key_type]
		if key_section and type(key_section) == "table" then
			local values = {}
			for _, entry in ipairs(key_section) do
				if type(entry) == "table" and entry[spec.field] then
					table.insert(values, entry[spec.field])
				end
			end
			if #values > 0 then
				keys[key_type] = values
			end
		end
	end

	return keys
end

local function parse_json_sops_metadata(content)
	local ok, data = pcall(vim.json.decode, content)
	if not ok or not data or not data.sops then
		return nil
	end

	local keys = {}
	for key_type, spec in pairs(KEY_TYPE_SPECS) do
		local key_section = data.sops[key_type]
		if key_section and type(key_section) == "table" then
			local values = {}
			for _, entry in ipairs(key_section) do
				if type(entry) == "table" and entry[spec.field] then
					table.insert(values, entry[spec.field])
				end
			end
			if #values > 0 then
				keys[key_type] = values
			end
		end
	end

	return keys
end

local function parse_toml_sops_metadata(content, filepath)
	if not toml then
		return nil
	end

	local ok, data
	if filepath then
		ok, data = pcall(toml.parse, filepath)
	else
		ok, data = pcall(toml.parse, content)
	end

	if not ok or not data or not data.sops then
		return nil
	end

	local keys = {}
	for key_type, spec in pairs(KEY_TYPE_SPECS) do
		local key_section = data.sops[key_type]
		if key_section and type(key_section) == "table" then
			local values = {}
			for _, entry in ipairs(key_section) do
				if type(entry) == "table" and entry[spec.field] then
					table.insert(values, entry[spec.field])
				end
			end
			if #values > 0 then
				keys[key_type] = values
			end
		end
	end

	return keys
end

local function parse_comment_block_metadata(content)
	local comment_lines = {}
	local in_sops_block = false

	for line in content:gmatch("[^\r\n]+") do
		local comment_char, rest = line:match("^([#;])(.*)$")
		if comment_char then
			local stripped = rest:match("^%s*(.*)$")
			if stripped:match("^sops:") or stripped:match("^sops%s") then
				in_sops_block = true
			end
			if in_sops_block then
				table.insert(comment_lines, rest)
			end
		elseif in_sops_block then
			break
		end
	end

	if #comment_lines == 0 then
		return nil
	end

	local metadata_str = table.concat(comment_lines, "\n")

	if lyaml then
		local yaml_ok, yaml_data = pcall(lyaml.load, metadata_str)
		if yaml_ok and yaml_data then
			local doc = type(yaml_data) == "table" and yaml_data[1] or yaml_data
			if doc and doc.sops then
				local keys = {}
				for key_type, spec in pairs(KEY_TYPE_SPECS) do
					local key_section = doc.sops[key_type]
					if key_section and type(key_section) == "table" then
						local values = {}
						for _, entry in ipairs(key_section) do
							if type(entry) == "table" and entry[spec.field] then
								table.insert(values, entry[spec.field])
							end
						end
						if #values > 0 then
							keys[key_type] = values
						end
					end
				end
				if next(keys) then
					return keys
				end
			end
		end
	end

	local json_ok, json_data = pcall(vim.json.decode, metadata_str)
	if json_ok and json_data and json_data.sops then
		local keys = {}
		for key_type, spec in pairs(KEY_TYPE_SPECS) do
			local key_section = json_data.sops[key_type]
			if key_section and type(key_section) == "table" then
				local values = {}
				for _, entry in ipairs(key_section) do
					if type(entry) == "table" and entry[spec.field] then
						table.insert(values, entry[spec.field])
					end
				end
				if #values > 0 then
					keys[key_type] = values
				end
			end
		end
		return keys
	end

	return nil
end

local function extract_sops_keys(filepath)
	local fd = vim.loop.fs_open(filepath, "r", tonumber("644", 8))
	if not fd then
		return nil
	end

	local stat = vim.loop.fs_fstat(fd)
	if not stat then
		vim.loop.fs_close(fd)
		return nil
	end

	local content = vim.loop.fs_read(fd, stat.size, 0)
	vim.loop.fs_close(fd)

	if not content then
		return nil
	end

	local ext = filepath:match("%.([^%.]+)$") or ""
	if ext == "json" then
		return parse_json_sops_metadata(content)
	elseif ext == "toml" then
		return parse_toml_sops_metadata(content, filepath)
	elseif ext == "env" or ext == "ini" then
		return parse_comment_block_metadata(content)
	else
		return parse_yaml_sops_metadata(content)
	end
end

function M.encrypt_buffer(args)
	if not args or not args.buf then
		return
	end
	local filepath = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":p")

	if vim.bo[args.buf].buftype ~= "acwrite" then
		return
	end

	if not vim.bo[args.buf].modified then
		if config.options.verbose then
			vim.notify("No changes to save for: " .. vim.fn.fnamemodify(filepath, ":~"), vim.log.levels.INFO)
		end
		return
	end

	if config.options.verbose then
		vim.notify("Encrypting SOPS file: " .. vim.fn.fnamemodify(filepath, ":~"), vim.log.levels.INFO)
	end

	local buffer_lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
	local full_plaintext = table.concat(buffer_lines, "\n") .. "\n"

	local ext = filepath:match("%.([^%.]+)$") or ""
	local format_map = {
		json = "json",
		toml = "toml",
		env = "dotenv",
		yml = "yaml",
		yaml = "yaml",
	}
	local input_type = format_map[ext]

	if not input_type then
		if config.options.verbose then
			vim.notify(
				string.format(
					"Unknown file extension '.%s' for %s, defaulting to yaml",
					ext,
					vim.fn.fnamemodify(filepath, ":~")
				),
				vim.log.levels.WARN
			)
		end
		input_type = "yaml"
	end

	local keys = extract_sops_keys(filepath)
	local key_flags = ""

	if keys then
		for key_type, spec in pairs(KEY_TYPE_SPECS) do
			if keys[key_type] and #keys[key_type] > 0 then
				key_flags = key_flags
					.. string.format(" %s %s", spec.flag, vim.fn.shellescape(table.concat(keys[key_type], ",")))
			end
		end
	end

	local cmd
	if key_flags ~= "" then
		cmd = string.format(
			"cat | sops --config /dev/null --encrypt --input-type %s --output-type %s%s /dev/stdin",
			input_type,
			input_type,
			key_flags
		)
		if config.options.verbose then
			vim.notify("Using extracted keys from original file for encryption", vim.log.levels.INFO)
		end
	else
		cmd = string.format(
			"cat | sops --encrypt --input-type %s --output-type %s --filename-override %s /dev/stdin",
			input_type,
			input_type,
			vim.fn.shellescape(filepath)
		)
		if config.options.verbose then
			vim.notify("No keys found in file, using creation rules from .sops.yaml", vim.log.levels.INFO)
		end
	end

	local success, encrypted_output, stderr = utils.execute_command(cmd, full_plaintext)
	full_plaintext = nil

	if not success then
		vim.notify(
			string.format("SOPS encryption failed for %s:\n%s", vim.fn.fnamemodify(filepath, ":~"), stderr),
			vim.log.levels.ERROR
		)
		return
	end

	local uv = vim.loop
	local stat = uv.fs_stat(filepath)
	local original_mode = stat and stat.mode or tonumber("600", 8)

	local tmp_filepath = filepath .. ".sops.tmp"

	local fd = uv.fs_open(tmp_filepath, "w", original_mode)
	if not fd then
		vim.notify(
			string.format("Error: Could not create temporary file %s", vim.fn.fnamemodify(tmp_filepath, ":~")),
			vim.log.levels.ERROR
		)
		return
	end

	local write_ok = uv.fs_write(fd, encrypted_output, -1)
	if not write_ok then
		uv.fs_close(fd)
		uv.fs_unlink(tmp_filepath)
		vim.notify(
			string.format("Error: Could not write to temporary file %s", vim.fn.fnamemodify(tmp_filepath, ":~")),
			vim.log.levels.ERROR
		)
		return
	end

	uv.fs_fsync(fd)
	uv.fs_close(fd)

	local rename_ok, rename_err = uv.fs_rename(tmp_filepath, filepath)
	if not rename_ok then
		uv.fs_unlink(tmp_filepath)
		vim.notify(
			string.format(
				"Error: Could not rename temporary file to %s: %s",
				vim.fn.fnamemodify(filepath, ":~"),
				rename_err or "unknown error"
			),
			vim.log.levels.ERROR
		)
		return
	end

	vim.bo[args.buf].modified = false

	if config.options.verbose then
		vim.notify("SOPS file encrypted and saved successfully", vim.log.levels.INFO)
	end
end

M._extract_sops_keys = extract_sops_keys

return M
