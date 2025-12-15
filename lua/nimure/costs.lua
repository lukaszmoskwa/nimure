-- Cost tracking and visualization module

local azure = require("nimure.azure")
local config = require("nimure.config")

local M = {}

-- Generate ASCII chart for daily costs
function M.generate_daily_chart(daily_costs, height)
	if not daily_costs or #daily_costs == 0 then
		return { "No cost data available" }
	end

	height = height or 10
	local chart_lines = {}

	-- Find max cost for scaling
	local max_cost = 0
	for _, day in ipairs(daily_costs) do
		if day.cost > max_cost then
			max_cost = day.cost
		end
	end

	if max_cost == 0 then
		return { "No costs recorded for this period" }
	end

	-- Create chart header
	table.insert(chart_lines, string.format("Daily Costs (Max: %.2f)", max_cost))
	table.insert(chart_lines, string.rep("─", 60))

	-- Generate bars for each day
	for i, day in ipairs(daily_costs) do
		local bar_length = math.floor((day.cost / max_cost) * 50)
		local bar = string.rep("█", bar_length)
		local date_short = day.date:sub(6) -- Remove year, show MM-DD

		table.insert(
			chart_lines,
			string.format("%s │%s %.2f", date_short, bar .. string.rep(" ", 50 - bar_length), day.cost)
		)

		-- Limit number of days shown to avoid too long charts
		if i >= 20 then
			table.insert(chart_lines, "... (showing first 20 days)")
			break
		end
	end

	table.insert(chart_lines, string.rep("─", 60))

	return chart_lines
end

-- Generate service breakdown chart
function M.generate_service_chart(services, max_services)
	if not services or #services == 0 then
		return { "No service cost data available" }
	end

	max_services = max_services or 10
	local chart_lines = {}
	local total_cost = 0

	-- Calculate total cost
	for _, service in ipairs(services) do
		total_cost = total_cost + service.cost
	end

	if total_cost == 0 then
		return { "No service costs recorded" }
	end

	-- Create chart header
	table.insert(chart_lines, string.format("Service Breakdown (Total: %.2f %s)", total_cost, services[1].currency))
	table.insert(chart_lines, string.rep("─", 70))

	-- Show top services
	for i = 1, math.min(#services, max_services) do
		local service = services[i]
		local percentage = (service.cost / total_cost) * 100
		local bar_length = math.floor(percentage / 2) -- Scale to fit in 50 chars
		local bar = string.rep("█", bar_length)

		-- Truncate service name if too long
		local service_name = service.name
		if #service_name > 25 then
			service_name = service_name:sub(1, 22) .. "..."
		end

		table.insert(
			chart_lines,
			string.format(
				"%-25s │%s %5.1f%% (%.2f)",
				service_name,
				bar .. string.rep(" ", 25 - bar_length),
				percentage,
				service.cost
			)
		)
	end

	if #services > max_services then
		table.insert(chart_lines, string.format("... and %d more services", #services - max_services))
	end

	table.insert(chart_lines, string.rep("─", 70))

	return chart_lines
end

-- Format cost summary
function M.format_cost_summary(cost_data)
	if not cost_data then
		return { "No cost data available" }
	end

	local summary_lines = {}
	local currency_symbol = M.get_currency_symbol(cost_data.currency)

	table.insert(summary_lines, string.format("📊 Azure Cost Summary"))
	table.insert(summary_lines, string.rep("═", 50))
	table.insert(summary_lines, "")
	table.insert(
		summary_lines,
		string.format("💰 Total Cost: %s%.2f %s", currency_symbol, cost_data.total_cost, cost_data.currency)
	)
	table.insert(
		summary_lines,
		string.format("📅 Period: %s to %s", cost_data.period.start_date, cost_data.period.end_date)
	)
	table.insert(summary_lines, string.format("🔢 Services: %d", #cost_data.services))
	table.insert(summary_lines, "")

	-- Calculate daily average
	if #cost_data.daily_costs > 0 then
		local avg_daily = cost_data.total_cost / #cost_data.daily_costs
		table.insert(
			summary_lines,
			string.format("📈 Daily Average: %s%.2f %s", currency_symbol, avg_daily, cost_data.currency)
		)
	end

	-- Show top 3 services
	if #cost_data.services > 0 then
		table.insert(summary_lines, "")
		table.insert(summary_lines, "🏆 Top Services:")
		for i = 1, math.min(3, #cost_data.services) do
			local service = cost_data.services[i]
			local percentage = (service.cost / cost_data.total_cost) * 100
			table.insert(
				summary_lines,
				string.format("   %d. %s: %s%.2f (%.1f%%)", i, service.name, currency_symbol, service.cost, percentage)
			)
		end
	end

	return summary_lines
end

-- Format resource-specific cost info
function M.format_resource_costs(resource_costs)
	if not resource_costs then
		return { "No cost data available for this resource" }
	end

	local lines = {}
	local currency_symbol = M.get_currency_symbol(resource_costs.currency)

	table.insert(lines, string.format("💰 Cost Analysis: %s", resource_costs.resource_name))
	table.insert(lines, string.rep("═", 50))
	table.insert(lines, "")
	table.insert(lines, string.format("Resource Type: %s", resource_costs.resource_type))
	table.insert(
		lines,
		string.format("Total Cost: %s%.2f %s", currency_symbol, resource_costs.total_cost, resource_costs.currency)
	)
	table.insert(lines, string.format("Usage Records: %d", #resource_costs.usage_items))
	table.insert(lines, "")

	-- Show note if available
	if resource_costs.note then
		table.insert(lines, "ℹ️  " .. resource_costs.note)
		table.insert(lines, "")
	end

	if resource_costs.total_cost == 0 then
		if not resource_costs.note then
			table.insert(lines, "ℹ️  No costs recorded for this resource in the selected period.")
			table.insert(lines, "   This might mean:")
			table.insert(lines, "   • Resource was not active during this period")
			table.insert(lines, "   • Costs are included in a bundle/plan")
			table.insert(lines, "   • Resource is in a free tier")
		end
	else
		-- Show some usage details if available
		if #resource_costs.usage_items > 0 then
			table.insert(lines, "📈 Recent Usage:")
			for i = 1, math.min(5, #resource_costs.usage_items) do
				local usage = resource_costs.usage_items[i]
				local cost = tonumber(usage.pretaxCost) or tonumber(usage.cost) or 0
				local date = usage.date or usage.usageStart or "N/A"
				if date ~= "N/A" then
					date = date:sub(1, 10) -- Extract date part
				end
				table.insert(lines, string.format("   %s: %s%.2f", date, currency_symbol, cost))
			end
		end
	end

	return lines
end

-- Create cost trend indicator
function M.get_cost_trend(daily_costs)
	if not daily_costs or #daily_costs < 2 then
		return "📊", "Insufficient data"
	end

	local recent_days = math.min(7, #daily_costs)
	local recent_avg = 0
	local older_avg = 0

	-- Calculate recent average (last 7 days or less)
	for i = #daily_costs - recent_days + 1, #daily_costs do
		recent_avg = recent_avg + daily_costs[i].cost
	end
	recent_avg = recent_avg / recent_days

	-- Calculate older average (7 days before that, or what's available)
	local older_start = math.max(1, #daily_costs - recent_days * 2 + 1)
	local older_end = #daily_costs - recent_days
	local older_count = older_end - older_start + 1

	if older_count > 0 then
		for i = older_start, older_end do
			older_avg = older_avg + daily_costs[i].cost
		end
		older_avg = older_avg / older_count

		local trend_percent = ((recent_avg - older_avg) / older_avg) * 100

		if trend_percent > 10 then
			return "📈", string.format("Trending up (%.1f%%)", trend_percent)
		elseif trend_percent < -10 then
			return "📉", string.format("Trending down (%.1f%%)", -trend_percent)
		else
			return "📊", "Stable"
		end
	end

	return "📊", "Stable"
end

-- Get currency symbol for display
function M.get_currency_symbol(currency_code)
	local currency_symbols = {
		USD = "$",
		EUR = "€",
		GBP = "£",
		JPY = "¥",
		CAD = "C$",
		AUD = "A$",
		CHF = "CHF ",
		SEK = "kr ",
		NOK = "kr ",
		DKK = "kr ",
		PLN = "zł ",
		CZK = "Kč ",
		HUF = "Ft ",
		BRL = "R$ ",
		INR = "₹",
		CNY = "¥",
		KRW = "₩",
		SGD = "S$",
		HKD = "HK$",
		NZD = "NZ$",
		ZAR = "R ",
		TRY = "₺",
		RUB = "₽",
	}

	return currency_symbols[currency_code] or (currency_code and (currency_code .. " ") or "$")
end

return M
