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

	local success = pcall(function()
		lyaml = require("lyaml")
	end)
	if success then
		return lyaml
	end

	success = pcall(require, "luarocks.loader")
	if success then
		success = pcall(function()
			lyaml = require("lyaml")
		end)
		if success then
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

			success = pcall(function()
				lyaml = require("lyaml")
			end)
			if success then
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

	local success, docs = pcall(yaml.load, content)
	if not success or not docs then
		return nil
	end

	local doc = type(docs) == "table" and docs[1] or docs
	if not doc or not doc.sops then
		return nil
	end

	local recipients_by_type = {}
	for key_type, spec in pairs(KEY_TYPE_SPECS) do
		local key_section = doc.sops[key_type]
		if key_section and type(key_section) == "table" then
			local recipient_values = {}
			for _, entry in ipairs(key_section) do
				if type(entry) == "table" and entry[spec.field] then
					table.insert(recipient_values, entry[spec.field])
				end
			end
			if #recipient_values > 0 then
				recipients_by_type[key_type] = recipient_values
			end
		end
	end

	return recipients_by_type
end

local function parse_json_sops_metadata(content)
	local success, data = pcall(vim.json.decode, content)
	if not success or not data or not data.sops then
		return nil
	end

	local recipients_by_type = {}
	for key_type, spec in pairs(KEY_TYPE_SPECS) do
		local key_section = data.sops[key_type]
		if key_section and type(key_section) == "table" then
			local recipient_values = {}
			for _, entry in ipairs(key_section) do
				if type(entry) == "table" and entry[spec.field] then
					table.insert(recipient_values, entry[spec.field])
				end
			end
			if #recipient_values > 0 then
				recipients_by_type[key_type] = recipient_values
			end
		end
	end

	return recipients_by_type
end

local function parse_env_sops_metadata(content)
	local recipients_by_type = {}

	for key_type, spec in pairs(KEY_TYPE_SPECS) do
		local recipient_values = {}
		local prefix = "sops_" .. key_type .. "__list_"

		for line in content:gmatch("[^\r\n]+") do
			local key, value = line:match("^([^=]+)=(.*)$")
			if key and value then
				key = key:gsub("^%s*(.-)%s*$", "%1")
				value = value:gsub("^%s*(.-)%s*$", "%1")
				if key:match("^" .. prefix .. "%d+__map_" .. spec.field .. "$") then
					table.insert(recipient_values, value)
				end
			end
		end

		if #recipient_values > 0 then
			recipients_by_type[key_type] = recipient_values
		end
	end

	return next(recipients_by_type) and recipients_by_type or nil
end

local function parse_ini_sops_metadata(content)
	local recipients_by_type = {}
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
						if not recipients_by_type[key_type] then
							recipients_by_type[key_type] = {}
						end
						local idx = tonumber(index) + 1
						recipients_by_type[key_type][idx] = value
					end
				end
			end
		end
	end

	for key_type, recipient_values in pairs(recipients_by_type) do
		local indices = {}
		for idx in pairs(recipient_values) do
			table.insert(indices, idx)
		end
		table.sort(indices)

		local compact = {}
		for _, idx in ipairs(indices) do
			table.insert(compact, recipient_values[idx])
		end
		recipients_by_type[key_type] = compact
	end

	return next(recipients_by_type) and recipients_by_type or nil
end

local function extract_sops_keys(filepath)
	local file_handle = vim.loop.fs_open(filepath, "r", tonumber("644", 8))
	if not file_handle then
		return nil
	end

	local stat = vim.loop.fs_fstat(file_handle)
	if not stat then
		vim.loop.fs_close(file_handle)
		return nil
	end

	local content = vim.loop.fs_read(file_handle, stat.size, 0)
	vim.loop.fs_close(file_handle)

	if not content then
		return nil
	end

	local file_extension = (filepath:match("%.([^%.]+)$") or ""):lower()
	if file_extension == "json" then
		return parse_json_sops_metadata(content)
	elseif file_extension == "env" then
		return parse_env_sops_metadata(content)
	elseif file_extension == "ini" then
		return parse_ini_sops_metadata(content)
	elseif file_extension == "yaml" or file_extension == "yml" then
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

	local file_extension = (filepath:match("%.([^%.]+)$") or ""):lower()
	local format_map = {
		json = "json",
		env = "dotenv",
		ini = "ini",
		yml = "yaml",
		yaml = "yaml",
	}
	local input_type = format_map[file_extension]

	if not input_type then
		secure_cleanup()
		vim.notify(
			string.format(
				"Error: Unknown file extension '.%s' for %s. Supported: json, yaml, yml, env, ini",
				file_extension,
				vim.fn.fnamemodify(filepath, ":~")
			),
			vim.log.levels.ERROR
		)
		return
	end

	local ALLOWED_INPUT_TYPES = {
		json = true,
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

	local recipients_by_type = extract_sops_keys(filepath)
	local key_flags = ""

	if recipients_by_type then
		for key_type, spec in pairs(KEY_TYPE_SPECS) do
			if recipients_by_type[key_type] and #recipients_by_type[key_type] > 0 then
				key_flags = key_flags
					.. string.format(" %s %s", spec.flag, vim.fn.shellescape(table.concat(recipients_by_type[key_type], ",")))
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

	local success, encrypted_output, error_msg = utils.execute_command(cmd, full_plaintext)
	secure_cleanup()

	if not success then
		vim.notify(
			string.format("SOPS encryption failed for %s:\n%s", vim.fn.fnamemodify(filepath, ":~"), error_msg),
			vim.log.levels.ERROR
		)
		return
	end

	local uv = vim.loop
	local stat = uv.fs_stat(filepath)
	local original_mode = stat and stat.mode or tonumber("600", 8)
	local safe_mode = tonumber("600", 8)

	local tmp_filepath = filepath .. ".sops." .. uv.hrtime() .. ".tmp"

	local file_handle = uv.fs_open(tmp_filepath, "w", safe_mode)
	if not file_handle then
		vim.notify(
			string.format("Error: Could not create temporary file %s", vim.fn.fnamemodify(tmp_filepath, ":~")),
			vim.log.levels.ERROR
		)
		return
	end

	local write_ok = uv.fs_write(file_handle, encrypted_output, -1)
	if not write_ok then
		uv.fs_close(file_handle)
		uv.fs_unlink(tmp_filepath)
		vim.notify(
			string.format("Error: Could not write to temporary file %s", vim.fn.fnamemodify(tmp_filepath, ":~")),
			vim.log.levels.ERROR
		)
		return
	end

	uv.fs_fsync(file_handle)
	uv.fs_close(file_handle)

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
