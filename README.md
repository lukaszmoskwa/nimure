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
- 📋 **Copy IDs**: Quick copy resource IDs and names to clipboard
- 🔄 **Manual Refresh**: Refresh resource list on demand
- ⚡ **Async**: Non-blocking operations using plenary.nvim

## 📋 Requirements

- Neovim >= 0.8.0
- Azure CLI (`az`) installed and configured
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

### Cache Management Commands

- `:NimureClearCache` - Clear cached Azure data to force fresh API calls

### Default Keybindings

In the sidebar:
- `<CR>` - View resource details
- `m` - View resource metrics
- `y` - Copy resource ID to clipboard
- `Y` - Copy resource name to clipboard
- `r` - Refresh resource list
- `/` - Search resources with Telescope
- `c` - View subscription cost overview
- `C` - View detailed cost breakdown
- `R` - View costs for selected resource
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

### Performance Tips

- **Use Caching**: Data is cached for 5 minutes by default to improve performance
- **Avoid Rapid Requests**: Don't call multiple cost commands simultaneously  
- **Custom Date Ranges**: Use smaller date ranges for faster responses
- **Resource Costs**: Resource-specific costs use resource group aggregation for better performance

### Common Issues

1. **"Azure CLI not found"**: Install Azure CLI and ensure it's in your PATH
2. **"Not authenticated"**: Run `az login` to authenticate with Azure
3. **"No subscription found"**: Run `az account show` to verify your subscription
4. **Empty resource list**: Check your subscription has resources or verify resource group filters

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