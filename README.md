# Nimure 🌊

**Azure Resource Explorer for Neovim**

Nimure is a Neovim plugin that provides a beautiful sidebar interface to explore and manage your Azure subscription resources directly from your editor.

## ✨ Features

- 🗂️ **Sidebar View**: Clean sidebar showing all Azure resources in your subscription
- 🔍 **Telescope Integration**: Search and filter resources with fuzzy finding
- 🎨 **Resource Icons**: Visual icons for different Azure resource types
- 📊 **Resource Details**: View detailed information about any resource
- 📈 **Metrics**: Display resource metrics and usage statistics
- 💰 **Cost Tracking**: View Azure subscription costs and spending breakdown by service using Azure Cost Management API
- 🌍 **Multi-Currency Support**: Automatically detects and displays costs in your Azure billing currency (USD, EUR, GBP, JPY, etc.)
- 📊 **Cost Visualization**: ASCII charts showing daily costs and service spending over time
- 🔐 **Azure AD Integration**: Browse and manage Azure Active Directory objects (app registrations, users, groups, roles)
- 📱 **App Registrations**: View Azure AD application registrations with properties and permissions
- 👥 **Users & Groups**: Browse Azure AD users and groups with membership information
- 🔑 **Role Management**: View Azure RBAC role assignments across your subscription
- 🏗️ **Terraform Import**: Generate HCL import blocks for Azure resources with automatic backend configuration
- 📋 **Copy IDs**: Quick copy resource IDs and names to clipboard
- 🔄 **Manual Refresh**: Refresh resource list on demand
- ⚡ **Async**: Non-blocking operations using plenary.nvim

## 📋 Requirements

- Neovim >= 0.8.0
- Azure CLI (`az`) installed and configured
- Terraform CLI (optional, for import generation)
- Required Neovim plugins:
  - [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
  - [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
  - [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
  - [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (optional, for icons)

## 🚀 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "lukaszmoskwa/nimure",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons", -- optional
  },
  config = function()
    require("nimure").setup({
      -- your configuration here
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "lukaszmoskwa/nimure",
  requires = {
    "MunifTanjim/nui.nvim",
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons", -- optional
  },
  config = function()
    require("nimure").setup()
  end,
}
```

## ⚙️ Configuration

```lua
require("nimure").setup({
  -- Sidebar configuration
  sidebar = {
    width = 40,
    position = "left", -- "left" or "right"
    auto_close = false,
  },

  -- Azure configuration
  azure = {
    subscription_id = nil, -- nil to use default subscription
    resource_groups = {}, -- empty to show all resource groups
  },

  -- UI configuration
  ui = {
    show_icons = true,
    show_resource_group = true,
    show_location = true,
    show_type = true,
  },

  -- Keybindings
  keymaps = {
    toggle_sidebar = "<leader>az",
    refresh = "r",
    details = "<CR>",
    metrics = "m",
    copy_id = "y",
    copy_name = "Y",
    search = "/",
    costs = "c", -- View subscription costs
    cost_breakdown = "C", -- View detailed cost breakdown
    -- Azure AD specific keymaps
    show_app_details = "a", -- Show app registration details
    show_user_details = "u", -- Show user details
    show_group_members = "g", -- Show group members
    show_role_details = "r", -- Show role assignment details
    ad_search = "S", -- Search Azure AD objects
    terraform_import = "t", -- Generate Terraform import block
  },

  -- Cost tracking configuration
  costs = {
    enabled = true,
    default_period_days = 30, -- Default to last 30 days
    show_daily_chart = true,
    show_service_breakdown = true,
    chart_height = 10, -- Height of ASCII charts
    -- Currency symbols are now auto-detected from Azure billing data
  },

  -- Terraform import configuration
  terraform = {
    enabled = true,
    backend = {
      resource_group_name = "terraform-state",
      storage_account_name = "tfstate12345", -- Set to enable backend.tf generation
      container_name = "tfstate",
      key = "terraform.tfstate",
      use_azuread_cli = true,
    },
    output_dir = "/tmp/nimure-terraform",
    auto_open = true, -- Automatically open generated file
    resource_name_placeholder = "example", -- Placeholder for resource names
  },

  -- Azure AD configuration
  azure_ad = {
    enabled = true,
    include_app_registrations = true,
    include_users = true,
    include_groups = true,
    include_role_assignments = true,
    include_service_principals = false, -- Optional: can be resource intensive
    -- Filter options for large environments
    user_filters = {}, -- Filter by UPN domain, etc.
    group_filters = {},
    app_filters = {},
  },

  -- Cache and rate limiting configuration
  cache = {
    ttl_seconds = 300, -- 5 minutes cache TTL
    auto_cleanup = true, -- Automatically clean up old cache entries
  },

  rate_limiting = {
    enabled = true, -- Enable rate limiting to prevent API throttling
    min_interval_ms = 1000, -- Minimum 1 second between requests
    max_requests_per_minute = 20, -- Conservative API rate limit
  },
})
```

## 🎯 Usage

### Basic Commands

- `:NimureToggle` - Toggle the sidebar
- `:NimureOpen` - Open the sidebar
- `:NimureClose` - Close the sidebar
- `:NimureRefresh` - Refresh resource list
- `:NimureSearch` - Open Telescope resource search

### Cost Tracking Commands

- `:NimureCosts` - Show Azure subscription cost overview
- `:NimureCostBreakdown` - Show detailed cost breakdown with charts
- `:NimureCostsCustom <start-date> <end-date>` - Show costs for custom date range
  - Example: `:NimureCostsCustom 2024-01-01 2024-01-31`

### Azure AD Commands

- `:NimureADSearch` - Search all Azure AD objects with Telescope
- `:NimureADApps` - Search Azure AD app registrations
- `:NimureADUsers` - Search Azure AD users
- `:NimureADGroups` - Search Azure AD groups
- `:NimureADRoles` - Search Azure AD role assignments

### Terraform Import

Nimure can generate Terraform HCL import blocks for Azure resources, making it easy to import existing infrastructure into Terraform.

#### How to Use

1. Open the Nimure sidebar (`:NimureToggle` or `<leader>az`)
2. Navigate to the resource you want to import
3. Press `t` to generate the Terraform import block
4. The generated file opens automatically in Neovim
5. Follow the instructions in the notification to complete the import

#### Generated Files

Files are generated in `/tmp/nimure-terraform/` (configurable):

- `import_<resource_type>_<timestamp>.tf` - Import block and resource placeholder
- `backend.tf` - Azure backend configuration (if `storage_account_name` is configured)

#### Next Steps After Generation

```bash
cd /tmp/nimure-terraform
terraform init
terraform plan -generate-config-out=generated.tf
# Review generated.tf and adjust as needed
terraform apply
```

#### Supported Resource Types

Nimure supports 100+ Azure resource types including:

- Compute (VMs, Scale Sets, Disks)
- Storage (Storage Accounts, Containers)
- Networking (VNets, Subnets, NSGs, Load Balancers)
- Databases (PostgreSQL, MySQL, SQL Server, CosmosDB)
- Containers (AKS, Container Registry)
- Web (App Service, Functions)
- And many more...

Run `:checkhealth nimure` to see the full count of supported types.

### Cache Management Commands

- `:NimureClearCache` - Clear cached Azure and Azure AD data to force fresh API calls

### Default Keybindings

In the sidebar:

- `<CR>` - View resource/AD object details
- `m` - View resource metrics
- `y` - Copy resource/AD object ID to clipboard
- `Y` - Copy resource/AD object name to clipboard
- `r` - Refresh resource list
- `/` - Search resources with Telescope
- `S` - Search Azure AD objects with Telescope
- `c` - View subscription cost overview
- `C` - View detailed cost breakdown
- `R` - View costs for selected resource
- `t` - Generate Terraform import block for selected resource
- `q` - Close sidebar

Global:

- `<leader>az` - Toggle sidebar

## 🔧 Troubleshooting

### "Too Many Requests" Error (HTTP 429)

If you encounter "Too Many Requests" errors, the plugin has built-in optimizations to prevent this:

- **Automatic Caching**: API responses are cached for 5 minutes to reduce redundant calls
- **Rate Limiting**: Minimum 1-second intervals between API calls with max 20 requests/minute
- **Smart Currency Detection**: Billing currency is cached and reused across requests

**Solutions:**

1. **Automatic Handling**: The plugin will automatically handle rate limiting with non-blocking delays
2. **Clear Cache**: Use `:NimureClearCache` if you need fresh data immediately
3. **Adjust Settings**: Increase rate limiting intervals in your configuration:

```lua
require("nimure").setup({
  rate_limiting = {
    min_interval_ms = 2000, -- 2 seconds between requests
    max_requests_per_minute = 10, -- More conservative limit
  },
})
```

## 🔐 Azure AD Features

Nimure now includes comprehensive Azure Active Directory integration, allowing you to browse and manage AD objects alongside your Azure resources.

### Supported AD Objects

- **App Registrations**: View Azure AD application registrations with properties like Application ID, reply URLs, and permissions
- **Users**: Browse user accounts with details like UPN, email, department, and account status
- **Groups**: View security and distribution groups with membership information
- **Role Assignments**: Browse Azure RBAC role assignments across your subscription with scope and principal details

### Azure AD Permissions

To access Azure AD data, you need appropriate permissions:

- **Application.Read.All** or **Directory.Read.All** for app registrations
- **User.Read.All** for user listings
- **Group.Read.All** for group listings
- **RoleAssignment.ReadWrite.Directory** for role assignments

The plugin will check permissions on startup and provide helpful error messages if access is denied.

### Configuration

You can customize which AD objects to display in your configuration:

```lua
require("nimure").setup({
  azure_ad = {
    enabled = true, -- Enable/disable Azure AD features
    include_app_registrations = true,
    include_users = true,
    include_groups = true,
    include_role_assignments = true,
    include_service_principals = false, -- Resource intensive, disabled by default
    -- Filters for large environments
    user_filters = { "*.example.com" }, -- Only show users from specific domains
    group_filters = {},
    app_filters = {},
  },
})
```

### Performance Tips

- **Use Caching**: Data is cached for 5 minutes by default to improve performance
- **Avoid Rapid Requests**: Don't call multiple cost commands simultaneously
- **Custom Date Ranges**: Use smaller date ranges for faster responses
- **Resource Costs**: Resource-specific costs use resource group aggregation for better performance
- **Large AD Environments**: Consider using filters if you have thousands of AD objects

### Common Issues

1. **"Azure CLI not found"**: Install Azure CLI and ensure it's in your PATH
2. **"Not authenticated"**: Run `az login` to authenticate with Azure
3. **"No subscription found"**: Run `az account show` to verify your subscription
4. **Empty resource list**: Check your subscription has resources or verify resource group filters
5. **"Insufficient permissions"**: Ensure you have proper Azure AD permissions (see above)
6. **"Too Many Requests"**: The plugin includes rate limiting; consider increasing intervals in config

## 🛠️ Development Setup

### Prerequisites

1. **Azure CLI**: Install and authenticate

   ```bash
   # Install Azure CLI
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

   # Login to Azure
   az login

   # Verify authentication
   az account show
   ```

2. **Neovim with required plugins**: Ensure you have the dependencies installed

### Local Development

1. **Clone the repository**:

   ```bash
   git clone https://github.com/lukaszmoskwa/nimure.git
   cd nimure
   ```

2. **Set up development environment**:

   ```bash
   # Create a test Neovim configuration
   mkdir -p ~/.config/nvim-nimure
   ```

3. **Create development init.lua**:

   ```lua
   -- ~/.config/nvim-nimure/init.lua
   local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
   if not vim.loop.fs_stat(lazypath) then
     vim.fn.system({
       "git", "clone", "--filter=blob:none",
       "https://github.com/folke/lazy.nvim.git",
       "--branch=stable", lazypath,
     })
   end
   vim.opt.rtp:prepend(lazypath)

   require("lazy").setup({
     {
       dir = "/path/to/your/nimure", -- Adjust path
       dependencies = {
         "MunifTanjim/nui.nvim",
         "nvim-telescope/telescope.nvim",
         "nvim-lua/plenary.nvim",
         "nvim-tree/nvim-web-devicons",
       },
       config = function()
         require("nimure").setup({
           -- Development configuration
         })
       end,
     }
   })
   ```

4. **Run development Neovim**:
   ```bash
   NVIM_APPNAME=nvim-nimure nvim
   ```

### Testing

1. **Test Azure CLI integration**:

   ```bash
   # Verify Azure CLI works
   az resource list --output table
   ```

2. **Test plugin loading**:

   ```vim
   :checkhealth nimure
   ```

3. **Manual testing**:
   - Open Neovim with the plugin
   - Run `:NimureToggle`
   - Verify resources load in sidebar
   - Test all keybindings and actions

### Debugging

Enable debug logging:

```lua
require("nimure").setup({
  debug = true,
})
```

View logs:

```vim
:messages
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Add tests if applicable
5. Commit your changes: `git commit -m 'Add amazing feature'`
6. Push to the branch: `git push origin feature/amazing-feature`
7. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) for the beautiful UI components
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for the fuzzy finding
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for async utilities
- Azure CLI team for the excellent command-line interface

## 📸 Screenshots

![Nimure Sidebar](screenshots/sidebar.png)
![Telescope Integration](screenshots/telescope.png)
![Resource Details](screenshots/details.png)

