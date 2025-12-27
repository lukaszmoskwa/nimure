-- Nimure: Azure Resource Explorer for Neovim
-- Main module

local config = require("nimure.config")
local ui = require("nimure.ui")
local azure = require("nimure.azure")
local azure_ad = require("nimure.azure_ad")
local telescope_extension = require("nimure.telescope")
local costs = require("nimure.costs")

local M = {}

-- Plugin state
M.state = {
	setup_done = false,
	sidebar_open = false,
	resources = {},
	ad_objects = {},
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

	if config.options.keymaps.switch_subscription then
		vim.keymap.set("n", config.options.keymaps.switch_subscription, function()
			M.switch_subscription()
		end, { desc = "Switch Azure subscription" })
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
	if (#M.state.resources == 0 or #M.state.ad_objects == 0) and not M.state.loading then
		M.refresh_resources()
	else
		ui.update_sidebar(M.state.resources, M.state.ad_objects)
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

	local resource_count = 0
	local ad_count = 0
	local completed_requests = 0
	local total_requests = 2 -- Resources and AD

	-- Get regular Azure resources
	azure.get_resources(function(resources, error)
		completed_requests = completed_requests + 1
		if error then
			vim.schedule(function()
				vim.notify("Failed to fetch Azure resources: " .. error, vim.log.levels.WARN)
			end)
		else
			M.state.resources = resources
			resource_count = #resources
		end

		-- Check if both requests are complete
		if completed_requests == total_requests then
			M._refresh_complete(resource_count, ad_count, callback)
		end
	end)

	-- Get Azure AD objects if enabled
	local options = config.get()
	if options.azure_ad.enabled then
		azure_ad.check_ad_permissions(function(has_permission, permission_error)
			if not has_permission then
				vim.schedule(function()
					vim.notify("Azure AD access: " .. permission_error, vim.log.levels.WARN)
				end)
				completed_requests = completed_requests + 1
			else
				-- Get all AD objects
				M._fetch_ad_objects(function(count, fetch_error)
					completed_requests = completed_requests + 1
					if fetch_error then
						vim.schedule(function()
							vim.notify("Failed to fetch AD objects: " .. fetch_error, vim.log.levels.WARN)
						end)
					else
						ad_count = count
					end

					-- Check if both requests are complete
					if completed_requests == total_requests then
						M._refresh_complete(resource_count, ad_count, callback)
					end
				end)
			end
		end)
	else
		completed_requests = completed_requests + 1
		if completed_requests == total_requests then
			M._refresh_complete(resource_count, ad_count, callback)
		end
	end
end

-- Fetch all Azure AD objects
function M._fetch_ad_objects(callback)
	local completed_requests = 0
	local total_requests = 4 -- Apps, Users, Groups, Roles
	local ad_objects = {}
	local total_count = 0

	local function check_complete()
		if completed_requests == total_requests then
			callback(total_count, nil)
		end
	end

	-- Get app registrations
	azure_ad.get_app_registrations(function(apps, error)
		completed_requests = completed_requests + 1
		if not error then
			ad_objects.app_registrations = apps
			total_count = total_count + #apps
		end
		check_complete()
	end)

	-- Get users
	azure_ad.get_users(function(users, error)
		completed_requests = completed_requests + 1
		if not error then
			ad_objects.users = users
			total_count = total_count + #users
		end
		check_complete()
	end)

	-- Get groups
	azure_ad.get_groups(function(groups, error)
		completed_requests = completed_requests + 1
		if not error then
			ad_objects.groups = groups
			total_count = total_count + #groups
		end
		check_complete()
	end)

	-- Get role assignments
	azure_ad.get_role_assignments(function(roles, error)
		completed_requests = completed_requests + 1
		if not error then
			ad_objects.role_assignments = roles
			total_count = total_count + #roles
		end
		check_complete()
	end)

	M.state.ad_objects = ad_objects
end

-- Complete refresh operation
function M._refresh_complete(resource_count, ad_count, callback)
	M.state.loading = false

	-- Use vim.schedule to defer notifications out of fast event context
	vim.schedule(function()
		-- Update sidebar if open
		if M.state.sidebar_open then
			ui.update_sidebar(M.state.resources, M.state.ad_objects)
		end

		-- Show combined notification
		local messages = {}
		if resource_count > 0 then
			table.insert(messages, resource_count .. " Azure resources")
		end
		if ad_count > 0 then
			table.insert(messages, ad_count .. " AD objects")
		end

		if #messages > 0 then
			vim.notify("Refreshed " .. table.concat(messages, " and "), vim.log.levels.INFO)
		end

		if callback then
			callback()
		end
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

-- Search Azure AD objects with telescope
function M.search_ad_objects()
	if not M.state.ad_objects or M.count_ad_objects(M.state.ad_objects) == 0 then
		vim.schedule(function()
			vim.notify("No AD objects loaded. Refreshing...", vim.log.levels.INFO)
		end)
		M.refresh_resources(function()
			telescope_extension.search_ad_objects(M.state.ad_objects)
		end)
		return
	end

	telescope_extension.search_ad_objects(M.state.ad_objects)
end

-- Count AD objects
function M.count_ad_objects(ad_objects)
	if not ad_objects then
		return 0
	end
	
	local count = 0
	if ad_objects.app_registrations then
		count = count + #ad_objects.app_registrations
	end
	if ad_objects.users then
		count = count + #ad_objects.users
	end
	if ad_objects.groups then
		count = count + #ad_objects.groups
	end
	if ad_objects.role_assignments then
		count = count + #ad_objects.role_assignments
	end
	if ad_objects.service_principals then
		count = count + #ad_objects.service_principals
	end
	
	return count
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

-- Show Azure AD object details
function M.show_ad_object_details(ad_object)
	local details_function = nil
	
	-- Choose appropriate function based on AD object type
	if ad_object.type == "Microsoft.AzureAD/appRegistrations" then
		details_function = azure_ad.get_app_registration_details
	elseif ad_object.type == "Microsoft.AzureAD/users" then
		details_function = azure_ad.get_user_details
	elseif ad_object.type == "Microsoft.AzureAD/groups" then
		details_function = azure_ad.get_group_members
	elseif ad_object.type == "Microsoft.AzureAD/roleAssignments" then
		-- For role assignments, we have enough data from the list
		ui.show_ad_object_details(ad_object, { properties = ad_object.properties })
		return
	else
		-- Fallback - show basic info without additional API call
		ui.show_ad_object_details(ad_object, { properties = ad_object.properties })
		return
	end

	if details_function then
		details_function(ad_object, function(details, error)
			vim.schedule(function()
				if error then
					vim.notify("Failed to get AD object details: " .. error, vim.log.levels.ERROR)
					-- Show basic info anyway
					ui.show_ad_object_details(ad_object, { properties = ad_object.properties })
					return
				end

				ui.show_ad_object_details(ad_object, details)
			end)
		end)
	end
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

-- Switch Azure subscription
function M.switch_subscription()
	telescope_extension.switch_subscription()
end

-- Get current state (for debugging)
function M.get_state()
	return M.state
end

return M
