local modpath = core.get_modpath(core.get_current_modname())

-- Load public API namespace first
dofile(modpath .. "/api.lua")

-- Load subsystems & modular components
dofile(modpath .. "/particles.lua")
dofile(modpath .. "/physics.lua")
dofile(modpath .. "/fx.lua")
dofile(modpath .. "/nodes.lua")
dofile(modpath .. "/items.lua")
dofile(modpath .. "/recipes.lua")
dofile(modpath .. "/ritual.lua")
dofile(modpath .. "/pale_watcher.lua")
dofile(modpath .. "/chatcommands.lua")
