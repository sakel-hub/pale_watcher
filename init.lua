local modpath = core.get_modpath(core.get_current_modname())

-- Load public API namespace first
dofile(modpath .. "/api.lua")

-- Load modules
dofile(modpath .. "/physics.lua")
dofile(modpath .. "/fx.lua")
dofile(modpath .. "/nodes.lua")
dofile(modpath .. "/ritual.lua")
dofile(modpath .. "/pale_watcher.lua")
dofile(modpath .. "/chatcommands.lua")
