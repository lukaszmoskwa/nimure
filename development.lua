-- Development configuration for Nimure
-- Place this in ~/.config/nvim-nimure/init.lua for testing

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- Plugin specification
local plugins = {
	-- Dependencies
	{
		"MunifTanjim/nui.nvim",
	},
	{
		"nvim-telescope/telescope.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
	},
	{
		"nvim-lua/plenary.nvim",
	},
	{
		"nvim-tree/nvim-web-devicons",
		optional = true,
	},

	-- Nimure plugin (local development)
	{
		dir = vim.fn.getcwd(), -- Current directory
		name = "nimure",
		dependencies = {
			"MunifTanjim/nui.nvim",
			"nvim-telescope/telescope.nvim",
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
		},
		config = function()
			require("nimure").setup({
				-- Development configuration
				debug = true,
				sidebar = {
					width = 50,
					position = "left",
				},
				ui = {
					show_icons = true,
					show_type = true,
					show_location = true,
				},
			})
		end,
	},
}

-- Setup lazy.nvim
require("lazy").setup(plugins, {
	-- Lazy.nvim configuration
	install = {
		colorscheme = { "default" },
	},
	checker = {
		enabled = false,
	},
})

-- Basic Neovim settings for development
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true

-- Set leader key
vim.g.mapleader = " "

-- Development keymaps
vim.keymap.set(
	"n",
	"<leader>nr",
	':lua require("nimure").refresh_resources()<CR>',
	{ desc = "Refresh Nimure resources" }
)
vim.keymap.set("n", "<leader>nt", ':lua require("nimure").toggle_sidebar()<CR>', { desc = "Toggle Nimure sidebar" })
vim.keymap.set(
	"n",
	"<leader>nf",
	':lua require("nimure").toggle_floating_right()<CR>',
	{ desc = "Toggle floating sidebar" }
)
vim.keymap.set("n", "<leader>ns", ':lua require("nimure").search_resources()<CR>', { desc = "Search Nimure resources" })
vim.keymap.set("n", "<leader>nh", ":checkhealth nimure<CR>", { desc = "Check Nimure health" })

-- Development commands
vim.api.nvim_create_user_command("NimureReload", function()
	-- Reload the plugin
	package.loaded["nimure"] = nil
	package.loaded["nimure.config"] = nil
	package.loaded["nimure.azure"] = nil
	package.loaded["nimure.ui"] = nil
	package.loaded["nimure.telescope"] = nil
	package.loaded["nimure.utils"] = nil
	package.loaded["nimure.health"] = nil

	require("nimure").setup({
		debug = true,
		sidebar = {
			width = 50,
			position = "left",
		},
		ui = {
			show_icons = true,
			show_type = true,
			show_location = true,
		},
	})

	vim.schedule(function()
		vim.notify("Nimure reloaded!", vim.log.levels.INFO)
	end)
end, { desc = "Reload Nimure plugin" })

-- Print development info
vim.schedule(function()
	vim.notify("Nimure development environment loaded!", vim.log.levels.INFO)
	vim.notify(
		"Available commands: :NimureToggle, :NimureFloatRight, :NimureRefresh, :NimureSearch, :NimureHealth, :NimureReload",
		vim.log.levels.INFO
	)
	vim.notify(
		"Keymaps: <leader>nt (toggle), <leader>nf (float right), <leader>nr (refresh), <leader>ns (search), <leader>nh (health)",
		vim.log.levels.INFO
	)
end)
