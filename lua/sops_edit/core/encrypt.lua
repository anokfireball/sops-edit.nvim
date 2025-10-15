local config = require("sops_edit.config")
local utils = require("sops_edit.utils")

local M = {}

local KEY_TYPE_SPECS = {
	age = { field = "recipient", flag = "--age" },
	kms = { field = "arn", flag = "--kms" },
	gcp_kms = { field = "resource_id", flag = "--gcp-kms" },
	azure_kv = { field = "vault_url", flag = "--azure-kv" },
	pgp = { field = "fp", flag = "--pgp" },
	hc_vault_transit = { field = "vault_address", flag = "--hc-vault-transit" },
}

local function parse_key_type_yaml(sops_section, key_type, field_name)
	local section = sops_section:match(key_type .. ":(.-)%s*\n    [a-z_]+:")
		or sops_section:match(key_type .. ":(.-)$")
	if not section then
		return nil
	end

	local values = {}
	for value in section:gmatch(field_name .. ":%s*([^\n]+)") do
		value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^['\"]", ""):gsub("['\"]$", "")
		if value ~= "" then
			table.insert(values, value)
		end
	end

	return #values > 0 and values or nil
end

local function parse_key_type_json(sops_section, key_type, field_name)
	local array = sops_section:match('"' .. key_type .. '"%s*:%s*(%b[])')
	if not array or array == "[]" then
		return nil
	end

	local values = {}
	for value in array:gmatch('"' .. field_name .. '"%s*:%s*"([^"]+)"') do
		table.insert(values, value)
	end

	return #values > 0 and values or nil
end

local function parse_yaml_sops_metadata(content)
	local sops_section = content:match("\nsops:(.-)\n[^\n%s]") or content:match("\nsops:(.+)$")
	if not sops_section then
		return nil
	end

	local keys = {}
	for key_type, spec in pairs(KEY_TYPE_SPECS) do
		local values = parse_key_type_yaml(sops_section, key_type, spec.field)
		if values then
			keys[key_type] = values
		end
	end

	return keys
end

local function parse_json_sops_metadata(content)
	local sops_section = content:match('"sops"%s*:%s*({.-})[,}]%s*$')
	if not sops_section then
		return nil
	end

	local keys = {}
	for key_type, spec in pairs(KEY_TYPE_SPECS) do
		local values = parse_key_type_json(sops_section, key_type, spec.field)
		if values then
			keys[key_type] = values
		end
	end

	return keys
end

-- Extract SOPS encryption keys from an encrypted file's metadata section.
-- This allows re-encrypting files with the same recipients without needing .sops.yaml.
--
-- Process:
-- 1. Read the encrypted file from disk
-- 2. Parse YAML or JSON SOPS metadata section
-- 3. Extract age/KMS/GCP KMS/Azure Key Vault recipient identifiers
--
-- Returns: table with extracted keys, or nil if extraction fails
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
