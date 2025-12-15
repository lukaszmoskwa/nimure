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

return M
