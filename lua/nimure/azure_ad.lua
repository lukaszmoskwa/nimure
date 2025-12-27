-- Azure AD integration module using Azure CLI
-- Follows the same patterns as azure.lua

local Job = require("plenary.job")
local config = require("nimure.config")

local M = {}

-- Cache for frequently accessed AD data to reduce API calls
M.cache = {
	app_registrations = {},
	app_registrations_timestamp = 0,
	users = {},
	users_timestamp = 0,
	groups = {},
	groups_timestamp = 0,
	role_assignments = {},
	role_assignments_timestamp = 0,
	service_principals = {},
	service_principals_timestamp = 0,
}

-- Check if cached data is still valid
local function is_cache_valid(timestamp)
	local cache_ttl = config.get().cache.ttl_seconds or 300
	return os.time() - timestamp < cache_ttl
end

-- Rate limiting state (shared with azure.lua pattern)
M.rate_limit = {
	last_request_time = 0,
	request_count = 0,
	request_window_start = 0,
}

-- Rate limiting check
local function should_rate_limit()
	local config_opts = config.get()
	if not config_opts.rate_limiting.enabled then
		return false
	end

	local now = os.time() * 1000 -- milliseconds
	local max_requests = config_opts.rate_limiting.max_requests_per_minute or 20
	local min_interval = config_opts.rate_limiting.min_interval_ms or 1000

	-- Reset window if more than a minute has passed
	if now - M.rate_limit.request_window_start > 60000 then
		M.rate_limit.request_count = 0
		M.rate_limit.request_window_start = now
	end

	-- Check if we're hitting the rate limit
	if M.rate_limit.request_count >= max_requests then
		return true
	end

	-- Check minimum interval between requests
	if now - M.rate_limit.last_request_time < min_interval then
		return true
	end

	return false
end

-- Record an API request
local function record_request()
	local now = os.time() * 1000
	M.rate_limit.last_request_time = now
	M.rate_limit.request_count = M.rate_limit.request_count + 1
end

-- Check if we need to wait for rate limiting and return wait time
local function get_rate_limit_wait_time()
	if not should_rate_limit() then
		return 0
	end

	local min_interval = config.get().rate_limiting.min_interval_ms or 1000
	local wait_time = min_interval - (os.time() * 1000 - M.rate_limit.last_request_time)
	return math.max(0, wait_time)
end

-- Execute a function after rate limiting delay (non-blocking)
local function execute_with_rate_limit(fn)
	local wait_time = get_rate_limit_wait_time()

	if wait_time > 0 then
		vim.schedule(function()
			vim.notify("Rate limiting: waiting " .. math.ceil(wait_time / 1000) .. " seconds...", vim.log.levels.INFO)
		end)

		vim.defer_fn(function()
			record_request()
			fn()
		end, wait_time)
	else
		record_request()
		fn()
	end
end

-- Check if user has Azure AD permissions
function M.check_ad_permissions(callback)
	-- Use account show to verify basic Azure connectivity
	-- We'll check AD permissions when actually trying to fetch AD objects
	local stdout = {}
	local stderr = {}

	Job:new({
		command = "az",
		args = { "account", "show", "--query", "tenantId", "--output", "tsv" },
		timeout = config.get().azure.timeout,
		on_stdout = function(_, line)
			table.insert(stdout, line)
		end,
		on_stderr = function(_, line)
			table.insert(stderr, line)
		end,
		on_exit = function(_, return_val)
			if return_val ~= 0 then
				local error_msg = table.concat(stderr, "\n")
				callback(false, "Failed to verify Azure account: " .. error_msg)
				return
			end

			-- If we can get tenant ID, we have basic Azure access
			-- AD permissions will be checked during actual AD operations
			callback(true, nil)
		end,
	}):start()
end

-- Get Azure AD app registrations
function M.get_app_registrations(callback)
	-- Return cached data if valid
	if M.cache.app_registrations and is_cache_valid(M.cache.app_registrations_timestamp) then
		vim.schedule(function()
			callback(M.cache.app_registrations, nil)
		end)
		return
	end

	-- Execute with rate limiting
	execute_with_rate_limit(function()
		local stdout = {}
		local stderr = {}

		Job:new({
			command = "az",
			args = { "ad", "app", "list", "--output", "json" },
			timeout = config.get().azure.timeout,
			on_stdout = function(_, line)
				table.insert(stdout, line)
			end,
			on_stderr = function(_, line)
				table.insert(stderr, line)
			end,
			on_exit = function(_, return_val)
				if return_val ~= 0 then
					local error_msg = table.concat(stderr, "\n")
					callback(nil, "Failed to get app registrations: " .. error_msg)
					return
				end

				local json_str = table.concat(stdout, "\n")
				if json_str == "" or json_str == "[]" then
					callback({}, nil)
					return
				end

				local ok, apps = pcall(vim.json.decode, json_str)
				if not ok then
					callback(nil, "Failed to parse app registrations JSON")
					return
				end

				-- Process and cache app registrations
				local processed_apps = M.process_app_registrations(apps)
				M.cache.app_registrations = processed_apps
				M.cache.app_registrations_timestamp = os.time()

				callback(processed_apps, nil)
			end,
		}):start()
	end)
end

-- Process raw Azure AD app registrations
function M.process_app_registrations(apps)
	local processed = {}

	for _, app in ipairs(apps) do
		table.insert(processed, {
			id = "azure-ad://app-registrations/" .. app.id,
			name = app.displayName or app.name or "Unknown",
			type = "Microsoft.AzureAD/appRegistrations",
			location = "Azure AD",
			resource_group = "Azure AD",
			tags = {},
			properties = {
				app_id = app.appId,
				object_id = app.id,
				display_name = app.displayName,
				sign_in_audience = app.signInAudience,
				homepage = app.homepage,
				reply_urls = app.replyUrls or {},
				required_resource_accesses = app.requiredResourceAccess or {},
				owners = {},
				created_date_time = app.createdDateTime,
				updated_date_time = app.updatedDateTime,
			},
		})
	end

	-- Sort by display name
	table.sort(processed, function(a, b)
		return a.name < b.name
	end)

	return processed
end

-- Get Azure AD users
function M.get_users(callback)
	-- Return cached data if valid
	if M.cache.users and is_cache_valid(M.cache.users_timestamp) then
		vim.schedule(function()
			callback(M.cache.users, nil)
		end)
		return
	end

	-- Execute with rate limiting
	execute_with_rate_limit(function()
		local stdout = {}
		local stderr = {}

		Job:new({
			command = "az",
			args = { "ad", "user", "list", "--output", "json" },
			timeout = config.get().azure.timeout,
			on_stdout = function(_, line)
				table.insert(stdout, line)
			end,
			on_stderr = function(_, line)
				table.insert(stderr, line)
			end,
			on_exit = function(_, return_val)
				if return_val ~= 0 then
					local error_msg = table.concat(stderr, "\n")
					callback(nil, "Failed to get users: " .. error_msg)
					return
				end

				local json_str = table.concat(stdout, "\n")
				if json_str == "" or json_str == "[]" then
					callback({}, nil)
					return
				end

				local ok, users = pcall(vim.json.decode, json_str)
				if not ok then
					callback(nil, "Failed to parse users JSON")
					return
				end

				-- Process and cache users
				local processed_users = M.process_users(users)
				M.cache.users = processed_users
				M.cache.users_timestamp = os.time()

				callback(processed_users, nil)
			end,
		}):start()
	end)
end

-- Process raw Azure AD users
function M.process_users(users)
	local processed = {}

	for _, user in ipairs(users) do
		table.insert(processed, {
			id = "azure-ad://users/" .. user.id,
			name = user.displayName or user.userPrincipalName or "Unknown",
			type = "Microsoft.AzureAD/users",
			location = "Azure AD",
			resource_group = "Azure AD",
			tags = {},
			properties = {
				object_id = user.id,
				user_principal_name = user.userPrincipalName,
				display_name = user.displayName,
				mail = user.mail,
				account_enabled = user.accountEnabled,
				job_title = user.jobTitle,
				department = user.department,
				company_name = user.companyName,
				creation_type = user.creationType,
				created_date_time = user.createdDateTime,
				last_sign_in_date_time = user.lastSignInDateTime,
			},
		})
	end

	-- Sort by display name
	table.sort(processed, function(a, b)
		return a.name < b.name
	end)

	return processed
end

-- Get Azure AD groups
function M.get_groups(callback)
	-- Return cached data if valid
	if M.cache.groups and is_cache_valid(M.cache.groups_timestamp) then
		vim.schedule(function()
			callback(M.cache.groups, nil)
		end)
		return
	end

	-- Execute with rate limiting
	execute_with_rate_limit(function()
		local stdout = {}
		local stderr = {}

		Job:new({
			command = "az",
			args = { "ad", "group", "list", "--output", "json" },
			timeout = config.get().azure.timeout,
			on_stdout = function(_, line)
				table.insert(stdout, line)
			end,
			on_stderr = function(_, line)
				table.insert(stderr, line)
			end,
			on_exit = function(_, return_val)
				if return_val ~= 0 then
					local error_msg = table.concat(stderr, "\n")
					callback(nil, "Failed to get groups: " .. error_msg)
					return
				end

				local json_str = table.concat(stdout, "\n")
				if json_str == "" or json_str == "[]" then
					callback({}, nil)
					return
				end

				local ok, groups = pcall(vim.json.decode, json_str)
				if not ok then
					callback(nil, "Failed to parse groups JSON")
					return
				end

				-- Process and cache groups
				local processed_groups = M.process_groups(groups)
				M.cache.groups = processed_groups
				M.cache.groups_timestamp = os.time()

				callback(processed_groups, nil)
			end,
		}):start()
	end)
end

-- Process raw Azure AD groups
function M.process_groups(groups)
	local processed = {}

	for _, group in ipairs(groups) do
		table.insert(processed, {
			id = "azure-ad://groups/" .. group.id,
			name = group.displayName or group.mailNickname or "Unknown",
			type = "Microsoft.AzureAD/groups",
			location = "Azure AD",
			resource_group = "Azure AD",
			tags = {},
			properties = {
				object_id = group.id,
				display_name = group.displayName,
				mail = group.mail,
				mail_enabled = group.mailEnabled,
				mail_nickname = group.mailNickname,
				security_enabled = group.securityEnabled,
				description = group.description,
				created_date_time = group.createdDateTime,
				membership_types = group.groupTypes or {},
			},
		})
	end

	-- Sort by display name
	table.sort(processed, function(a, b)
		return a.name < b.name
	end)

	return processed
end

-- Get Azure role assignments
function M.get_role_assignments(callback)
	-- Return cached data if valid
	if M.cache.role_assignments and is_cache_valid(M.cache.role_assignments_timestamp) then
		vim.schedule(function()
			callback(M.cache.role_assignments, nil)
		end)
		return
	end

	-- Execute with rate limiting
	execute_with_rate_limit(function()
		local stdout = {}
		local stderr = {}

		Job:new({
			command = "az",
			args = { "role", "assignment", "list", "--output", "json" },
			timeout = config.get().azure.timeout,
			on_stdout = function(_, line)
				table.insert(stdout, line)
			end,
			on_stderr = function(_, line)
				table.insert(stderr, line)
			end,
			on_exit = function(_, return_val)
				if return_val ~= 0 then
					local error_msg = table.concat(stderr, "\n")
					callback(nil, "Failed to get role assignments: " .. error_msg)
					return
				end

				local json_str = table.concat(stdout, "\n")
				if json_str == "" or json_str == "[]" then
					callback({}, nil)
					return
				end

				local ok, assignments = pcall(vim.json.decode, json_str)
				if not ok then
					callback(nil, "Failed to parse role assignments JSON")
					return
				end

				-- Process and cache role assignments
				local processed_assignments = M.process_role_assignments(assignments)
				M.cache.role_assignments = processed_assignments
				M.cache.role_assignments_timestamp = os.time()

				callback(processed_assignments, nil)
			end,
		}):start()
	end)
end

-- Process raw Azure role assignments
function M.process_role_assignments(assignments)
	local processed = {}

	for _, assignment in ipairs(assignments) do
		table.insert(processed, {
			id = "azure-ad://role-assignments/" .. assignment.id,
			name = assignment.properties and assignment.properties.roleDefinitionName or "Unknown Role",
			type = "Microsoft.AzureAD/roleAssignments",
			location = "Azure AD",
			resource_group = "Azure AD",
			tags = {},
			properties = {
				assignment_id = assignment.id,
				scope = assignment.properties and assignment.properties.scope or "Unknown",
				role_definition_id = assignment.properties and assignment.properties.roleDefinitionId or "Unknown",
				role_definition_name = assignment.properties and assignment.properties.roleDefinitionName or "Unknown",
				principal_id = assignment.properties and assignment.properties.principalId or "Unknown",
				principal_type = assignment.properties and assignment.properties.principalType or "Unknown",
				principal_name = assignment.properties and assignment.properties.principalName or "Unknown",
				created_on = assignment.properties and assignment.properties.createdOn or "Unknown",
				updated_on = assignment.properties and assignment.properties.updatedOn or "Unknown",
				description = assignment.properties and assignment.properties.description or "Azure role assignment",
			},
		})
	end

	-- Sort by role name, then by principal name
	table.sort(processed, function(a, b)
		if a.name == b.name then
			return (a.properties.principal_name or "") < (b.properties.principal_name or "")
		end
		return a.name < b.name
	end)

	return processed
end

-- Get detailed information about a specific app registration
function M.get_app_registration_details(app, callback)
	local stdout = {}
	local stderr = {}

	Job:new({
		command = "az",
		args = { "ad", "app", "show", "--id", app.properties.app_id, "--output", "json" },
		timeout = config.get().azure.timeout,
		on_stdout = function(_, line)
			table.insert(stdout, line)
		end,
		on_stderr = function(_, line)
			table.insert(stderr, line)
		end,
		on_exit = function(_, return_val)
			if return_val ~= 0 then
				callback(nil, "Failed to get app registration details: " .. table.concat(stderr, "\n"))
				return
			end

			local json_str = table.concat(stdout, "\n")
			local ok, details = pcall(vim.json.decode, json_str)

			if not ok then
				callback(nil, "Failed to parse app registration details")
				return
			end

			callback(details, nil)
		end,
	}):start()
end

-- Get detailed information about a specific user
function M.get_user_details(user, callback)
	local stdout = {}
	local stderr = {}

	Job:new({
		command = "az",
		args = { "ad", "user", "show", "--id", user.properties.object_id, "--output", "json" },
		timeout = config.get().azure.timeout,
		on_stdout = function(_, line)
			table.insert(stdout, line)
		end,
		on_stderr = function(_, line)
			table.insert(stderr, line)
		end,
		on_exit = function(_, return_val)
			if return_val ~= 0 then
				callback(nil, "Failed to get user details: " .. table.concat(stderr, "\n"))
				return
			end

			local json_str = table.concat(stdout, "\n")
			local ok, details = pcall(vim.json.decode, json_str)

			if not ok then
				callback(nil, "Failed to parse user details")
				return
			end

			callback(details, nil)
		end,
	}):start()
end

-- Get members of a specific group
function M.get_group_members(group, callback)
	local stdout = {}
	local stderr = {}

	Job:new({
		command = "az",
		args = { "ad", "group", "member", "list", "--group", group.properties.object_id, "--output", "json" },
		timeout = config.get().azure.timeout,
		on_stdout = function(_, line)
			table.insert(stdout, line)
		end,
		on_stderr = function(_, line)
			table.insert(stderr, line)
		end,
		on_exit = function(_, return_val)
			if return_val ~= 0 then
				callback(nil, "Failed to get group members: " .. table.concat(stderr, "\n"))
				return
			end

			local json_str = table.concat(stdout, "\n")
			if json_str == "" or json_str == "[]" then
				callback({}, nil)
				return
			end

			local ok, members = pcall(vim.json.decode, json_str)

			if not ok then
				callback(nil, "Failed to parse group members")
				return
			end

			callback(members, nil)
		end,
	}):start()
end

-- Clear Azure AD cache
function M.clear_cache()
	M.cache.app_registrations = {}
	M.cache.app_registrations_timestamp = 0
	M.cache.users = {}
	M.cache.users_timestamp = 0
	M.cache.groups = {}
	M.cache.groups_timestamp = 0
	M.cache.role_assignments = {}
	M.cache.role_assignments_timestamp = 0
	M.cache.service_principals = {}
	M.cache.service_principals_timestamp = 0
	
	vim.schedule(function()
		vim.notify("Azure AD data cache cleared", vim.log.levels.INFO)
	end)
end

return M