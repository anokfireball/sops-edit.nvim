local config = require("sops_edit.config")
local utils = require("sops_edit.utils")

local M = {}

local lyaml = nil
local lyaml_load_attempted = false

local function get_lyaml()
	if lyaml then
		return lyaml
	end
	if lyaml_load_attempted then
		return nil
	end

	lyaml_load_attempted = true

	local ok = pcall(function()
		lyaml = require("lyaml")
	end)
	if ok then
		return lyaml
	end

	ok = pcall(require, "luarocks.loader")
	if ok then
		ok = pcall(function()
			lyaml = require("lyaml")
		end)
		if ok then
			return lyaml
		end
	end

	local home = os.getenv("HOME")
	if home then
		local lua_ver = _VERSION:match("Lua (%d+%.%d+)")
		if lua_ver then
			local share = home .. "/.luarocks/share/lua/" .. lua_ver
			local lib = home .. "/.luarocks/lib/lua/" .. lua_ver

			local ext = "so"
			if jit and jit.os then
				ext = jit.os:find("Windows") and "dll" or "so"
			end

			local new_path = share .. "/?.lua;" .. share .. "/?/init.lua"
			if not package.path:find(new_path, 1, true) then
				package.path = package.path .. ";" .. new_path
			end

			local new_cpath = lib .. "/?." .. ext
			if not package.cpath:find(lib, 1, true) then
				package.cpath = package.cpath .. ";" .. new_cpath
			end

			ok = pcall(function()
				lyaml = require("lyaml")
			end)
			if ok then
				return lyaml
			end
		end
	end

	return nil
end

local KEY_TYPE_SPECS = {
	age = { field = "recipient", flag = "--age" },
	kms = { field = "arn", flag = "--kms" },
	gcp_kms = { field = "resource_id", flag = "--gcp-kms" },
	azure_kv = { field = "vault_url", flag = "--azure-kv" },
	pgp = { field = "fp", flag = "--pgp" },
	hc_vault_transit = { field = "vault_address", flag = "--hc-vault-transit" },
}

local function parse_yaml_sops_metadata(content)
	local yaml = get_lyaml()
	if not yaml then
		return nil
	end

	local ok, docs = pcall(yaml.load, content)
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

local function parse_toml_sops_metadata(content)
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

local function parse_env_sops_metadata(content)
	local keys = {}

	for key_type, spec in pairs(KEY_TYPE_SPECS) do
		local recipients = {}
		local prefix = "sops_" .. key_type .. "__list_"

		for line in content:gmatch("[^\r\n]+") do
			local key, value = line:match("^([^=]+)=(.*)$")
			if key and value then
				key = key:gsub("^%s*(.-)%s*$", "%1")
				value = value:gsub("^%s*(.-)%s*$", "%1")
				if key:match("^" .. prefix .. "%d+__map_" .. spec.field .. "$") then
					table.insert(recipients, value)
				end
			end
		end

		if #recipients > 0 then
			keys[key_type] = recipients
		end
	end

	return next(keys) and keys or nil
end

local function parse_ini_sops_metadata(content)
	local keys = {}
	local in_sops_section = false

	for line in content:gmatch("[^\r\n]+") do
		local section = line:match("^%[(.-)%]$")
		if section then
			in_sops_section = (section == "sops")
		elseif in_sops_section then
			local key, value = line:match("^([^=]+)=(.*)$")
			if key and value then
				key = key:gsub("^%s*(.-)%s*$", "%1")
				value = value:gsub("^%s*(.-)%s*$", "%1")

				for key_type, spec in pairs(KEY_TYPE_SPECS) do
					local pattern = "^" .. key_type .. "__list_(%d+)__map_" .. spec.field .. "$"
					local index = key:match(pattern)
					if index then
						if not keys[key_type] then
							keys[key_type] = {}
						end
						local idx = tonumber(index) + 1
						keys[key_type][idx] = value
					end
				end
			end
		end
	end

	for key_type, recipients in pairs(keys) do
		local indices = {}
		for idx in pairs(recipients) do
			table.insert(indices, idx)
		end
		table.sort(indices)

		local compact = {}
		for _, idx in ipairs(indices) do
			table.insert(compact, recipients[idx])
		end
		keys[key_type] = compact
	end

	return next(keys) and keys or nil
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

	local ext = (filepath:match("%.([^%.]+)$") or ""):lower()
	if ext == "json" then
		return parse_json_sops_metadata(content)
	elseif ext == "toml" then
		return parse_toml_sops_metadata(content)
	elseif ext == "env" then
		return parse_env_sops_metadata(content)
	elseif ext == "ini" then
		return parse_ini_sops_metadata(content)
	elseif ext == "yaml" or ext == "yml" then
		return parse_yaml_sops_metadata(content)
	else
		return nil
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

	local function secure_cleanup()
		if full_plaintext then
			local len = #full_plaintext
			full_plaintext = string.rep("\0", len)
			full_plaintext = nil
		end

		if buffer_lines then
			for i = 1, #buffer_lines do
				local line_len = #buffer_lines[i]
				buffer_lines[i] = string.rep("\0", line_len)
			end
			for i = 1, #buffer_lines do
				buffer_lines[i] = nil
			end
			buffer_lines = nil
		end

		collectgarbage("collect")
	end

	local ext = (filepath:match("%.([^%.]+)$") or ""):lower()
	local format_map = {
		json = "json",
		toml = "toml",
		env = "dotenv",
		ini = "ini",
		yml = "yaml",
		yaml = "yaml",
	}
	local input_type = format_map[ext]

	if not input_type then
		secure_cleanup()
		vim.notify(
			string.format(
				"Error: Unknown file extension '.%s' for %s. Supported: json, toml, yaml, yml, env, ini",
				ext,
				vim.fn.fnamemodify(filepath, ":~")
			),
			vim.log.levels.ERROR
		)
		return
	end

	local ALLOWED_INPUT_TYPES = {
		json = true,
		toml = true,
		dotenv = true,
		yaml = true,
		ini = true,
	}
	if not ALLOWED_INPUT_TYPES[input_type] then
		secure_cleanup()
		vim.notify(
			string.format("Security: Invalid input type '%s' for %s", input_type, vim.fn.fnamemodify(filepath, ":~")),
			vim.log.levels.ERROR
		)
		return
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
			vim.fn.shellescape(input_type),
			vim.fn.shellescape(input_type),
			key_flags
		)
		if config.options.verbose then
			vim.notify("Using extracted keys from original file for encryption", vim.log.levels.INFO)
		end
	else
		cmd = string.format(
			"cat | sops --encrypt --input-type %s --output-type %s --filename-override %s /dev/stdin",
			vim.fn.shellescape(input_type),
			vim.fn.shellescape(input_type),
			vim.fn.shellescape(filepath)
		)
		if config.options.verbose then
			vim.notify("No keys found in file, using creation rules from .sops.yaml", vim.log.levels.INFO)
		end
	end

	local success, encrypted_output, stderr = utils.execute_command(cmd, full_plaintext)
	secure_cleanup()

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
	local safe_mode = tonumber("600", 8)

	local tmp_filepath = filepath .. ".sops." .. uv.hrtime() .. ".tmp"

	local fd = uv.fs_open(tmp_filepath, "w", safe_mode)
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

	if stat then
		uv.fs_chmod(filepath, original_mode)
	end

	vim.bo[args.buf].modified = false

	if config.options.verbose then
		vim.notify("SOPS file encrypted and saved successfully", vim.log.levels.INFO)
	end
end

M._extract_sops_keys = extract_sops_keys

return M
