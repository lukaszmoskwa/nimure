-- Telescope extension for Nimure

return require("telescope").register_extension({
	exports = {
		search_resources = require("nimure.telescope").search_resources,
		search_ad_objects = require("nimure.telescope").search_ad_objects,
		search_role_assignments = require("nimure.telescope").search_role_assignments,
		switch_subscription = require("nimure.telescope").switch_subscription,
	},
})