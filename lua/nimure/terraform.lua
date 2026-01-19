-- Terraform integration module for Nimure
-- Generates HCL import blocks for Azure resources

local Job = require("plenary.job")
local config = require("nimure.config")

local M = {}

-- Azure to Terraform resource type mapping
M.resource_mapping = {
	-- Storage
	["Microsoft.Storage/storageAccounts"] = "azurerm_storage_account",
	["Microsoft.Storage/storageAccounts/blobServices"] = "azurerm_storage_account",
	["Microsoft.Storage/storageAccounts/blobServices/containers"] = "azurerm_storage_container",
	["Microsoft.Storage/storageAccounts/fileServices/shares"] = "azurerm_storage_share",
	["Microsoft.Storage/storageAccounts/queueServices/queues"] = "azurerm_storage_queue",
	["Microsoft.Storage/storageAccounts/tableServices/tables"] = "azurerm_storage_table",

	-- Network
	["Microsoft.Network/virtualNetworks"] = "azurerm_virtual_network",
	["Microsoft.Network/virtualNetworks/subnets"] = "azurerm_subnet",
	["Microsoft.Network/publicIPAddresses"] = "azurerm_public_ip",
	["Microsoft.Network/networkInterfaces"] = "azurerm_network_interface",
	["Microsoft.Network/networkSecurityGroups"] = "azurerm_network_security_group",
	["Microsoft.Network/networkSecurityGroups/securityRules"] = "azurerm_network_security_rule",
	["Microsoft.Network/loadBalancers"] = "azurerm_lb",
	["Microsoft.Network/loadBalancers/backendAddressPools"] = "azurerm_lb_backend_address_pool",
	["Microsoft.Network/loadBalancers/frontendIPConfigurations"] = "azurerm_lb_frontend_ip_configuration",
	["Microsoft.Network/loadBalancers/probes"] = "azurerm_lb_probe",
	["Microsoft.Network/loadBalancers/loadBalancingRules"] = "azurerm_lb_rule",
	["Microsoft.Network/applicationGateways"] = "azurerm_application_gateway",
	["Microsoft.Network/routeTables"] = "azurerm_route_table",
	["Microsoft.Network/routeTables/routes"] = "azurerm_route",
	["Microsoft.Network/natGateways"] = "azurerm_nat_gateway",
	["Microsoft.Network/privateDnsZones"] = "azurerm_private_dns_zone",
	["Microsoft.Network/privateEndpoints"] = "azurerm_private_endpoint",
	["Microsoft.Network/bastionHosts"] = "azurerm_bastion_host",
	["Microsoft.Network/vpnGateways"] = "azurerm_vpn_gateway",
	["Microsoft.Network/expressRouteCircuits"] = "azurerm_express_route_circuit",
	["Microsoft.Network/firewalls"] = "azurerm_firewall",
	["Microsoft.Network/firewallPolicies"] = "azurerm_firewall_policy",
	["Microsoft.Network/applicationSecurityGroups"] = "azurerm_application_security_group",
	["Microsoft.Network/ddosProtectionPlans"] = "azurerm_network_ddos_protection_plan",
	["Microsoft.Network/dnsZones"] = "azurerm_dns_zone",

	-- Compute
	["Microsoft.Compute/virtualMachines"] = "azurerm_linux_virtual_machine",
	["Microsoft.Compute/virtualMachineScaleSets"] = "azurerm_linux_virtual_machine_scale_set",
	["Microsoft.Compute/disks"] = "azurerm_managed_disk",
	["Microsoft.Compute/snapshots"] = "azurerm_snapshot",
	["Microsoft.Compute/images"] = "azurerm_image",
	["Microsoft.Compute/availabilitySets"] = "azurerm_availability_set",
	["Microsoft.Compute/proximityPlacementGroups"] = "azurerm_proximity_placement_group",
	["Microsoft.Compute/diskEncryptionSets"] = "azurerm_disk_encryption_set",

	-- Database
	["Microsoft.DBforPostgreSQL/flexibleServers"] = "azurerm_postgresql_flexible_server",
	["Microsoft.DBforPostgreSQL/servers"] = "azurerm_postgresql_server",
	["Microsoft.DBforPostgreSQL/flexibleServers/databases"] = "azurerm_postgresql_flexible_server_database",
	["Microsoft.DBforMySQL/flexibleServers"] = "azurerm_mysql_flexible_server",
	["Microsoft.DBforMySQL/servers"] = "azurerm_mysql_server",
	["Microsoft.DBforMariaDB/servers"] = "azurerm_mariadb_server",
	["Microsoft.Sql/servers"] = "azurerm_mssql_server",
	["Microsoft.Sql/servers/databases"] = "azurerm_mssql_database",
	["Microsoft.Sql/servers/elasticPools"] = "azurerm_mssql_elasticpool",
	["Microsoft.Sql/managedInstances"] = "azurerm_mssql_managed_instance",
	["Microsoft.DocumentDB/databaseAccounts"] = "azurerm_cosmosdb_account",
	["Microsoft.Cache/Redis"] = "azurerm_redis_cache",

	-- Resources
	["Microsoft.Resources/resourceGroups"] = "azurerm_resource_group",

	-- Container
	["Microsoft.ContainerService/managedClusters"] = "azurerm_kubernetes_cluster",
	["Microsoft.ContainerRegistry/registries"] = "azurerm_container_registry",
	["Microsoft.ContainerInstance/containerGroups"] = "azurerm_container_group",

	-- Web / App Service
	["Microsoft.Web/sites"] = "azurerm_linux_web_app",
	["Microsoft.Web/serverfarms"] = "azurerm_service_plan",
	["Microsoft.Web/sites/slots"] = "azurerm_linux_web_app_slot",
	["Microsoft.Web/staticSites"] = "azurerm_static_site",
	["Microsoft.Web/certificates"] = "azurerm_app_service_certificate",

	-- Key Vault
	["Microsoft.KeyVault/vaults"] = "azurerm_key_vault",
	["Microsoft.KeyVault/vaults/secrets"] = "azurerm_key_vault_secret",
	["Microsoft.KeyVault/vaults/keys"] = "azurerm_key_vault_key",
	["Microsoft.KeyVault/vaults/certificates"] = "azurerm_key_vault_certificate",
	["Microsoft.KeyVault/managedHSMs"] = "azurerm_key_vault_managed_hardware_security_module",

	-- Identity
	["Microsoft.ManagedIdentity/userAssignedIdentities"] = "azurerm_user_assigned_identity",

	-- Monitor / Log Analytics
	["Microsoft.OperationalInsights/workspaces"] = "azurerm_log_analytics_workspace",
	["Microsoft.Insights/components"] = "azurerm_application_insights",
	["Microsoft.Insights/actionGroups"] = "azurerm_monitor_action_group",
	["Microsoft.Insights/metricAlerts"] = "azurerm_monitor_metric_alert",
	["Microsoft.Insights/activityLogAlerts"] = "azurerm_monitor_activity_log_alert",
	["Microsoft.Insights/diagnosticSettings"] = "azurerm_monitor_diagnostic_setting",

	-- Event / Messaging
	["Microsoft.EventHub/namespaces"] = "azurerm_eventhub_namespace",
	["Microsoft.EventHub/namespaces/eventhubs"] = "azurerm_eventhub",
	["Microsoft.ServiceBus/namespaces"] = "azurerm_servicebus_namespace",
	["Microsoft.ServiceBus/namespaces/queues"] = "azurerm_servicebus_queue",
	["Microsoft.ServiceBus/namespaces/topics"] = "azurerm_servicebus_topic",
	["Microsoft.EventGrid/topics"] = "azurerm_eventgrid_topic",
	["Microsoft.EventGrid/domains"] = "azurerm_eventgrid_domain",

	-- Logic / Functions
	["Microsoft.Logic/workflows"] = "azurerm_logic_app_workflow",
	["Microsoft.Web/sites/functions"] = "azurerm_function_app_function",

	-- API Management
	["Microsoft.ApiManagement/service"] = "azurerm_api_management",

	-- CDN / Front Door
	["Microsoft.Cdn/profiles"] = "azurerm_cdn_profile",
	["Microsoft.Cdn/profiles/endpoints"] = "azurerm_cdn_endpoint",
	["Microsoft.Network/frontDoors"] = "azurerm_frontdoor",

	-- Recovery Services
	["Microsoft.RecoveryServices/vaults"] = "azurerm_recovery_services_vault",

	-- Automation
	["Microsoft.Automation/automationAccounts"] = "azurerm_automation_account",

	-- Data Factory
	["Microsoft.DataFactory/factories"] = "azurerm_data_factory",

	-- Synapse
	["Microsoft.Synapse/workspaces"] = "azurerm_synapse_workspace",

	-- Databricks
	["Microsoft.Databricks/workspaces"] = "azurerm_databricks_workspace",

	-- Search
	["Microsoft.Search/searchServices"] = "azurerm_search_service",

	-- Cognitive Services
	["Microsoft.CognitiveServices/accounts"] = "azurerm_cognitive_account",

	-- Machine Learning
	["Microsoft.MachineLearningServices/workspaces"] = "azurerm_machine_learning_workspace",

	-- SignalR
	["Microsoft.SignalRService/SignalR"] = "azurerm_signalr_service",

	-- Notification Hubs
	["Microsoft.NotificationHubs/namespaces"] = "azurerm_notification_hub_namespace",
	["Microsoft.NotificationHubs/namespaces/notificationHubs"] = "azurerm_notification_hub",

	-- Policy
	["Microsoft.Authorization/policyDefinitions"] = "azurerm_policy_definition",
	["Microsoft.Authorization/policyAssignments"] = "azurerm_policy_assignment",

	-- Role Assignments
	["Microsoft.Authorization/roleAssignments"] = "azurerm_role_assignment",
	["Microsoft.Authorization/roleDefinitions"] = "azurerm_role_definition",
}

-- Module state
M.state = {
	terraform_available = nil,
	terraform_version = nil,
}

-- Check if Terraform CLI is available
function M.check_terraform_cli()
	if M.state.terraform_available ~= nil then
		return M.state.terraform_available
	end

	local result = vim.fn.executable("terraform")
	M.state.terraform_available = result == 1
	return M.state.terraform_available
end

-- Get Terraform version (async)
function M.get_terraform_version(callback)
	if M.state.terraform_version then
		if callback then
			callback(M.state.terraform_version, nil)
		end
		return
	end

	local stdout = {}
	local stderr = {}

	Job:new({
		command = "terraform",
		args = { "version", "-json" },
		on_stdout = function(_, line)
			table.insert(stdout, line)
		end,
		on_stderr = function(_, line)
			table.insert(stderr, line)
		end,
		on_exit = function(_, return_val)
			if return_val ~= 0 then
				if callback then
					callback(nil, "Failed to get Terraform version")
				end
				return
			end

			local json_str = table.concat(stdout, "\n")
			local ok, data = pcall(vim.json.decode, json_str)

			if ok and data and data.terraform_version then
				M.state.terraform_version = data.terraform_version
				if callback then
					callback(data.terraform_version, nil)
				end
			else
				if callback then
					callback(nil, "Failed to parse Terraform version")
				end
			end
		end,
	}):start()
end

-- Map Azure resource type to Terraform resource type
function M.map_azure_to_terraform(azure_type)
	return M.resource_mapping[azure_type]
end

-- Sanitize resource name for Terraform (convert to valid identifier)
function M.sanitize_resource_name(name)
	-- Replace hyphens and other invalid chars with underscores
	local sanitized = name:gsub("[^%w_]", "_")
	-- Ensure it starts with a letter or underscore
	if sanitized:match("^%d") then
		sanitized = "_" .. sanitized
	end
	return sanitized
end

-- Clean up output directory (remove all files)
function M.clean_output_directory()
	local opts = config.get()
	local output_dir = opts.terraform.output_dir

	if vim.fn.isdirectory(output_dir) == 1 then
		-- Get all files in the directory
		local files = vim.fn.glob(output_dir .. "/*", false, true)
		for _, file in ipairs(files) do
			-- Remove files and directories
			if vim.fn.isdirectory(file) == 1 then
				vim.fn.delete(file, "rf")
			else
				vim.fn.delete(file)
			end
		end
	end
end

-- Create output directory if it doesn't exist
function M.create_output_directory()
	local opts = config.get()
	local output_dir = opts.terraform.output_dir

	if vim.fn.isdirectory(output_dir) == 0 then
		local ok = vim.fn.mkdir(output_dir, "p")
		if ok == 0 then
			return nil, "Failed to create output directory: " .. output_dir
		end
	end

	return output_dir, nil
end

-- Run terraform init asynchronously
function M.run_terraform_init(output_dir, callback)
	local stdout = {}
	local stderr = {}

	Job:new({
		command = "terraform",
		args = { "init" },
		cwd = output_dir,
		on_stdout = function(_, line)
			table.insert(stdout, line)
		end,
		on_stderr = function(_, line)
			table.insert(stderr, line)
		end,
		on_exit = function(_, return_val)
			if return_val ~= 0 then
				vim.schedule(function()
					vim.notify("Terraform init failed:\n" .. table.concat(stderr, "\n"), vim.log.levels.ERROR)
				end)
				if callback then
					callback(false, table.concat(stderr, "\n"))
				end
				return
			end

			if callback then
				callback(true, nil)
			end
		end,
	}):start()
end

-- Run terraform plan with generate-config-out asynchronously
function M.run_terraform_plan_generate(output_dir, callback)
	local stdout = {}
	local stderr = {}

	Job:new({
		command = "terraform",
		args = { "plan", "-generate-config-out=generated.tf" },
		cwd = output_dir,
		on_stdout = function(_, line)
			table.insert(stdout, line)
		end,
		on_stderr = function(_, line)
			table.insert(stderr, line)
		end,
		on_exit = function(_, return_val)
			-- Note: terraform plan may return non-zero for various reasons
			-- but still generate the config file
			local generated_file = output_dir .. "/generated.tf"
			local file_exists = vim.fn.filereadable(generated_file) == 1

			if file_exists then
				vim.schedule(function()
					-- Open the generated file
					vim.cmd("edit " .. generated_file)
				end)

				if callback then
					callback(true, generated_file)
				end
			else
				vim.schedule(function()
					local msg = "Terraform plan completed but no config generated"
					if #stderr > 0 then
						msg = msg .. ":\n" .. table.concat(stderr, "\n")
					end
					vim.notify(msg, vim.log.levels.WARN)
				end)

				if callback then
					callback(false, table.concat(stderr, "\n"))
				end
			end
		end,
	}):start()
end

-- Generate unique filename for import
function M.generate_filename(resource)
	local opts = config.get()
	local tf_type = M.map_azure_to_terraform(resource.type)
	local short_type = tf_type and tf_type:gsub("azurerm_", "") or "resource"
	local timestamp = os.date("%Y%m%d_%H%M%S")

	return string.format("%s/import_%s_%s.tf", opts.terraform.output_dir, short_type, timestamp)
end

-- Generate HCL import block content
function M.generate_import_content(resource)
	local tf_type = M.map_azure_to_terraform(resource.type)

	if not tf_type then
		return nil, string.format("Unsupported resource type: %s", resource.type)
	end

	local opts = config.get()
	local resource_name = opts.terraform.resource_name_placeholder

	-- Only generate import block - no resource block!
	-- The resource configuration will be auto-generated by:
	-- terraform plan -generate-config-out=generated.tf
	local lines = {
		"# Generated by Nimure",
		string.format("# Azure Resource: %s", resource.name),
		string.format("# Azure Type: %s", resource.type),
		string.format("# Generated: %s", os.date("%Y-%m-%d %H:%M:%S")),
		"",
		"import {",
		string.format("  to = %s.%s", tf_type, resource_name),
		string.format('  id = "%s"', resource.id),
		"}",
		"",
	}

	return table.concat(lines, "\n"), nil
end

-- Generate backend configuration content
function M.generate_backend_content()
	local opts = config.get()
	local backend = opts.terraform.backend

	-- Check if backend is configured
	--[[ if not backend.storage_account_name then
		return nil, "Backend storage_account_name not configured"
	end ]]

	local lines = {
		"# Generated by Nimure",
		"# Azure Backend Configuration",
		string.format("# Generated: %s", os.date("%Y-%m-%d %H:%M:%S")),
		"",
		"terraform {",
		"  required_providers {",
		"    azurerm = {",
		'      source  = "hashicorp/azurerm"',
		'      version = "~> 4.57.0"',
		"    }",
		"  }",
		"",
		-- '  backend "azurerm" {',
	}

	-- if backend.use_azuread_cli then
	-- 	table.insert(lines, "    use_azuread_auth    = true")
	-- end
	--
	-- table.insert(lines, "  }")
	table.insert(lines, "}")
	table.insert(lines, "")
	table.insert(lines, 'provider "azurerm" {')
	table.insert(lines, "  features {}")
	table.insert(lines, "}")
	table.insert(lines, "")

	return table.concat(lines, "\n"), nil
end

-- Create backend.tf file if configured
function M.create_backend_config()
	local opts = config.get()

	local output_dir, dir_err = M.create_output_directory()
	if dir_err then
		return nil, dir_err
	end

	local backend_path = output_dir .. "/backend.tf"

	-- Check if backend.tf already exists
	if vim.fn.filereadable(backend_path) == 1 then
		return backend_path, nil -- Already exists
	end

	local content, err = M.generate_backend_content()
	if err then
		return nil, err
	end

	-- Write backend.tf
	local file = io.open(backend_path, "w")
	if not file then
		return nil, "Failed to write backend.tf"
	end

	file:write(content)
	file:close()

	return backend_path, nil
end

-- Main function to generate import block for a resource
function M.generate_import_block(resource)
	-- Validate Terraform CLI
	if not M.check_terraform_cli() then
		vim.schedule(function()
			vim.notify("Terraform CLI not found. Please install Terraform.", vim.log.levels.ERROR)
		end)
		return
	end

	-- Validate resource
	if not resource or not resource.id or not resource.type then
		vim.schedule(function()
			vim.notify("Invalid resource selected", vim.log.levels.ERROR)
		end)
		return
	end

	-- Check if resource type is supported
	local tf_type = M.map_azure_to_terraform(resource.type)
	if not tf_type then
		vim.schedule(function()
			vim.notify(
				string.format("Unsupported resource type: %s\nNo Terraform mapping available.", resource.type),
				vim.log.levels.WARN
			)
		end)
		return
	end

	-- Clean up output directory first (remove old state and files)
	M.clean_output_directory()

	-- Create output directory
	local output_dir, dir_err = M.create_output_directory()
	if dir_err then
		vim.schedule(function()
			vim.notify(dir_err, vim.log.levels.ERROR)
		end)
		return
	end

	-- Generate import content
	local content, content_err = M.generate_import_content(resource)
	if content_err then
		vim.schedule(function()
			vim.notify(content_err, vim.log.levels.ERROR)
		end)
		return
	end

	-- Generate filename and write file
	local filepath = M.generate_filename(resource)
	local file = io.open(filepath, "w")
	if not file then
		vim.schedule(function()
			vim.notify("Failed to create import file: " .. filepath, vim.log.levels.ERROR)
		end)
		return
	end

	file:write(content)
	file:close()

	-- Create backend config
	M.create_backend_config()

	-- Run terraform init, then plan -generate-config-out
	M.run_terraform_init(output_dir, function(init_success, init_error)
		if not init_success then
			return
		end

		-- Run terraform plan to generate the config
		M.run_terraform_plan_generate(output_dir, function(plan_success, result) end)
	end)
end

-- Batch generate import blocks for multiple resources
function M.generate_batch_import(resources)
	if not resources or #resources == 0 then
		vim.schedule(function()
			vim.notify("No resources selected for batch import", vim.log.levels.WARN)
		end)
		return
	end

	-- Validate Terraform CLI
	if not M.check_terraform_cli() then
		vim.schedule(function()
			vim.notify("Terraform CLI not found. Please install Terraform.", vim.log.levels.ERROR)
		end)
		return
	end

	-- Create output directory
	local output_dir, dir_err = M.create_output_directory()
	if dir_err then
		vim.schedule(function()
			vim.notify(dir_err, vim.log.levels.ERROR)
		end)
		return
	end

	local opts = config.get()
	local timestamp = os.date("%Y%m%d_%H%M%S")
	local filepath = string.format("%s/batch_import_%s.tf", output_dir, timestamp)

	local lines = {
		"# Generated by Nimure - Batch Import",
		string.format("# Generated: %s", os.date("%Y-%m-%d %H:%M:%S")),
		string.format("# Resources: %d", #resources),
		"",
	}

	local success_count = 0
	local skipped = {}

	-- Only generate import blocks - no resource blocks!
	-- The resource configuration will be auto-generated by:
	-- terraform plan -generate-config-out=generated.tf
	for i, resource in ipairs(resources) do
		local tf_type = M.map_azure_to_terraform(resource.type)

		if tf_type then
			local resource_name = string.format("%s_%d", opts.terraform.resource_name_placeholder, i)

			table.insert(lines, string.format("# Resource %d: %s", i, resource.name))
			table.insert(lines, "import {")
			table.insert(lines, string.format("  to = %s.%s", tf_type, resource_name))
			table.insert(lines, string.format('  id = "%s"', resource.id))
			table.insert(lines, "}")
			table.insert(lines, "")

			success_count = success_count + 1
		else
			table.insert(skipped, string.format("%s (%s)", resource.name, resource.type))
		end
	end

	-- Write file
	local file = io.open(filepath, "w")
	if not file then
		vim.schedule(function()
			vim.notify("Failed to create batch import file", vim.log.levels.ERROR)
		end)
		return
	end

	file:write(table.concat(lines, "\n"))
	file:close()

	-- Try to create backend config
	M.create_backend_config()

	-- Open file
	if opts.terraform.auto_open then
		vim.schedule(function()
			vim.cmd("edit " .. filepath)
		end)
	end

	-- Show notification
	vim.schedule(function()
		local msg = string.format("Batch import generated: %s\nResources: %d imported", filepath, success_count)

		if #skipped > 0 then
			msg = msg .. string.format(", %d skipped (unsupported types)", #skipped)
		end

		vim.notify(msg, vim.log.levels.INFO)
	end)
end

-- List supported resource types
function M.list_supported_types()
	local types = {}
	for azure_type, tf_type in pairs(M.resource_mapping) do
		table.insert(types, { azure = azure_type, terraform = tf_type })
	end

	table.sort(types, function(a, b)
		return a.azure < b.azure
	end)

	return types
end

-- Check if a resource type is supported
function M.is_type_supported(azure_type)
	return M.resource_mapping[azure_type] ~= nil
end

return M
