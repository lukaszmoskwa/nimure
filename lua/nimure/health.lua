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

return M
