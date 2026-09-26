--[[
	pale_watcher - Crafting Recipes & Mapblock Load Maintenance
	Ritual Pyre, Flash Camera, Shroud of Stalking, and Transient Light Purge LBM.
]]

-- 1. Ritual Pyre Recipe (Stone + Wood + Torch/Coal)
core.register_craft({
	output = "pale_watcher:ritual_pyre",
	recipe = {
		{"group:stone", "group:wood", "group:stone"},
		{"group:wood",  "group:torch", "group:wood"},
		{"group:stone", "group:wood", "group:stone"},
	},
})

-- Fallback with coal if torch group not present
core.register_craft({
	output = "pale_watcher:ritual_pyre",
	recipe = {
		{"group:stone", "group:wood", "group:stone"},
		{"group:wood",  "group:coal", "group:wood"},
		{"group:stone", "group:wood", "group:stone"},
	},
})

-- 2. Flash Camera Recipe (Steel + Glass + Torch)
core.register_craft({
	output = "pale_watcher:flash_camera",
	recipe = {
		{"", "group:torch", ""},
		{"group:steel_ingot", "group:glass", "group:steel_ingot"},
		{"group:steel_ingot", "group:steel_ingot", "group:steel_ingot"},
	},
})

-- Fallback for default steel/glass
core.register_craft({
	output = "pale_watcher:flash_camera",
	recipe = {
		{"", "default:torch", ""},
		{"default:steel_ingot", "default:glass", "default:steel_ingot"},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
	},
})

-- 3. Shroud of Stalking Recipe (4x Dimensional Cloth + Static Core)
core.register_craft({
	output = "pale_watcher:shroud_of_stalking",
	recipe = {
		{"pale_watcher:dimensional_cloth", "pale_watcher:static_core", "pale_watcher:dimensional_cloth"},
		{"pale_watcher:dimensional_cloth", "", "pale_watcher:dimensional_cloth"},
		{"", "", ""},
	},
})

-- LBM to purge any transient flash light nodes on mapblock load / server reboot
core.register_lbm({
	name = "pale_watcher:purge_transient_lights",
	nodenames = {"pale_watcher:flash_light"},
	run_at_every_load = true,
	action = function(pos)
		core.remove_node(pos)
	end,
})
