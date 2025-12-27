-- Telescope integration for Nimure

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local config = require("nimure.config")
local utils = require("nimure.utils")

local M = {}

-- Setup telescope extension
function M.setup()
	-- Register the extension
	pcall(require("telescope").load_extension, "nimure")
end

-- Main resource search function
function M.search_resources(resources)
	if not resources or #resources == 0 then
		vim.schedule(function()
			vim.notify("No resources to search", vim.log.levels.WARN)
		end)
		return
	end

	local opts = {}

	pickers
		.new(opts, {
			prompt_title = "Azure Resources",
			finder = finders.new_table({
				results = resources,
				entry_maker = function(resource)
					local icon = config.get_icon(resource.type)
					local display_name = string.format(
						"%s%s (%s) [%s]",
						icon,
						resource.name,
						utils.get_short_type(resource.type),
						resource.location
					)

					return {
						value = resource,
						display = display_name,
						ordinal = resource.name
							.. " "
							.. resource.type
							.. " "
							.. resource.resource_group
							.. " "
							.. resource.location,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = M.create_resource_previewer(),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						require("nimure").show_resource_details(selection.value)
					end
				end)

				-- Copy resource ID
				map("i", "<C-y>", function()
					local selection = action_state.get_selected_entry()
					if selection then
						require("nimure").copy_resource_id(selection.value)
					end
				end)

				-- Copy resource name
				map("i", "<C-n>", function()
					local selection = action_state.get_selected_entry()
					if selection then
						require("nimure").copy_resource_name(selection.value)
					end
				end)

				-- Show metrics
				map("i", "<C-m>", function()
					local selection = action_state.get_selected_entry()
					if selection then
						require("nimure").show_resource_metrics(selection.value)
					end
				end)

				return true
			end,
		})
		:find()
end

-- Create resource previewer
function M.create_resource_previewer()
	return previewers.new_buffer_previewer({
		title = "Resource Details",
		define_preview = function(self, entry, status)
			local resource = entry.value
			local lines = {}

			-- Basic info
			table.insert(lines, "Name: " .. resource.name)
			table.insert(lines, "Type: " .. resource.type)
			table.insert(lines, "Location: " .. utils.format_location(resource.location))
			table.insert(lines, "Resource Group: " .. resource.resource_group)
			table.insert(lines, "")

			-- Resource ID
			table.insert(lines, "Resource ID:")
			table.insert(lines, resource.id)
			table.insert(lines, "")

			-- Tags
			-- Check is tags is a table
			if resource.tags and type(resource.tags) == "table" and vim.tbl_count(resource.tags) > 0 then
				table.insert(lines, "Tags:")
				for key, value in pairs(resource.tags) do
					table.insert(lines, "  " .. key .. ": " .. value)
				end
				table.insert(lines, "")
			end

			-- Additional info
			if resource.kind and type(resource.kind) == "string" then
				table.insert(lines, "Kind: " .. resource.kind .. " (" .. resource.kind .. ")")
			end

			if resource.sku and type(resource.sku) == "table" then
				local sku = vim.inspect(resource.sku)
				-- For each key, add a new line
				for key, value in sku:gmatch("([^:]+):([^,]+)") do
					table.insert(lines, key .. ": " .. value)
				end
			end
			local txt = [[
Actions:
  <Enter> - Show detailed information
  <C-y>   - Copy resource ID
  <C-n>   - Copy resource name
  <C-m>   - Show metrics
]]

			for line in txt:gmatch("[^\r\n]+") do
				table.insert(lines, line)
			end

			-- Remove the newlines in the items
			for i, line in ipairs(lines) do
				if line:sub(-1) == "\n" then
					lines[i] = line:sub(1, -2)
				end
			end

			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
		end,
	})
end

-- Search by resource type
function M.search_by_type(resources, resource_type)
	local filtered = {}
	for _, resource in ipairs(resources) do
		if resource.type == resource_type then
			table.insert(filtered, resource)
		end
	end

	if #filtered == 0 then
		vim.schedule(function()
			vim.notify("No resources found of type: " .. resource_type, vim.log.levels.INFO)
		end)
		return
	end

	M.search_resources(filtered)
end

-- Search by resource group
function M.search_by_resource_group(resources, resource_group)
	local filtered = {}
	for _, resource in ipairs(resources) do
		if resource.resource_group == resource_group then
			table.insert(filtered, resource)
		end
	end

	if #filtered == 0 then
		vim.schedule(function()
			vim.notify("No resources found in resource group: " .. resource_group, vim.log.levels.INFO)
		end)
		return
	end

	M.search_resources(filtered)
end

-- Search by location
function M.search_by_location(resources, location)
	local filtered = {}
	for _, resource in ipairs(resources) do
		if resource.location == location then
			table.insert(filtered, resource)
		end
	end

	if #filtered == 0 then
		vim.schedule(function()
			vim.notify("No resources found in location: " .. location, vim.log.levels.INFO)
		end)
		return
	end

	M.search_resources(filtered)
end

-- Get unique resource types
function M.get_resource_types(resources)
	local types = {}
	local seen = {}

	for _, resource in ipairs(resources) do
		if not seen[resource.type] then
			table.insert(types, resource.type)
			seen[resource.type] = true
		end
	end

	table.sort(types)
	return types
end

-- Get unique resource groups
function M.get_resource_groups(resources)
	local groups = {}
	local seen = {}

	for _, resource in ipairs(resources) do
		if not seen[resource.resource_group] then
			table.insert(groups, resource.resource_group)
			seen[resource.resource_group] = true
		end
	end

	table.sort(groups)
	return groups
end

-- Get unique locations
function M.get_locations(resources)
	local locations = {}
	local seen = {}

	for _, resource in ipairs(resources) do
		if not seen[resource.location] then
			table.insert(locations, resource.location)
			seen[resource.location] = true
		end
	end

	table.sort(locations)
	return locations
end

-- Subscription switcher
function M.switch_subscription()
	local azure = require("nimure.azure")

	azure.list_subscriptions(function(subscriptions, error)
		if error then
			vim.schedule(function()
				vim.notify("Failed to list subscriptions: " .. error, vim.log.levels.ERROR)
			end)
			return
		end

		if #subscriptions == 0 then
			vim.schedule(function()
				vim.notify("No subscriptions found", vim.log.levels.WARN)
			end)
			return
		end

		-- Create picker in vim.schedule to avoid fast context issues
		vim.schedule(function()
			local opts = {}

			pickers
				.new(opts, {
					prompt_title = "Azure Subscriptions",
					finder = finders.new_table({
						results = subscriptions,
						entry_maker = function(subscription)
							local default_indicator = subscription.is_default and " (current)" or ""
							local display_name = string.format(
								"%s%s [%s]%s",
								subscription.name,
								default_indicator,
								subscription.cloud_name or "AzureCloud",
								subscription.state ~= "Enabled" and " (" .. subscription.state .. ")" or ""
							)

							return {
								value = subscription,
								display = display_name,
								ordinal = subscription.name .. " " .. subscription.id,
							}
						end,
					}),
					sorter = conf.generic_sorter(opts),
					attach_mappings = function(prompt_bufnr, map)
						actions.select_default:replace(function()
							actions.close(prompt_bufnr)
							local selection = action_state.get_selected_entry()
							if selection then
								azure.set_subscription(selection.value.id, function(success, error)
									if error then
										vim.schedule(function()
											vim.notify("Failed to switch subscription: " .. error, vim.log.levels.ERROR)
										end)
									else
										vim.schedule(function()
											vim.notify(
												"Switched to subscription: " .. selection.value.name,
												vim.log.levels.INFO
											)
											-- Refresh resources to show resources from new subscription
											require("nimure").refresh_resources()
										end)
									end
								end)
							end
						end)

						-- Copy subscription ID
						map("i", "<C-y>", function()
							local selection = action_state.get_selected_entry()
							if selection then
								vim.fn.setreg("+", selection.value.id)
								vim.schedule(function()
									vim.notify("Copied subscription ID: " .. selection.value.id, vim.log.levels.INFO)
								end)
							end
						end)

						return true
					end,
				})
			:find()
		end)
		end)
end

-- Search Azure AD objects
function M.search_ad_objects(ad_objects)
	if not ad_objects then
		vim.schedule(function()
			vim.notify("No AD objects to search", vim.log.levels.WARN)
		end)
		return
	end

	-- Flatten all AD objects into a single list for searching
	local all_objects = {}
	
	if ad_objects.app_registrations then
		for _, app in ipairs(ad_objects.app_registrations) do
			table.insert(all_objects, app)
		end
	end
	
	if ad_objects.users then
		for _, user in ipairs(ad_objects.users) do
			table.insert(all_objects, user)
		end
	end
	
	if ad_objects.groups then
		for _, group in ipairs(ad_objects.groups) do
			table.insert(all_objects, group)
		end
	end
	
	if ad_objects.role_assignments then
		for _, role in ipairs(ad_objects.role_assignments) do
			table.insert(all_objects, role)
		end
	end

	if #all_objects == 0 then
		vim.schedule(function()
			vim.notify("No AD objects to search", vim.log.levels.WARN)
		end)
		return
	end

	local opts = {}

	pickers
		.new(opts, {
			prompt_title = "Azure AD Objects",
			finder = finders.new_table({
				results = all_objects,
				entry_maker = function(ad_object)
					local icon = config.get_icon(ad_object.type)
					local short_type = ad_object.type:gsub("Microsoft%.AzureAD/", "")
					local display_name = string.format(
						"%s%s (%s)",
						icon,
						ad_object.name,
						short_type
					)

					return {
						value = ad_object,
						display = display_name,
						ordinal = tostring(ad_object.name or "")
							.. " "
							.. tostring(ad_object.type or "")
							.. " "
							.. tostring(ad_object.properties.user_principal_name or "")
							.. " "
							.. tostring(ad_object.properties.app_id or ""),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = M.create_ad_object_previewer(),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						require("nimure").show_ad_object_details(selection.value)
					end
				end)

				-- Copy object ID
				map("i", "<C-y>", function()
					local selection = action_state.get_selected_entry()
					if selection then
						require("nimure").copy_resource_id(selection.value)
					end
				end)

				-- Copy object name
				map("i", "<C-n>", function()
					local selection = action_state.get_selected_entry()
					if selection then
						require("nimure").copy_resource_name(selection.value)
					end
				end)

				return true
			end,
		})
		:find()
end

-- Create AD object previewer
function M.create_ad_object_previewer()
	return previewers.new_buffer_previewer({
		title = "Azure AD Object Details",
		define_preview = function(self, entry, status)
			local ad_object = entry.value
			local lines = {}

			-- Safe string conversion helper
			local function safe_str(value)
				if value == nil then
					return "N/A"
				elseif type(value) == "string" then
					return value
				elseif type(value) == "boolean" then
					return tostring(value)
				elseif type(value) == "number" then
					return tostring(value)
				else
					return tostring(value)
				end
			end

			-- Basic info
			table.insert(lines, "Name: " .. safe_str(ad_object.name))
			table.insert(lines, "Type: " .. safe_str(ad_object.type:gsub("Microsoft%.AzureAD/", "")))
			table.insert(lines, "Location: " .. safe_str(ad_object.location))
			table.insert(lines, "")

			-- Object-specific details
			if ad_object.properties then
				if ad_object.type == "Microsoft.AzureAD/appRegistrations" then
					table.insert(lines, "Application ID: " .. safe_str(ad_object.properties.app_id))
					table.insert(lines, "Object ID: " .. safe_str(ad_object.properties.object_id))
					table.insert(lines, "Sign-in Audience: " .. safe_str(ad_object.properties.sign_in_audience))

				elseif ad_object.type == "Microsoft.AzureAD/users" then
					table.insert(lines, "User Principal Name: " .. safe_str(ad_object.properties.user_principal_name))
					table.insert(lines, "Object ID: " .. safe_str(ad_object.properties.object_id))
					table.insert(lines, "Email: " .. safe_str(ad_object.properties.mail))
					table.insert(lines, "Account Enabled: " .. safe_str(ad_object.properties.account_enabled))
					table.insert(lines, "Job Title: " .. safe_str(ad_object.properties.job_title))
					table.insert(lines, "Department: " .. safe_str(ad_object.properties.department))

				elseif ad_object.type == "Microsoft.AzureAD/groups" then
					table.insert(lines, "Object ID: " .. safe_str(ad_object.properties.object_id))
					table.insert(lines, "Mail: " .. safe_str(ad_object.properties.mail))
					table.insert(lines, "Security Enabled: " .. safe_str(ad_object.properties.security_enabled))
					table.insert(lines, "Mail Enabled: " .. safe_str(ad_object.properties.mail_enabled))
					table.insert(lines, "Description: " .. safe_str(ad_object.properties.description))

				elseif ad_object.type == "Microsoft.AzureAD/roleAssignments" then
					table.insert(lines, "Role: " .. safe_str(ad_object.properties.role_definition_name))
					table.insert(lines, "Principal: " .. safe_str(ad_object.properties.principal_name))
					table.insert(lines, "Principal Type: " .. safe_str(ad_object.properties.principal_type))
					table.insert(lines, "Scope: " .. safe_str(ad_object.properties.scope))
					table.insert(lines, "Created On: " .. safe_str(ad_object.properties.created_on))
				end
			end

			table.insert(lines, "")
			table.insert(lines, "Resource ID:")
			table.insert(lines, safe_str(ad_object.id))
			table.insert(lines, "")

			local txt = [[
Actions:
  <Enter> - Show detailed information
  <C-y>   - Copy object ID
  <C-n>   - Copy object name
]]

			for line in txt:gmatch("[^\r\n]+") do
				table.insert(lines, line)
			end

			-- Remove trailing newlines
			for i, line in ipairs(lines) do
				if line:sub(-1) == "\n" then
					lines[i] = line:sub(1, -2)
				end
			end

			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
		end,
	})
end

return M
