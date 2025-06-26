-- Telescope extension for Nimure

local nimure_telescope = require("nimure.telescope")

return require("telescope").register_extension({
  exports = {
    resources = function()
      local nimure = require("nimure")
      local state = nimure.get_state()
      
      if #state.resources == 0 then
        vim.notify("No resources loaded. Refreshing...", vim.log.levels.INFO)
        nimure.refresh_resources()
        return
      end
      
      nimure_telescope.search_resources(state.resources)
    end,
  },
}) 