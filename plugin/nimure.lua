-- Nimure: Azure Resource Explorer for Neovim
-- Plugin entry point

if vim.g.loaded_nimure then
	return
end
vim.g.loaded_nimure = 1

-- Create user commands
vim.api.nvim_create_user_command("NimureToggle", function()
	require("nimure").toggle_sidebar()
end, {
	desc = "Toggle Nimure sidebar",
})

vim.api.nvim_create_user_command("NimureOpen", function()
	require("nimure").open_sidebar()
end, {
	desc = "Open Nimure sidebar",
})

vim.api.nvim_create_user_command("NimureClose", function()
	require("nimure").close_sidebar()
end, {
	desc = "Close Nimure sidebar",
})

vim.api.nvim_create_user_command("NimureRefresh", function()
	require("nimure").refresh_resources()
end, {
	desc = "Refresh Azure resources",
})

vim.api.nvim_create_user_command("NimureSearch", function()
	require("nimure").search_resources()
end, {
	desc = "Search Azure resources with Telescope",
})

vim.api.nvim_create_user_command("NimureFloatRight", function()
	require("nimure").toggle_floating_right()
end, {
	desc = "Toggle floating sidebar on the right",
})

-- Cost tracking commands
vim.api.nvim_create_user_command("NimureCosts", function()
	require("nimure").show_subscription_costs()
end, {
	desc = "Show Azure subscription costs",
})

vim.api.nvim_create_user_command("NimureCostBreakdown", function()
	require("nimure").show_cost_breakdown()
end, {
	desc = "Show detailed Azure cost breakdown",
})

vim.api.nvim_create_user_command("NimureCostsCustom", function(opts)
	local args = vim.split(opts.args, " ", { plain = true })
	local options = {}

	-- Parse custom date range if provided
	-- Usage: :NimureCostsCustom 2024-01-01 2024-01-31
	if #args >= 2 then
		options.start_date = args[1]
		options.end_date = args[2]
	end

	require("nimure").show_subscription_costs(options)
end, {
	desc = "Show Azure costs for custom date range",
	nargs = "*",
	complete = function()
		-- Provide some example date ranges
		return {
			os.date("%Y-%m-01", os.time() - 30 * 24 * 60 * 60) .. " " .. os.date("%Y-%m-%d"),
			os.date("%Y-%m-01", os.time() - 60 * 24 * 60 * 60)
				.. " "
				.. os.date("%Y-%m-01", os.time() - 30 * 24 * 60 * 60),
			os.date("%Y-01-01") .. " " .. os.date("%Y-%m-%d"),
		}
	end,
})

-- Cache management command
vim.api.nvim_create_user_command("NimureClearCache", function()
	require("nimure.azure").clear_cache()
end, {
	desc = "Clear Azure data cache to force fresh data",
})

-- Subscription management
vim.api.nvim_create_user_command("NimureSwitchSubscription", function()
	require("nimure").switch_subscription()
end, {
	desc = "Switch Azure subscription",
})

-- Azure AD commands
vim.api.nvim_create_user_command("NimureADSearch", function()
	require("nimure").search_ad_objects()
end, {
	desc = "Search Azure AD objects with Telescope",
})

vim.api.nvim_create_user_command("NimureADApps", function()
	require("nimure.azure_ad").get_app_registrations(function(apps, error)
		if error then
			vim.schedule(function()
				vim.notify("Failed to get app registrations: " .. error, vim.log.levels.ERROR)
			end)
			return
		end
		
		local ad_objects = { app_registrations = apps }
		require("nimure").search_ad_objects(ad_objects)
	end)
end, {
	desc = "Search Azure AD app registrations",
})

vim.api.nvim_create_user_command("NimureADUsers", function()
	require("nimure.azure_ad").get_users(function(users, error)
		if error then
			vim.schedule(function()
				vim.notify("Failed to get users: " .. error, vim.log.levels.ERROR)
			end)
			return
		end
		
		local ad_objects = { users = users }
		require("nimure").search_ad_objects(ad_objects)
	end)
end, {
	desc = "Search Azure AD users",
})

vim.api.nvim_create_user_command("NimureADGroups", function()
	require("nimure.azure_ad").get_groups(function(groups, error)
		if error then
			vim.schedule(function()
				vim.notify("Failed to get groups: " .. error, vim.log.levels.ERROR)
			end)
			return
		end
		
		local ad_objects = { groups = groups }
		require("nimure").search_ad_objects(ad_objects)
	end)
end, {
	desc = "Search Azure AD groups",
})

vim.api.nvim_create_user_command("NimureADRoles", function()
	require("nimure.azure_ad").get_role_assignments(function(roles, error)
		if error then
			vim.schedule(function()
				vim.notify("Failed to get role assignments: " .. error, vim.log.levels.ERROR)
			end)
			return
		end
		
		local ad_objects = { role_assignments = roles }
		require("nimure").search_ad_objects(ad_objects)
	end)
end, {
	desc = "Search Azure AD role assignments",
})

-- Cache management command
vim.api.nvim_create_user_command("NimureClearCache", function()
	local azure = require("nimure.azure")
	local azure_ad = require("nimure.azure_ad")
	
	azure.clear_cache()
	azure_ad.clear_cache()
	
	vim.schedule(function()
		vim.notify("Azure and Azure AD cache cleared", vim.log.levels.INFO)
	end)
end, {
	desc = "Clear Azure and Azure AD data cache to force fresh data",
})

-- Set up health check
vim.api.nvim_create_user_command("NimureHealth", function()
	require("nimure.health").check()
end, {
	desc = "Check Nimure health",
})
