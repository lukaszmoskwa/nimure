-- Azure integration module using Azure CLI

local Job = require("plenary.job")
local config = require("nimure.config")

local M = {}

-- Cache for frequently accessed data to reduce API calls
M.cache = {
  subscription_info = nil,
  subscription_info_timestamp = 0,
  billing_currency = nil,
  billing_currency_timestamp = 0,
  cost_data = {},
}

-- Rate limiting state
M.rate_limit = {
  last_request_time = 0,
  request_count = 0,
  request_window_start = 0,
}

-- Check if cached data is still valid
local function is_cache_valid(timestamp)
  local cache_ttl = config.get().cache.ttl_seconds or 300
  return os.time() - timestamp < cache_ttl
end

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

-- Clear cache (useful for debugging or forcing fresh data)
function M.clear_cache()
  M.cache.subscription_info = nil
  M.cache.subscription_info_timestamp = 0
  M.cache.billing_currency = nil
  M.cache.billing_currency_timestamp = 0
  M.cache.cost_data = {}
  vim.schedule(function()
    vim.notify("Azure data cache cleared", vim.log.levels.INFO)
  end)
end

-- Clean up old cache entries (called periodically)
local function cleanup_cache()
  local config_opts = config.get()
  if not config_opts.cache.auto_cleanup then
    return
  end
  
  local now = os.time()
  local cache_ttl = config_opts.cache.ttl_seconds or 300
  for key, entry in pairs(M.cache.cost_data) do
    if entry.timestamp and (now - entry.timestamp) > cache_ttl then
      M.cache.cost_data[key] = nil
    end
  end
end

-- Check if Azure CLI is available
function M.check_cli()
  local job = Job:new({
    command = "az",
    args = { "--version" },
    on_exit = function(j, return_val)
      return return_val == 0
    end,
  })
  
  job:sync()
  return job.code == 0
end

-- Check if user is logged in
function M.check_auth()
  local job = Job:new({
    command = "az",
    args = { "account", "show" },
    on_exit = function(j, return_val)
      return return_val == 0
    end,
  })
  
  job:sync()
  return job.code == 0
end

-- Get current subscription info (with caching)
function M.get_subscription_info(callback)
  -- Return cached data if valid
  if M.cache.subscription_info and is_cache_valid(M.cache.subscription_info_timestamp) then
    vim.schedule(function()
      callback(M.cache.subscription_info, nil)
    end)
    return
  end
  
  -- Execute with rate limiting
  execute_with_rate_limit(function()
    local stdout = {}
    local stderr = {}
    
    Job:new({
      command = "az",
      args = { "account", "show", "--output", "json" },
      timeout = config.get().azure.timeout,
      on_stdout = function(_, line)
        table.insert(stdout, line)
      end,
      on_stderr = function(_, line)
        table.insert(stderr, line)
      end,
      on_exit = function(_, return_val)
        if return_val ~= 0 then
          callback(nil, "Failed to get subscription info: " .. table.concat(stderr, "\n"))
          return
        end
        
        local json_str = table.concat(stdout, "\n")
        local ok, result = pcall(vim.json.decode, json_str)
        
        if not ok then
          callback(nil, "Failed to parse subscription info")
          return
        end
        
        -- Cache the result
        M.cache.subscription_info = result
        M.cache.subscription_info_timestamp = os.time()
        callback(result, nil)
      end,
    }):start()
  end)
end

-- Get all resources in subscription
function M.get_resources(callback)
  local stdout = {}
  local stderr = {}
  local args = { "resource", "list", "--output", "json" }
  
  -- Add subscription filter if specified
  local options = config.get()
  if options.azure.subscription_id then
    table.insert(args, "--subscription")
    table.insert(args, options.azure.subscription_id)
  end
  
  -- Add resource group filter if specified
  if #options.azure.resource_groups > 0 then
    for _, rg in ipairs(options.azure.resource_groups) do
      table.insert(args, "--resource-group")
      table.insert(args, rg)
    end
  end
  
  if options.debug then
    vim.schedule(function()
      vim.notify("Running: az " .. table.concat(args, " "), vim.log.levels.DEBUG)
    end)
  end
  
  Job:new({
    command = "az",
    args = args,
    timeout = options.azure.timeout,
    on_stdout = function(_, line)
      table.insert(stdout, line)
    end,
    on_stderr = function(_, line)
      table.insert(stderr, line)
    end,
    on_exit = function(_, return_val)
      if return_val ~= 0 then
        local error_msg = table.concat(stderr, "\n")
        if error_msg:match("Please run 'az login'") then
          error_msg = "Not logged in to Azure. Please run 'az login'"
        end
        callback(nil, error_msg)
        return
      end
      
      local json_str = table.concat(stdout, "\n")
      if json_str == "" or json_str == "[]" then
        callback({}, nil)
        return
      end
      
      local ok, resources = pcall(vim.json.decode, json_str)
      
      if not ok then
        callback(nil, "Failed to parse resources JSON")
        return
      end
      
      -- Process and sort resources
      local processed_resources = M.process_resources(resources)
      callback(processed_resources, nil)
    end,
  }):start()
end

-- Process raw Azure resources
function M.process_resources(resources)
  local processed = {}
  
  for _, resource in ipairs(resources) do
    table.insert(processed, {
      id = resource.id,
      name = resource.name,
      type = resource.type,
      location = resource.location,
      resource_group = M.extract_resource_group(resource.id),
      tags = resource.tags or {},
      kind = resource.kind,
      sku = resource.sku,
    })
  end
  
  -- Sort by resource group, then by name
  table.sort(processed, function(a, b)
    if a.resource_group == b.resource_group then
      return a.name < b.name
    end
    return a.resource_group < b.resource_group
  end)
  
  return processed
end

-- Extract resource group from resource ID
function M.extract_resource_group(resource_id)
  local rg = resource_id:match("/resourceGroups/([^/]+)")
  return rg or "Unknown"
end

-- Get detailed resource information
function M.get_resource_details(resource, callback)
  local stdout = {}
  local stderr = {}
  
  Job:new({
    command = "az",
    args = { "resource", "show", "--ids", resource.id, "--output", "json" },
    timeout = config.get().azure.timeout,
    on_stdout = function(_, line)
      table.insert(stdout, line)
    end,
    on_stderr = function(_, line)
      table.insert(stderr, line)
    end,
    on_exit = function(_, return_val)
      if return_val ~= 0 then
        callback(nil, "Failed to get resource details: " .. table.concat(stderr, "\n"))
        return
      end
      
      local json_str = table.concat(stdout, "\n")
      local ok, details = pcall(vim.json.decode, json_str)
      
      if not ok then
        callback(nil, "Failed to parse resource details")
        return
      end
      
      callback(details, nil)
    end,
  }):start()
end

-- Get resource metrics (simplified for demo)
function M.get_resource_metrics(resource, callback)
  -- For now, we'll return some basic "metrics" from the resource info
  -- In a full implementation, you'd use `az monitor metrics list`
  local metrics = {
    resource_id = resource.id,
    resource_type = resource.type,
    location = resource.location,
    created = "N/A", -- Would need to parse creation time
    status = "Running", -- Would need to check actual status
    tags_count = vim.tbl_count(resource.tags or {}),
  }
  
  callback(metrics, nil)
end

-- Health check
function M.health_check()
  local health = {
    azure_cli_installed = M.check_cli(),
    azure_cli_authenticated = false,
    subscription_info = nil,
  }
  
  if health.azure_cli_installed then
    health.azure_cli_authenticated = M.check_auth()
    
    if health.azure_cli_authenticated then
      M.get_subscription_info(function(info, error)
        if not error then
          health.subscription_info = {
            name = info.name,
            id = info.id,
            tenant_id = info.tenantId,
          }
        end
      end)
    end
  end
  
  return health
end

-- Get billing currency from account information (with caching)
function M.get_billing_currency(callback)
  -- Return cached data if valid
  if M.cache.billing_currency and is_cache_valid(M.cache.billing_currency_timestamp) then
    vim.schedule(function()
      callback(M.cache.billing_currency, nil)
    end)
    return
  end
  
  -- Use cached subscription info if available to avoid double API call
  if M.cache.subscription_info and is_cache_valid(M.cache.subscription_info_timestamp) then
    local account_info = M.cache.subscription_info
    local currency = M._extract_currency_from_account_info(account_info)
    M.cache.billing_currency = currency
    M.cache.billing_currency_timestamp = os.time()
    vim.schedule(function()
      callback(currency, nil)
    end)
    return
  end
  
  -- Execute with rate limiting
  execute_with_rate_limit(function()
    local stdout = {}
    local stderr = {}
    
    Job:new({
      command = "az",
      args = { "account", "show", "--output", "json" },
      timeout = config.get().azure.timeout,
      on_stdout = function(_, line)
        table.insert(stdout, line)
      end,
      on_stderr = function(_, line)
        table.insert(stderr, line)
      end,
      on_exit = function(_, return_val)
        if return_val ~= 0 then
          callback("USD", nil) -- fallback to USD
          return
        end
        
        local json_str = table.concat(stdout, "\n")
        local ok, account_info = pcall(vim.json.decode, json_str)
        
        if not ok then
          callback("USD", nil) -- fallback to USD
          return
        end
        
        local currency = M._extract_currency_from_account_info(account_info)
        
        -- Cache both subscription info and currency
        M.cache.subscription_info = account_info
        M.cache.subscription_info_timestamp = os.time()
        M.cache.billing_currency = currency
        M.cache.billing_currency_timestamp = os.time()
        
        callback(currency, nil)
      end,
    }):start()
  end)
end

-- Helper function to extract currency from account info
function M._extract_currency_from_account_info(account_info)
  -- Try to infer currency from tenant location or user location
  -- This is a best-effort approach since Azure doesn't always expose billing currency directly
  local currency = "USD" -- default fallback
  
  -- Map some common tenant locations to currencies (not exhaustive)
  if account_info.user and account_info.user.name then
    local email_domain = account_info.user.name:match("@(.+)$")
    if email_domain then
      -- Common domain patterns that might indicate currency
      if email_domain:find("%.uk$") or email_domain:find("%.gb$") then
        currency = "GBP"
      elseif email_domain:find("%.de$") or email_domain:find("%.fr$") or 
             email_domain:find("%.it$") or email_domain:find("%.es$") or
             email_domain:find("%.nl$") or email_domain:find("%.at$") then
        currency = "EUR"
      elseif email_domain:find("%.jp$") then
        currency = "JPY"
      elseif email_domain:find("%.ca$") then
        currency = "CAD"
      elseif email_domain:find("%.au$") then
        currency = "AUD"
      elseif email_domain:find("%.in$") then
        currency = "INR"
      end
    end
  end
  
  return currency
end

-- Get cost data using Azure Cost Management API (with caching)
function M.get_subscription_costs(options, callback)
  -- Clean up old cache entries periodically
  cleanup_cache()
  
  -- Default to last 30 days if no time range specified
  local start_date = options.start_date or os.date("%Y-%m-01", os.time() - 30*24*60*60)
  local end_date = options.end_date or os.date("%Y-%m-%d")
  
  -- Create cache key for this request
  local cache_key = string.format("%s_%s", start_date, end_date)
  
  -- Check if we have cached cost data for this date range
  if M.cache.cost_data[cache_key] and 
     M.cache.cost_data[cache_key].timestamp and 
     is_cache_valid(M.cache.cost_data[cache_key].timestamp) then
    vim.schedule(function()
      callback(M.cache.cost_data[cache_key].data, nil)
    end)
    return
  end
  
  -- Get subscription ID
  local config_opts = config.get()
  local subscription_id = config_opts.azure.subscription_id
  
  -- If no subscription ID specified, get the current one
  if not subscription_id then
    M.get_subscription_info(function(sub_info, error)
      if error or not sub_info then
        callback(nil, "Failed to get subscription info: " .. (error or "Unknown error"))
        return
      end
      
      subscription_id = sub_info.id
      M._make_cost_query(subscription_id, start_date, end_date, cache_key, callback)
    end)
  else
    M._make_cost_query(subscription_id, start_date, end_date, cache_key, callback)
  end
end

-- Internal function to make the actual cost query (with rate limiting and caching)
function M._make_cost_query(subscription_id, start_date, end_date, cache_key, callback)
  -- Execute with rate limiting
  execute_with_rate_limit(function()
    local stdout = {}
    local stderr = {}
    
    -- Create the Cost Management API query body
    local query_body = {
      type = "ActualCost",
      timeframe = "Custom",
      timePeriod = {
        from = start_date .. "T00:00:00+00:00",
        to = end_date .. "T23:59:59+00:00"
      },
      dataset = {
        granularity = "Daily",
        aggregation = {
          totalCost = {
            name = "PreTaxCost",
            ["function"] = "Sum"
          }
        },
        grouping = {
          {
            type = "Dimension",
            name = "ServiceName"
          }
        }
      }
    }
    
    -- Convert query body to JSON
    local query_json = vim.json.encode(query_body)
    
    -- Construct the API URL
    local api_url = string.format(
      "https://management.azure.com/subscriptions/%s/providers/Microsoft.CostManagement/query?api-version=2021-10-01",
      subscription_id
    )
    
    local config_opts = config.get()
    if config_opts.debug then
      vim.schedule(function()
        vim.notify("Cost Management API URL: " .. api_url, vim.log.levels.DEBUG)
        vim.notify("Query body: " .. query_json, vim.log.levels.DEBUG)
      end)
    end
    
    Job:new({
      command = "az",
      args = {
        "rest",
        "--method", "POST",
        "--url", api_url,
        "--body", query_json,
        "--headers", "Content-Type=application/json"
      },
      timeout = config_opts.azure.timeout,
      on_stdout = function(_, line)
        table.insert(stdout, line)
      end,
      on_stderr = function(_, line)
        table.insert(stderr, line)
      end,
      on_exit = function(_, return_val)
        if return_val ~= 0 then
          local error_msg = table.concat(stderr, "\n")
          callback(nil, "Cost Management API error: " .. error_msg)
          return
        end
        
        local json_str = table.concat(stdout, "\n")
        if json_str == "" then
          local empty_result = {
            total_cost = 0,
            currency = "USD",
            services = {},
            daily_costs = {},
            period = { start_date = start_date, end_date = end_date }
          }
          -- Cache empty result
          M.cache.cost_data[cache_key] = {
            data = empty_result,
            timestamp = os.time()
          }
          callback(empty_result, nil)
          return
        end
        
        local ok, response = pcall(vim.json.decode, json_str)
        
        if not ok then
          callback(nil, "Failed to parse Cost Management API response")
          return
        end
        
        -- Process the Cost Management API response
        local processed_costs = M.process_cost_management_data(response, start_date, end_date)
        
        -- Only try to get billing currency if we still have default currency
        -- and we don't have it cached already
        if processed_costs.currency == "USD" and not M.cache.billing_currency then
          M.get_billing_currency(function(billing_currency, error)
            if billing_currency and billing_currency ~= "USD" then
              processed_costs.currency = billing_currency
              -- Update all service currencies too
              for _, service in ipairs(processed_costs.services) do
                service.currency = billing_currency
              end
            end
            
            -- Cache the result
            M.cache.cost_data[cache_key] = {
              data = processed_costs,
              timestamp = os.time()
            }
            callback(processed_costs, nil)
          end)
        else
          -- Use cached billing currency if available
          if processed_costs.currency == "USD" and M.cache.billing_currency then
            processed_costs.currency = M.cache.billing_currency
            for _, service in ipairs(processed_costs.services) do
              service.currency = M.cache.billing_currency
            end
          end
          
          -- Cache the result
          M.cache.cost_data[cache_key] = {
            data = processed_costs,
            timestamp = os.time()
          }
          callback(processed_costs, nil)
        end
      end,
    }):start()
  end)
end

-- Process Azure Cost Management API response
function M.process_cost_management_data(response, start_date, end_date)
  local costs_by_service = {}
  local costs_by_date = {}
  local total_cost = 0
  local currency = "USD" -- default fallback
  
  -- Check if response has the expected structure
  if not response.properties or not response.properties.rows then
    return {
      total_cost = 0,
      currency = currency,
      services = {},
      daily_costs = {},
      period = { start_date = start_date, end_date = end_date }
    }
  end
  
  -- Try to extract currency from response metadata
  if response.properties then
    -- Check if there's currency information in the response metadata
    if response.properties.currency and 
       type(response.properties.currency) == "string" and 
       response.properties.currency ~= vim.NIL then
      currency = response.properties.currency
    elseif response.properties.nextLink and 
           type(response.properties.nextLink) == "string" and 
           response.properties.nextLink ~= vim.NIL then
      -- Sometimes currency info is in the nextLink
      local next_link = response.properties.nextLink
      if next_link:find("currency=([A-Z]+)") then
        currency = next_link:match("currency=([A-Z]+)")
      end
    end
  end
  
  -- Map column indices based on Azure Cost Management API response structure
  -- Standard columns: PreTaxCost, UsageDate, Currency, ServiceName (when grouped)
  local columns = response.properties.columns or {}
  local cost_index, date_index, service_index, currency_index = nil, nil, nil, nil
  
  for i, column in ipairs(columns) do
    if column.name == "PreTaxCost" or column.name == "Cost" then
      cost_index = i
    elseif column.name == "UsageDate" or column.name == "Date" then
      date_index = i
    elseif column.name == "ServiceName" or column.name == "Service" then
      service_index = i
    elseif column.name == "Currency" or column.name == "BillingCurrency" then
      currency_index = i
    end
  end
  
  -- Process each row
  for _, row in ipairs(response.properties.rows) do
    local cost = cost_index and tonumber(row[cost_index]) or 0
    local date = date_index and row[date_index] or start_date
    local service_name = service_index and row[service_index] or "Unknown"
    local row_currency = currency_index and row[currency_index] or nil
    
    -- Extract currency from the first row if available and we haven't found it yet
    -- Check for vim.NIL which appears as userdata
    if currency == "USD" and row_currency and 
       type(row_currency) == "string" and 
       row_currency ~= vim.NIL and 
       #row_currency > 0 then
      currency = row_currency
    end
    
    -- Aggregate by service
    if not costs_by_service[service_name] then
      costs_by_service[service_name] = {
        total_cost = 0,
        usage_count = 0,
        currency = currency
      }
    end
    costs_by_service[service_name].total_cost = costs_by_service[service_name].total_cost + cost
    costs_by_service[service_name].usage_count = costs_by_service[service_name].usage_count + 1
    
    -- Aggregate by date
    if date then
      local date_key = tostring(date):sub(1, 10) -- Extract YYYY-MM-DD
      if not costs_by_date[date_key] then
        costs_by_date[date_key] = 0
      end
      costs_by_date[date_key] = costs_by_date[date_key] + cost
    end
    
    total_cost = total_cost + cost
  end
  
  -- Convert to sorted arrays for display
  local services = {}
  for service, data in pairs(costs_by_service) do
    table.insert(services, {
      name = service,
      cost = data.total_cost,
      usage_count = data.usage_count,
      currency = data.currency
    })
  end
  
  -- Sort services by cost (descending)
  table.sort(services, function(a, b)
    return a.cost > b.cost
  end)
  
  local dates = {}
  for date, cost in pairs(costs_by_date) do
    table.insert(dates, {
      date = date,
      cost = cost
    })
  end
  
  -- Sort dates chronologically
  table.sort(dates, function(a, b)
    return a.date < b.date
  end)
  
  return {
    total_cost = total_cost,
    currency = currency,
    services = services,
    daily_costs = dates,
    period = {
      start_date = dates[1] and dates[1].date or start_date,
      end_date = dates[#dates] and dates[#dates].date or end_date
    }
  }
end

-- Get resource-specific cost data (simplified due to API limitations)
function M.get_resource_costs(resource, options, callback)
  -- Since the consumption API is broken, we'll get resource group costs
  -- and provide some basic information
  local start_date = options.start_date or os.date("%Y-%m-01", os.time() - 30*24*60*60)
  local end_date = options.end_date or os.date("%Y-%m-%d")
  
  -- First, try to get resource group costs if available
  if resource.resource_group and resource.resource_group ~= "Unknown" then
    M._get_resource_group_costs(resource, start_date, end_date, callback)
  else
    -- Fallback: return basic resource info with no cost data
    callback({
      total_cost = 0,
      currency = "USD",
      usage_items = {},
      resource_name = resource.name,
      resource_type = resource.type,
      note = "Resource-specific cost data requires Azure Cost Management API access. Showing resource group costs where available."
    }, nil)
  end
end

-- Get costs for a resource group (as a proxy for individual resource costs)
function M._get_resource_group_costs(resource, start_date, end_date, callback)
  local config_opts = config.get()
  local subscription_id = config_opts.azure.subscription_id
  
  -- Get subscription ID if not configured
  if not subscription_id then
    M.get_subscription_info(function(sub_info, error)
      if error or not sub_info then
        callback({
          total_cost = 0,
          currency = "USD",
          usage_items = {},
          resource_name = resource.name,
          resource_type = resource.type,
          note = "Could not retrieve subscription information for cost analysis."
        }, nil)
        return
      end
      
      subscription_id = sub_info.id
      M._make_resource_group_cost_query(subscription_id, resource, start_date, end_date, callback)
    end)
  else
    M._make_resource_group_cost_query(subscription_id, resource, start_date, end_date, callback)
  end
end

-- Make cost query for a specific resource group (with rate limiting)
function M._make_resource_group_cost_query(subscription_id, resource, start_date, end_date, callback)
  -- Execute with rate limiting
  execute_with_rate_limit(function()
    local stdout = {}
    local stderr = {}
    
    -- Create cost query for the resource group
    local query_body = {
      type = "ActualCost",
      timeframe = "Custom",
      timePeriod = {
        from = start_date .. "T00:00:00+00:00",
        to = end_date .. "T23:59:59+00:00"
      },
      dataset = {
        granularity = "Daily",
               aggregation = {
           totalCost = {
             name = "PreTaxCost",
             ["function"] = "Sum"
           }
         },
        filter = {
          dimensions = {
            name = "ResourceGroupName",
            operator = "In",
            values = { resource.resource_group }
          }
        }
      }
    }
    
    local query_json = vim.json.encode(query_body)
    local api_url = string.format(
      "https://management.azure.com/subscriptions/%s/providers/Microsoft.CostManagement/query?api-version=2021-10-01",
      subscription_id
    )
    
    Job:new({
      command = "az",
      args = {
        "rest",
        "--method", "POST",
        "--url", api_url,
        "--body", query_json,
        "--headers", "Content-Type=application/json"
      },
      timeout = config.get().azure.timeout,
      on_stdout = function(_, line)
        table.insert(stdout, line)
      end,
      on_stderr = function(_, line)
        table.insert(stderr, line)
      end,
      on_exit = function(_, return_val)
        if return_val ~= 0 then
          callback({
            total_cost = 0,
            currency = "USD",
            usage_items = {},
            resource_name = resource.name,
            resource_type = resource.type,
            note = "Failed to retrieve cost data: " .. table.concat(stderr, "\n")
          }, nil)
          return
        end
        
        local json_str = table.concat(stdout, "\n")
        if json_str == "" then
          callback({
            total_cost = 0,
            currency = "USD",
            usage_items = {},
            resource_name = resource.name,
            resource_type = resource.type,
            note = "No cost data available for the specified period."
          }, nil)
          return
        end
        
        local ok, response = pcall(vim.json.decode, json_str)
        
        if not ok then
          callback({
            total_cost = 0,
            currency = "USD",
            usage_items = {},
            resource_name = resource.name,
            resource_type = resource.type,
            note = "Failed to parse cost data response."
          }, nil)
          return
        end
        
        -- Process the response and calculate total cost for resource group
        local total_cost = 0
        local currency = "USD"
        
        if response.properties and response.properties.rows then
          for _, row in ipairs(response.properties.rows) do
            -- First column should be PreTaxCost
            local cost = tonumber(row[1]) or 0
            total_cost = total_cost + cost
          end
        end
        
        callback({
          total_cost = total_cost,
          currency = currency,
          usage_items = response.properties and response.properties.rows or {},
          resource_name = resource.name,
          resource_type = resource.type,
          resource_group = resource.resource_group,
          note = string.format("Showing costs for resource group '%s' (period: %s to %s)", 
            resource.resource_group, start_date, end_date)
        }, nil)
      end,
    }):start()
  end)
end

return M 
