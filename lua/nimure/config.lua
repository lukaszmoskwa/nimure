-- Nimure configuration module

local M = {}

-- Default configuration
M.defaults = {
	-- Sidebar configuration
	sidebar = {
		width = 40,
		position = "left", -- "left", "right", or "float"
		auto_close = false,
		border = "rounded", -- "none", "single", "double", "rounded", "solid", "shadow"
		float = {
			relative = "editor",
			row = 1,
			col = "80%",
			width = 50,
			height = "90%",
		},
	},

	-- Azure configuration
	azure = {
		subscription_id = nil, -- nil to use default subscription
		resource_groups = {}, -- empty to show all resource groups
		timeout = 30000, -- timeout in milliseconds
	},

	-- UI configuration
	ui = {
		show_icons = true,
		show_resource_group = true,
		show_location = true,
		show_type = true,
		show_tags = false,
		indent = "  ",
	},

	-- Keybindings
	keymaps = {
		toggle_sidebar = "<leader>az",
		toggle_floating = "<leader>af",
		refresh = "r",
		details = "<CR>",
		metrics = "m",
		copy_id = "y",
		copy_name = "Y",
		search = "/",
		close = "q",
		costs = "c", -- View costs
		cost_breakdown = "C", -- View detailed cost breakdown
		switch_subscription = "s", -- Switch Azure subscription
		-- Azure AD specific keymaps
		show_app_details = "a", -- Show app registration details
		show_user_details = "u", -- Show user details
		show_group_members = "g", -- Show group members
		show_role_details = "r", -- Show role assignment details
		ad_search = "S", -- Search Azure AD objects
		terraform_import = "t", -- Generate Terraform import block
	},

	-- Debug mode
	debug = false,

	-- Cost tracking configuration
	costs = {
		enabled = true,
		default_period_days = 30, -- Default to last 30 days
		show_daily_chart = true,
		show_service_breakdown = true,
		chart_height = 10, -- Height of ASCII charts
		-- Currency symbols are now auto-detected from Azure billing data
	},

	-- Cache and rate limiting configuration
	cache = {
		ttl_seconds = 300, -- 5 minutes cache TTL
		auto_cleanup = true, -- Automatically clean up old cache entries
	},

	rate_limiting = {
		enabled = true, -- Enable rate limiting to prevent API throttling
		min_interval_ms = 1000, -- Minimum 1 second between requests
		max_requests_per_minute = 20, -- Conservative API rate limit
	},

	-- Azure AD configuration
	azure_ad = {
		enabled = true,
		include_app_registrations = true,
		include_users = true,
		include_groups = true,
		include_role_assignments = true,
		include_service_principals = false, -- Optional: can be resource intensive
		-- Filter options for large environments
		user_filters = {}, -- Filter by UPN domain, etc.
		group_filters = {},
		app_filters = {},
	},
	-- Terraform integration configuration
	terraform = {
		enabled = true,
		backend = {
			resource_group_name = "terraform-state",
			storage_account_name = nil, -- User must configure for backend.tf generation
			container_name = "tfstate",
			key = "terraform.tfstate",
			use_azuread_cli = true,
		},
		output_dir = "/tmp/nimure-terraform",
		auto_open = true, -- Automatically open generated file in Neovim
		resource_name_placeholder = "example", -- Placeholder name for imported resources
	},
}

-- Current configuration
M.options = {}

-- Resource type icons mapping
M.icons = {
	-- Compute
	["Microsoft.Compute/virtualMachines"] = "🖥️ ",
	["Microsoft.Compute/virtualMachineScaleSets"] = "⚖️ ",
	["Microsoft.Compute/disks"] = "💾",
	["Microsoft.Compute/snapshots"] = "📸",

	-- Storage
	["Microsoft.Storage/storageAccounts"] = "🗄️ ",

	-- Networking
	["Microsoft.Network/virtualNetworks"] = "🌐",
	["Microsoft.Network/virtualNetworks/subnets"] = "🔗",
	["Microsoft.Network/publicIPAddresses"] = "🌍",
	["Microsoft.Network/networkSecurityGroups"] = "🛡️ ",
	["Microsoft.Network/loadBalancers"] = "⚖️ ",
	["Microsoft.Network/applicationGateways"] = "🚪",
	["Microsoft.Network/networkInterfaces"] = "🔌",

	-- App Services
	["Microsoft.Web/sites"] = "🌐",
	["Microsoft.Web/serverfarms"] = "📦",

	-- Databases
	["Microsoft.Sql/servers"] = "🗃️ ",
	["Microsoft.DocumentDB/databaseAccounts"] = "📊",
	["Microsoft.DBforMySQL/servers"] = "🐬",
	["Microsoft.DBforPostgreSQL/servers"] = "🐘",

	-- Key Vault
	["Microsoft.KeyVault/vaults"] = "🔐",

	-- Container
	["Microsoft.ContainerRegistry/registries"] = "📦",
	["Microsoft.ContainerInstance/containerGroups"] = "📦",
	["Microsoft.ContainerService/managedClusters"] = "☸️ ",

	-- Functions
	["Microsoft.Web/sites/functions"] = "⚡",

	-- Resource Groups
	["Microsoft.Resources/resourceGroups"] = "📁",

	-- Azure AD
	["Microsoft.AzureAD/appRegistrations"] = "📱",
	["Microsoft.AzureAD/users"] = "👤",
	["Microsoft.AzureAD/groups"] = "👥",
	["Microsoft.AzureAD/roleAssignments"] = "🔑",
	["Microsoft.AzureAD/servicePrincipals"] = "🎭",

	-- Default
	default = "📄",
}

-- Setup configuration
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

	-- Validate configuration
	M.validate()

	if M.options.debug then
		vim.schedule(function()
			vim.notify("Nimure configuration loaded", vim.log.levels.DEBUG)
			vim.notify("Config: " .. vim.inspect(M.options), vim.log.levels.DEBUG)
		end)
	end
end

-- Validate configuration
function M.validate()
	-- Validate sidebar position
	if
		M.options.sidebar.position ~= "left"
		and M.options.sidebar.position ~= "right"
		and M.options.sidebar.position ~= "float"
	then
		vim.schedule(function()
			vim.notify("Invalid sidebar position. Using 'left'", vim.log.levels.WARN)
		end)
		M.options.sidebar.position = "left"
	end

	-- Validate sidebar width
	if type(M.options.sidebar.width) ~= "number" or M.options.sidebar.width < 20 or M.options.sidebar.width > 100 then
		vim.schedule(function()
			vim.notify("Invalid sidebar width. Using 40", vim.log.levels.WARN)
		end)
		M.options.sidebar.width = 40
	end

	-- Validate timeout
	if type(M.options.azure.timeout) ~= "number" or M.options.azure.timeout < 1000 then
		vim.schedule(function()
			vim.notify("Invalid Azure timeout. Using 30000ms", vim.log.levels.WARN)
		end)
		M.options.azure.timeout = 30000
	end
end

-- Get icon for resource type
function M.get_icon(resource_type)
	if not M.options.ui.show_icons then
		return ""
	end

	return M.icons[resource_type] or M.icons.default
end

-- Get current configuration
function M.get()
	return M.options
end

return M
