-- Utility functions for Nimure

local M = {}

-- Get short type name from full Azure resource type
function M.get_short_type(resource_type)
	local parts = vim.split(resource_type, "/")
	if #parts >= 2 then
		return parts[#parts] -- Return the last part (e.g., "virtualMachines" from "Microsoft.Compute/virtualMachines")
	end
	return resource_type
end

-- Wrap text to fit within a specified width
function M.wrap_text(text, width)
	local lines = {}
	local current_line = ""

	for word in text:gmatch("%S+") do
		if #current_line + #word + 1 <= width then
			if current_line == "" then
				current_line = word
			else
				current_line = current_line .. " " .. word
			end
		else
			if current_line ~= "" then
				table.insert(lines, current_line)
			end
			current_line = word
		end
	end

	if current_line ~= "" then
		table.insert(lines, current_line)
	end

	return table.concat(lines, "\n")
end

-- Truncate text to specified length with ellipsis
function M.truncate(text, length)
	if #text <= length then
		return text
	end
	return text:sub(1, length - 3) .. "..."
end

-- Deep copy a table
function M.deep_copy(original)
	local copy = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = M.deep_copy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

-- Check if a table is empty
function M.is_empty(table)
	return next(table) == nil
end

-- Get Azure resource type category for grouping
function M.get_type_category(resource_type)
	local categories = {
		compute = {
			"Microsoft.Compute/virtualMachines",
			"Microsoft.Compute/virtualMachineScaleSets",
			"Microsoft.Compute/disks",
			"Microsoft.Compute/snapshots",
		},
		storage = {
			"Microsoft.Storage/storageAccounts",
		},
		networking = {
			"Microsoft.Network/virtualNetworks",
			"Microsoft.Network/publicIPAddresses",
			"Microsoft.Network/networkSecurityGroups",
			"Microsoft.Network/loadBalancers",
			"Microsoft.Network/applicationGateways",
			"Microsoft.Network/networkInterfaces",
		},
		web = {
			"Microsoft.Web/sites",
			"Microsoft.Web/serverfarms",
		},
		database = {
			"Microsoft.Sql/servers",
			"Microsoft.DocumentDB/databaseAccounts",
			"Microsoft.DBforMySQL/servers",
			"Microsoft.DBforPostgreSQL/servers",
		},
		security = {
			"Microsoft.KeyVault/vaults",
		},
		container = {
			"Microsoft.ContainerRegistry/registries",
			"Microsoft.ContainerInstance/containerGroups",
			"Microsoft.ContainerService/managedClusters",
		},
	}

	for category, types in pairs(categories) do
		for _, type in ipairs(types) do
			if type == resource_type then
				return category
			end
		end
	end

	return "other"
end

-- Format bytes to human readable format
function M.format_bytes(bytes)
	local units = { "B", "KB", "MB", "GB", "TB" }
	local unit_index = 1
	local size = bytes

	while size >= 1024 and unit_index < #units do
		size = size / 1024
		unit_index = unit_index + 1
	end

	return string.format("%.1f %s", size, units[unit_index])
end

-- Extract subscription ID from Azure resource ID
function M.extract_subscription_id(resource_id)
	return resource_id:match("/subscriptions/([^/]+)")
end

-- Validate Azure resource ID format
function M.is_valid_resource_id(resource_id)
	return resource_id:match("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/[^/]+/[^/]+/[^/]+") ~= nil
end

-- Convert Azure location to display name
function M.format_location(location)
	local location_map = {
		["eastus"] = "East US",
		["eastus2"] = "East US 2",
		["westus"] = "West US",
		["westus2"] = "West US 2",
		["centralus"] = "Central US",
		["northcentralus"] = "North Central US",
		["southcentralus"] = "South Central US",
		["westcentralus"] = "West Central US",
		["canadacentral"] = "Canada Central",
		["canadaeast"] = "Canada East",
		["brazilsouth"] = "Brazil South",
		["northeurope"] = "North Europe",
		["westeurope"] = "West Europe",
		["uksouth"] = "UK South",
		["ukwest"] = "UK West",
		["francecentral"] = "France Central",
		["francesouth"] = "France South",
		["germanywestcentral"] = "Germany West Central",
		["norwayeast"] = "Norway East",
		["switzerlandnorth"] = "Switzerland North",
		["eastasia"] = "East Asia",
		["southeastasia"] = "Southeast Asia",
		["japaneast"] = "Japan East",
		["japanwest"] = "Japan West",
		["australiaeast"] = "Australia East",
		["australiasoutheast"] = "Australia Southeast",
		["centralindia"] = "Central India",
		["southindia"] = "South India",
		["westindia"] = "West India",
		["koreacentral"] = "Korea Central",
		["koreasouth"] = "Korea South",
	}

	return location_map[location] or location
end

return M
