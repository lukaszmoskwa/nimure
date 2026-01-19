-- Health check module for Nimure

local M = {}

-- Main health check function
function M.check()
	local health = vim.health or require("health")

	health.start("Nimure: Azure Resource Explorer")

	-- Check Neovim version
	M.check_neovim_version(health)

	-- Check required plugins
	M.check_required_plugins(health)

	-- Check Azure CLI
	M.check_azure_cli(health)

	-- Check Azure authentication
	M.check_azure_auth(health)

	-- Check configuration
	M.check_configuration(health)

	-- Check Terraform (optional)
	M.check_terraform(health)
end

-- Check Neovim version
function M.check_neovim_version(health)
	local version = vim.version()
	local required_major = 0
	local required_minor = 8

	if version.major > required_major or (version.major == required_major and version.minor >= required_minor) then
		health.ok(string.format("Neovim version %d.%d.%d is supported", version.major, version.minor, version.patch))
	else
		health.error(
			string.format(
				"Neovim version %d.%d.%d is not supported. Requires >= %d.%d",
				version.major,
				version.minor,
				version.patch,
				required_major,
				required_minor
			)
		)
	end
end

-- Check required plugins
function M.check_required_plugins(health)
	local required_plugins = {
		{
			name = "nui.nvim",
			module = "nui.popup",
			desc = "Required for UI components",
		},
		{
			name = "telescope.nvim",
			module = "telescope",
			desc = "Required for resource search",
		},
		{
			name = "plenary.nvim",
			module = "plenary.job",
			desc = "Required for async operations",
		},
	}

	local optional_plugins = {
		{
			name = "nvim-web-devicons",
			module = "nvim-web-devicons",
			desc = "Optional for resource type icons",
		},
	}

	for _, plugin in ipairs(required_plugins) do
		local ok, _ = pcall(require, plugin.module)
		if ok then
			health.ok(plugin.name .. " is installed")
		else
			health.error(plugin.name .. " is not installed - " .. plugin.desc)
		end
	end

	for _, plugin in ipairs(optional_plugins) do
		local ok, _ = pcall(require, plugin.module)
		if ok then
			health.ok(plugin.name .. " is installed")
		else
			health.warn(plugin.name .. " is not installed - " .. plugin.desc)
		end
	end
end

-- Check Azure CLI
function M.check_azure_cli(health)
	local azure = require("nimure.azure")

	if azure.check_cli() then
		health.ok("Azure CLI is installed and accessible")
	else
		health.error("Azure CLI is not installed or not in PATH")
		health.info("Install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli")
	end
end

-- Check Azure authentication
function M.check_azure_auth(health)
	local azure = require("nimure.azure")

	if not azure.check_cli() then
		health.error("Cannot check Azure authentication - Azure CLI not available")
		return
	end

	if azure.check_auth() then
		health.ok("Azure CLI is authenticated")

		-- Get subscription info
		azure.get_subscription_info(function(info, error)
			if error then
				health.warn("Could not get subscription info: " .. error)
			else
				health.ok("Current subscription: " .. info.name .. " (" .. info.id .. ")")
			end
		end)
	else
		health.error("Azure CLI is not authenticated")
		health.info("Run 'az login' to authenticate with Azure")
	end
end

-- Check configuration
function M.check_configuration(health)
	local config = require("nimure.config")
	local options = config.get()

	if not options or vim.tbl_isempty(options) then
		health.warn("Nimure configuration not found - using defaults")
		return
	end

	health.ok("Nimure configuration loaded")

	-- Check sidebar configuration
	if options.sidebar then
		if options.sidebar.width and options.sidebar.width >= 20 and options.sidebar.width <= 100 then
			health.ok("Sidebar width is valid: " .. options.sidebar.width)
		else
			health.warn("Sidebar width may be invalid: " .. tostring(options.sidebar.width))
		end

		if options.sidebar.position == "left" or options.sidebar.position == "right" then
			health.ok("Sidebar position is valid: " .. options.sidebar.position)
		else
			health.warn("Sidebar position may be invalid: " .. tostring(options.sidebar.position))
		end
	end

	-- Check Azure configuration
	if options.azure then
		if options.azure.subscription_id then
			health.info("Using specific subscription: " .. options.azure.subscription_id)
		else
			health.info("Using default subscription")
		end

		if options.azure.timeout and options.azure.timeout >= 1000 then
			health.ok("Azure timeout is valid: " .. options.azure.timeout .. "ms")
		else
			health.warn("Azure timeout may be too low: " .. tostring(options.azure.timeout))
		end
	end

	-- Check debug mode
	if options.debug then
		health.info("Debug mode is enabled")
	end
end

-- Check Terraform CLI and configuration
function M.check_terraform(health)
	local terraform = require("nimure.terraform")
	local config = require("nimure.config")
	local options = config.get()

	health.start("Nimure: Terraform Integration")

	-- Check if Terraform feature is enabled
	if not options.terraform or not options.terraform.enabled then
		health.info("Terraform integration is disabled")
		return
	end

	-- Check Terraform CLI
	if terraform.check_terraform_cli() then
		health.ok("Terraform CLI is installed")

		-- Get version asynchronously - display result when available
		terraform.get_terraform_version(function(version, err)
			if version then
				vim.schedule(function()
					vim.notify("Terraform version: " .. version, vim.log.levels.DEBUG)
				end)
			end
		end)
	else
		health.warn("Terraform CLI not found - import generation will not work")
		health.info("Install Terraform: https://developer.hashicorp.com/terraform/downloads")
	end

	-- Check output directory
	local output_dir = options.terraform.output_dir
	if vim.fn.isdirectory(output_dir) == 1 then
		health.ok("Output directory exists: " .. output_dir)
	else
		health.info("Output directory will be created: " .. output_dir)
	end

	-- Check write permissions
	local test_file = output_dir .. "/.nimure_test"
	if vim.fn.isdirectory(output_dir) == 1 then
		local file = io.open(test_file, "w")
		if file then
			file:close()
			os.remove(test_file)
			health.ok("Output directory is writable")
		else
			health.warn("Output directory is not writable: " .. output_dir)
		end
	end

	-- Check backend configuration
	if options.terraform.backend.storage_account_name then
		health.ok("Terraform backend is configured")
		health.info("  Storage Account: " .. options.terraform.backend.storage_account_name)
		health.info("  Container: " .. options.terraform.backend.container_name)
		health.info("  Key: " .. options.terraform.backend.key)
	else
		health.info("Terraform backend not configured - backend.tf will not be generated")
		health.info("Configure terraform.backend.storage_account_name to enable backend generation")
	end

	-- Show supported resource types count
	local supported_types = terraform.list_supported_types()
	health.ok(string.format("Supported Azure resource types: %d", #supported_types))
end

return M
