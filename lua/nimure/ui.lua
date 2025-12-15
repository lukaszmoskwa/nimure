-- UI module using nui.nvim

local NuiTree = require("nui.tree")
local NuiSplit = require("nui.split")
local NuiPopup = require("nui.popup")
local NuiLine = require("nui.line")
local NuiText = require("nui.text")

local config = require("nimure.config")
local utils = require("nimure.utils")

local M = {}

-- UI state
M.sidebar = nil
M.details_popup = nil
M.tree = nil

-- Create sidebar
function M.create_sidebar()
	if M.sidebar then
		return
	end

	local options = config.get()

	if options.sidebar.position == "float" then
		-- Create floating sidebar
		M.sidebar = NuiPopup({
			relative = options.sidebar.float.relative,
			position = {
				row = options.sidebar.float.row,
				col = options.sidebar.float.col,
			},
			size = {
				width = options.sidebar.float.width,
				height = options.sidebar.float.height,
			},
			border = {
				style = options.sidebar.border,
				text = {
					top = " Azure Resources ",
				},
			},
			buf_options = {
				modifiable = false,
				readonly = true,
				filetype = "nimure",
			},
			win_options = {
				number = false,
				relativenumber = false,
				wrap = false,
				cursorline = true,
			},
		})
	else
		-- Create split sidebar
		M.sidebar = NuiSplit({
			relative = "editor",
			position = options.sidebar.position,
			size = options.sidebar.width,
			buf_options = {
				modifiable = false,
				readonly = true,
				filetype = "nimure",
			},
			win_options = {
				number = false,
				relativenumber = false,
				wrap = false,
				cursorline = true,
			},
		})
	end

	M.sidebar:mount()

	-- Set up keymaps
	M.setup_sidebar_keymaps()

	-- Set up autocmds
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(M.sidebar.winid),
		callback = function()
			-- Use vim.schedule to defer execution out of fast event context
			vim.schedule(function()
				M.close_sidebar()
			end)
		end,
		once = true,
	})
end

-- Setup sidebar keymaps
function M.setup_sidebar_keymaps()
	if not M.sidebar then
		return
	end

	local options = config.get()
	local bufnr = M.sidebar.bufnr

	-- Close sidebar
	vim.keymap.set("n", options.keymaps.close, function()
		require("nimure").close_sidebar()
	end, { buffer = bufnr, desc = "Close Nimure sidebar" })

	-- Refresh resources
	vim.keymap.set("n", options.keymaps.refresh, function()
		require("nimure").refresh_resources()
	end, { buffer = bufnr, desc = "Refresh Azure resources" })

	-- Show details
	vim.keymap.set("n", options.keymaps.details, function()
		if M.tree then
			local ok, node = pcall(M.tree.get_node, M.tree)
			if ok and node and node.resource then
				require("nimure").show_resource_details(node.resource)
			end
		end
	end, { buffer = bufnr, desc = "Show resource details" })

	-- Show metrics
	vim.keymap.set("n", options.keymaps.metrics, function()
		if M.tree then
			local ok, node = pcall(M.tree.get_node, M.tree)
			if ok and node and node.resource then
				require("nimure").show_resource_metrics(node.resource)
			end
		end
	end, { buffer = bufnr, desc = "Show resource metrics" })

	-- Show resource costs (using 'C' when focused on a specific resource)
	vim.keymap.set("n", "R", function()
		if M.tree then
			local ok, node = pcall(M.tree.get_node, M.tree)
			if ok and node and node.resource then
				require("nimure").show_resource_costs(node.resource)
			end
		end
	end, { buffer = bufnr, desc = "Show resource costs" })

	-- Copy resource ID
	vim.keymap.set("n", options.keymaps.copy_id, function()
		if M.tree then
			local ok, node = pcall(M.tree.get_node, M.tree)
			if ok and node and node.resource then
				require("nimure").copy_resource_id(node.resource)
			end
		end
	end, { buffer = bufnr, desc = "Copy resource ID" })

	-- Copy resource name
	vim.keymap.set("n", options.keymaps.copy_name, function()
		if M.tree then
			local ok, node = pcall(M.tree.get_node, M.tree)
			if ok and node and node.resource then
				require("nimure").copy_resource_name(node.resource)
			end
		end
	end, { buffer = bufnr, desc = "Copy resource name" })

	-- Search resources
	vim.keymap.set("n", options.keymaps.search, function()
		require("nimure").search_resources()
	end, { buffer = bufnr, desc = "Search resources" })

	-- Show costs
	vim.keymap.set("n", options.keymaps.costs, function()
		require("nimure").show_subscription_costs()
	end, { buffer = bufnr, desc = "Show subscription costs" })

	-- Show detailed cost breakdown
	vim.keymap.set("n", options.keymaps.cost_breakdown, function()
		require("nimure").show_cost_breakdown()
	end, { buffer = bufnr, desc = "Show detailed cost breakdown" })

	-- Tree navigation
	vim.keymap.set("n", "<Space>", function()
		if M.tree then
			local ok, node = pcall(M.tree.get_node, M.tree)
			if ok and node and node.resource_group then
				if node:is_expanded() then
					node:collapse()
				else
					node:expand()
				end
				M.tree:render()
			end
		end
	end, { buffer = bufnr, desc = "Expand/collapse resource group" })

	-- Arrow key navigation
	vim.keymap.set("n", "<Right>", function()
		if M.tree then
			local ok, node = pcall(M.tree.get_node, M.tree)
			if ok and node and node.resource_group and not node:is_expanded() then
				node:expand()
				M.tree:render()
			end
		end
	end, { buffer = bufnr, desc = "Expand resource group" })

	vim.keymap.set("n", "<Left>", function()
		if M.tree then
			local ok, node = pcall(M.tree.get_node, M.tree)
			if ok and node and node.resource_group and node:is_expanded() then
				node:collapse()
				M.tree:render()
			end
		end
	end, { buffer = bufnr, desc = "Collapse resource group" })
end

-- Update sidebar with resources
function M.update_sidebar(resources)
	if not M.sidebar then
		return
	end

	-- Use vim.schedule to ensure we're not in a fast event context
	vim.schedule(function()
		local tree_nodes = M.build_tree_nodes(resources)

		M.tree = NuiTree({
			winid = M.sidebar.winid,
			nodes = tree_nodes,
			prepare_node = function(node)
				local line = NuiLine()

				-- Add expand/collapse indicator for resource groups
				if node.resource_group then
					local expanded = node:is_expanded()
					local indicator = expanded and "▼ " or "▶ "
					line:append(indicator, "Directory")
					line:append("📁 ", "Directory")
				else
					-- Add indent for resources under resource groups
					line:append("  ")
					-- Add icon for individual resources
					local icon = config.get_icon(node.resource and node.resource.type or "default")
					if icon ~= "" then
						line:append(icon)
					end
				end

				-- Add text
				line:append(node.text)

				-- Add type/location info if configured for resources
				local options = config.get()
				if node.resource then
					if options.ui.show_type then
						line:append(" (" .. utils.get_short_type(node.resource.type) .. ")", "Comment")
					end
					if options.ui.show_location then
						line:append(" [" .. node.resource.location .. "]", "Comment")
					end
				end

				return line
			end,
		})

		M.tree:render()

		-- Update buffer name safely
		pcall(vim.api.nvim_buf_set_name, M.sidebar.bufnr, "Nimure: Azure Resources (" .. #resources .. ")")
	end)
end

-- Build tree nodes from resources
function M.build_tree_nodes(resources)
	local nodes = {}
	local resource_groups = {}
	local options = config.get()

	-- Group resources by resource group
	for _, resource in ipairs(resources) do
		local rg = resource.resource_group
		if not resource_groups[rg] then
			resource_groups[rg] = {}
		end
		table.insert(resource_groups[rg], resource)
	end

	-- Create tree structure
	for rg_name, rg_resources in pairs(resource_groups) do
		-- Create child nodes for resources first
		local child_nodes = {}
		for _, resource in ipairs(rg_resources) do
			local resource_node = NuiTree.Node({
				text = resource.name,
				resource = resource,
			})
			table.insert(child_nodes, resource_node)
		end

		-- Create resource group node with children (expanded by default)
		local rg_node = NuiTree.Node({
			text = rg_name,
			resource_group = true,
		}, child_nodes)

		-- Expand the resource group by default
		rg_node:expand()

		table.insert(nodes, rg_node)
	end

	return nodes
end

-- Show loading state
function M.show_loading()
	if not M.sidebar then
		return
	end

	vim.schedule(function()
		local loading_nodes = {
			NuiTree.Node({ text = "Loading Azure resources..." }),
		}

		M.tree = NuiTree({
			winid = M.sidebar.winid,
			nodes = loading_nodes,
		})

		M.tree:render()
	end)
end

-- Show error state
function M.show_error(error)
	if not M.sidebar then
		return
	end

	vim.schedule(function()
		local error_nodes = {
			NuiTree.Node({ text = "❌ Error loading resources" }),
			NuiTree.Node({ text = utils.wrap_text(error, 35) }),
			NuiTree.Node({ text = "" }),
			NuiTree.Node({ text = "Press 'r' to retry" }),
		}

		M.tree = NuiTree({
			winid = M.sidebar.winid,
			nodes = error_nodes,
		})

		M.tree:render()
	end)
end

-- Show resource details in a popup
function M.show_resource_details(resource, details)
	if M.details_popup then
		M.details_popup:unmount()
	end

	local content = M.format_resource_details(resource, details)

	M.details_popup = NuiPopup({
		enter = true,
		focusable = true,
		border = {
			style = config.get().sidebar.border,
			text = {
				top = " Resource Details ",
			},
		},
		position = "50%",
		size = {
			width = 80,
			height = 60,
		},
		relative = "editor",
		buf_options = {
			-- Don't set modifiable/readonly here, do it after setting content
		},
		win_options = {
			wrap = true,
		},
	})

	M.details_popup:mount()

	-- Set content
	vim.api.nvim_buf_set_lines(M.details_popup.bufnr, 0, -1, false, content)

	-- Make buffer readonly after setting content
	vim.api.nvim_buf_set_option(M.details_popup.bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(M.details_popup.bufnr, "readonly", true)

	-- Close with q or Escape
	local close_keys = { "q", "<Esc>" }
	for _, key in ipairs(close_keys) do
		vim.keymap.set("n", key, function()
			M.details_popup:unmount()
			M.details_popup = nil
		end, { buffer = M.details_popup.bufnr })
	end
end

-- Show resource metrics in a popup
function M.show_resource_metrics(resource, metrics)
	if M.details_popup then
		M.details_popup:unmount()
	end

	local content = M.format_resource_metrics(resource, metrics)

	M.details_popup = NuiPopup({
		enter = true,
		focusable = true,
		border = {
			style = config.get().sidebar.border,
			text = {
				top = " Resource Metrics ",
			},
		},
		position = "50%",
		size = {
			width = 60,
			height = 30,
		},
		relative = "editor",
		buf_options = {
			-- Don't set modifiable/readonly here, do it after setting content
		},
	})

	M.details_popup:mount()

	-- Set content
	vim.api.nvim_buf_set_lines(M.details_popup.bufnr, 0, -1, false, content)

	-- Make buffer readonly after setting content
	vim.api.nvim_buf_set_option(M.details_popup.bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(M.details_popup.bufnr, "readonly", true)

	-- Close with q or Escape
	local close_keys = { "q", "<Esc>" }
	for _, key in ipairs(close_keys) do
		vim.keymap.set("n", key, function()
			M.details_popup:unmount()
			M.details_popup = nil
		end, { buffer = M.details_popup.bufnr })
	end
end

-- Format resource details for display
function M.format_resource_details(resource, details)
	local lines = {}

	table.insert(lines, "Name: " .. resource.name)
	table.insert(lines, "Type: " .. resource.type)
	table.insert(lines, "Location: " .. resource.location)
	table.insert(lines, "Resource Group: " .. resource.resource_group)
	table.insert(lines, "")
	table.insert(lines, "Resource ID:")
	table.insert(lines, resource.id)
	table.insert(lines, "")

	if resource.tags and vim.tbl_count(resource.tags) > 0 then
		table.insert(lines, "Tags:")
		for key, value in pairs(resource.tags) do
			table.insert(lines, "  " .. key .. ": " .. value)
		end
		table.insert(lines, "")
	end

	if details.properties then
		table.insert(lines, "Properties:")
		local props = vim.inspect(details.properties, { indent = "  " })
		for line in props:gmatch("[^\r\n]+") do
			table.insert(lines, line)
		end
	end

	return lines
end

-- Format resource metrics for display
function M.format_resource_metrics(resource, metrics)
	local lines = {}

	table.insert(lines, "Resource: " .. resource.name)
	table.insert(lines, "Type: " .. utils.get_short_type(resource.type))
	table.insert(lines, "")
	table.insert(lines, "Basic Information:")
	table.insert(lines, "  Location: " .. metrics.location)
	table.insert(lines, "  Status: " .. metrics.status)
	table.insert(lines, "  Tags Count: " .. metrics.tags_count)
	table.insert(lines, "")
	table.insert(lines, "Note: Detailed metrics require additional")
	table.insert(lines, "Azure Monitor permissions and configuration.")

	return lines
end

-- Show cost overview popup
function M.show_cost_overview(cost_data)
	if M.details_popup then
		M.details_popup:unmount()
	end

	local costs = require("nimure.costs")
	local content = {}

	-- Add summary
	local summary = costs.format_cost_summary(cost_data)
	for _, line in ipairs(summary) do
		table.insert(content, line)
	end

	-- Add trend indicator
	local trend_icon, trend_text = costs.get_cost_trend(cost_data.daily_costs)
	table.insert(content, "")
	table.insert(content, string.format("%s Trend: %s", trend_icon, trend_text))
	table.insert(content, "")

	-- Add daily chart if enabled
	local config_opts = config.get()
	if config_opts.costs.show_daily_chart and #cost_data.daily_costs > 0 then
		table.insert(content, "")
		local daily_chart = costs.generate_daily_chart(cost_data.daily_costs, config_opts.costs.chart_height)
		for _, line in ipairs(daily_chart) do
			table.insert(content, line)
		end
	end

	M.details_popup = NuiPopup({
		enter = true,
		focusable = true,
		border = {
			style = config.get().sidebar.border,
			text = {
				top = " 💰 Azure Cost Overview ",
			},
		},
		position = "50%",
		size = {
			width = 80,
			height = math.min(40, #content + 5),
		},
		relative = "editor",
		buf_options = {},
		win_options = {
			wrap = false,
		},
	})

	M.details_popup:mount()

	-- Set content
	vim.api.nvim_buf_set_lines(M.details_popup.bufnr, 0, -1, false, content)

	-- Make buffer readonly after setting content
	vim.api.nvim_buf_set_option(M.details_popup.bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(M.details_popup.bufnr, "readonly", true)

	-- Close with q or Escape
	local close_keys = { "q", "<Esc>" }
	for _, key in ipairs(close_keys) do
		vim.keymap.set("n", key, function()
			M.details_popup:unmount()
			M.details_popup = nil
		end, { buffer = M.details_popup.bufnr })
	end
end

-- Show detailed cost breakdown popup
function M.show_cost_breakdown(cost_data)
	if M.details_popup then
		M.details_popup:unmount()
	end

	local costs = require("nimure.costs")
	local content = {}

	-- Add summary header
	local costs = require("nimure.costs")
	local currency_symbol = costs.get_currency_symbol(cost_data.currency)
	table.insert(content, string.format("💰 Detailed Cost Breakdown"))
	table.insert(content, string.rep("═", 60))
	table.insert(content, "")
	table.insert(
		content,
		string.format(
			"Total: %s%.2f %s (%s to %s)",
			currency_symbol,
			cost_data.total_cost,
			cost_data.currency,
			cost_data.period.start_date,
			cost_data.period.end_date
		)
	)
	table.insert(content, "")

	-- Add service breakdown chart
	if config.get().costs.show_service_breakdown and #cost_data.services > 0 then
		local service_chart = costs.generate_service_chart(cost_data.services, 15)
		for _, line in ipairs(service_chart) do
			table.insert(content, line)
		end
		table.insert(content, "")
	end

	-- Add daily costs chart
	if config.get().costs.show_daily_chart and #cost_data.daily_costs > 0 then
		local daily_chart = costs.generate_daily_chart(cost_data.daily_costs, config.get().costs.chart_height)
		for _, line in ipairs(daily_chart) do
			table.insert(content, line)
		end
	end

	M.details_popup = NuiPopup({
		enter = true,
		focusable = true,
		border = {
			style = config.get().sidebar.border,
			text = {
				top = " 📊 Cost Breakdown ",
			},
		},
		position = "50%",
		size = {
			width = 85,
			height = math.min(45, #content + 5),
		},
		relative = "editor",
		buf_options = {},
		win_options = {
			wrap = false,
		},
	})

	M.details_popup:mount()

	-- Set content
	vim.api.nvim_buf_set_lines(M.details_popup.bufnr, 0, -1, false, content)

	-- Make buffer readonly after setting content
	vim.api.nvim_buf_set_option(M.details_popup.bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(M.details_popup.bufnr, "readonly", true)

	-- Close with q or Escape
	local close_keys = { "q", "<Esc>" }
	for _, key in ipairs(close_keys) do
		vim.keymap.set("n", key, function()
			M.details_popup:unmount()
			M.details_popup = nil
		end, { buffer = M.details_popup.bufnr })
	end
end

-- Show resource-specific cost details
function M.show_resource_cost_details(resource_costs)
	if M.details_popup then
		M.details_popup:unmount()
	end

	local costs = require("nimure.costs")
	local content = costs.format_resource_costs(resource_costs)

	M.details_popup = NuiPopup({
		enter = true,
		focusable = true,
		border = {
			style = config.get().sidebar.border,
			text = {
				top = " 💰 Resource Costs ",
			},
		},
		position = "50%",
		size = {
			width = 70,
			height = math.min(30, #content + 5),
		},
		relative = "editor",
		buf_options = {},
		win_options = {
			wrap = true,
		},
	})

	M.details_popup:mount()

	-- Set content
	vim.api.nvim_buf_set_lines(M.details_popup.bufnr, 0, -1, false, content)

	-- Make buffer readonly after setting content
	vim.api.nvim_buf_set_option(M.details_popup.bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(M.details_popup.bufnr, "readonly", true)

	-- Close with q or Escape
	local close_keys = { "q", "<Esc>" }
	for _, key in ipairs(close_keys) do
		vim.keymap.set("n", key, function()
			M.details_popup:unmount()
			M.details_popup = nil
		end, { buffer = M.details_popup.bufnr })
	end
end

-- Close sidebar
function M.close_sidebar()
	-- Ensure we're not in a fast event context
	vim.schedule(function()
		if M.sidebar then
			pcall(M.sidebar.unmount, M.sidebar)
			M.sidebar = nil
			M.tree = nil
		end

		if M.details_popup then
			pcall(M.details_popup.unmount, M.details_popup)
			M.details_popup = nil
		end
	end)
end

return M
