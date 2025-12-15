-- Nimure: Azure Resource Explorer for Neovim
-- Main module

local config = require("nimure.config")
local ui = require("nimure.ui")
local azure = require("nimure.azure")
local telescope_extension = require("nimure.telescope")
local costs = require("nimure.costs")

local M = {}

-- Plugin state
M.state = {
	setup_done = false,
	sidebar_open = false,
	resources = {},
	loading = false,
}

-- Setup function
function M.setup(opts)
	if M.state.setup_done then
		return
	end

	-- Merge user config with defaults
	config.setup(opts)

	-- Register telescope extension
	telescope_extension.setup()

	-- Set up global keymaps if configured
	if config.options.keymaps.toggle_sidebar then
		vim.keymap.set("n", config.options.keymaps.toggle_sidebar, function()
			M.toggle_sidebar()
		end, { desc = "Toggle Nimure sidebar" })
	end

	if config.options.keymaps.toggle_floating then
		vim.keymap.set("n", config.options.keymaps.toggle_floating, function()
			M.toggle_floating_right()
		end, { desc = "Toggle floating sidebar on right" })
	end

	M.state.setup_done = true
end

-- Toggle sidebar
function M.toggle_sidebar()
	if M.state.sidebar_open then
		M.close_sidebar()
	else
		M.open_sidebar()
	end
end

-- Open sidebar
function M.open_sidebar()
	if M.state.sidebar_open then
		return
	end

	-- Create and show sidebar
	ui.create_sidebar()
	M.state.sidebar_open = true

	-- Load resources if not already loaded
	if #M.state.resources == 0 and not M.state.loading then
		M.refresh_resources()
	else
		ui.update_sidebar(M.state.resources)
	end
end

-- Close sidebar
function M.close_sidebar()
	if not M.state.sidebar_open then
		return
	end

	ui.close_sidebar()
	M.state.sidebar_open = false
end

-- Refresh resources
function M.refresh_resources(callback)
	if M.state.loading then
		return
	end

	M.state.loading = true

	-- Update UI to show loading state
	if M.state.sidebar_open then
		ui.show_loading()
	end

	azure.get_resources(function(resources, error)
		M.state.loading = false

		-- Use vim.schedule to defer notifications out of fast event context
		vim.schedule(function()
			if error then
				vim.notify("Failed to fetch Azure resources: " .. error, vim.log.levels.ERROR)
				if M.state.sidebar_open then
					ui.show_error(error)
				end
				return
			end

			M.state.resources = resources

			-- Update sidebar if open
			if M.state.sidebar_open then
				ui.update_sidebar(resources)
			end

			vim.notify("Refreshed " .. #resources .. " Azure resources", vim.log.levels.INFO)

			if callback then
				callback()
			end
		end)
	end)
end

-- Search resources with telescope
function M.search_resources()
	if #M.state.resources == 0 then
		vim.schedule(function()
			vim.notify("No resources loaded. Refreshing...", vim.log.levels.INFO)
		end)
		M.refresh_resources(function()
			telescope_extension.search_resources(M.state.resources)
		end)
		return
	end

	telescope_extension.search_resources(M.state.resources)
end

-- Show resource details
function M.show_resource_details(resource)
	azure.get_resource_details(resource, function(details, error)
		vim.schedule(function()
			if error then
				vim.notify("Failed to get resource details: " .. error, vim.log.levels.ERROR)
				return
			end

			ui.show_resource_details(resource, details)
		end)
	end)
end

-- Show resource metrics
function M.show_resource_metrics(resource)
	azure.get_resource_metrics(resource, function(metrics, error)
		vim.schedule(function()
			if error then
				vim.notify("Failed to get resource metrics: " .. error, vim.log.levels.ERROR)
				return
			end

			ui.show_resource_metrics(resource, metrics)
		end)
	end)
end

-- Copy resource ID to clipboard
function M.copy_resource_id(resource)
	vim.fn.setreg("+", resource.id)
	vim.schedule(function()
		vim.notify("Copied resource ID: " .. resource.id, vim.log.levels.INFO)
	end)
end

-- Copy resource name to clipboard
function M.copy_resource_name(resource)
	vim.fn.setreg("+", resource.name)
	vim.schedule(function()
		vim.notify("Copied resource name: " .. resource.name, vim.log.levels.INFO)
	end)
end

-- Toggle sidebar to floating on the right
function M.toggle_floating_right()
	local current_config = config.get()

	if current_config.sidebar.position == "float" then
		-- Switch back to left split
		current_config.sidebar.position = "left"
	else
		-- Switch to floating on the right
		current_config.sidebar.position = "float"
	end

	-- Close current sidebar if open
	if M.state.sidebar_open then
		M.close_sidebar()
		-- Reopen with new position
		vim.schedule(function()
			M.open_sidebar()
		end)
	end
end

-- Show subscription cost overview
function M.show_subscription_costs(options)
	options = options or {}

	-- Set default period if not specified
	if not options.start_date then
		local default_days = config.get().costs.default_period_days
		options.start_date = os.date("%Y-%m-%d", os.time() - default_days * 24 * 60 * 60)
	end
	if not options.end_date then
		options.end_date = os.date("%Y-%m-%d")
	end

	azure.get_subscription_costs(options, function(cost_data, error)
		vim.schedule(function()
			if error then
				vim.notify("Failed to get subscription costs: " .. error, vim.log.levels.ERROR)
				return
			end

			ui.show_cost_overview(cost_data)
		end)
	end)
end

-- Show detailed cost breakdown
function M.show_cost_breakdown(options)
	options = options or {}

	-- Set default period if not specified
	if not options.start_date then
		local default_days = config.get().costs.default_period_days
		options.start_date = os.date("%Y-%m-%d", os.time() - default_days * 24 * 60 * 60)
	end
	if not options.end_date then
		options.end_date = os.date("%Y-%m-%d")
	end

	azure.get_subscription_costs(options, function(cost_data, error)
		vim.schedule(function()
			if error then
				vim.notify("Failed to get cost breakdown: " .. error, vim.log.levels.ERROR)
				return
			end

			ui.show_cost_breakdown(cost_data)
		end)
	end)
end

-- Show resource-specific costs
function M.show_resource_costs(resource, options)
	options = options or {}

	-- Set default period if not specified
	if not options.start_date then
		local default_days = config.get().costs.default_period_days
		options.start_date = os.date("%Y-%m-%d", os.time() - default_days * 24 * 60 * 60)
	end
	if not options.end_date then
		options.end_date = os.date("%Y-%m-%d")
	end

	azure.get_resource_costs(resource, options, function(resource_costs, error)
		vim.schedule(function()
			if error then
				vim.notify("Failed to get resource costs: " .. error, vim.log.levels.ERROR)
				return
			end

			ui.show_resource_cost_details(resource_costs)
		end)
	end)
end

-- Get current state (for debugging)
function M.get_state()
	return M.state
end

return M
