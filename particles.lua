--[[
	pale_watcher - Universal Particle Engine & Visual Presets
	Modern Luanti particle spawner factory with automatic legacy fallback population
	and atmospheric horror visual presets.
]]

---@class PaleWatcherParticles
pale_watcher.particles = {}

---Spawns a particle spawner with automatic population of legacy engine fallback keys.
---Ensures 100% compatibility across all Luanti engine versions while keeping code DRY.
---@param def table Modern structured particle definition
---@return integer|nil spawner_id ID of registered particlespawner or nil
function pale_watcher.particles.spawn(def)
	if def.pos then
		def.minpos = def.minpos or def.pos.min
		def.maxpos = def.maxpos or def.pos.max
	end
	if def.vel then
		def.minvel = def.minvel or def.vel.min
		def.maxvel = def.maxvel or def.vel.max
	end
	if def.acc then
		def.minacc = def.minacc or def.acc.min
		def.maxacc = def.maxacc or def.acc.max
	end
	if def.exptime then
		def.minexptime = def.minexptime or def.exptime.min
		def.maxexptime = def.maxexptime or def.exptime.max
	end
	if def.size then
		def.minsize = def.minsize or def.size.min
		def.maxsize = def.maxsize or def.size.max
	end
	if def.texpool and #def.texpool > 0 and not def.texture then
		def.texture = def.texpool[1].name
	end
	return core.add_particlespawner(def)
end

---Cursed page ambient wisps (purple/dark ink wisp loop).
---@param pos Vector Center position
---@return integer|nil
function pale_watcher.particles.page_ambient(pos)
	return pale_watcher.particles.spawn({
		amount = 6,
		time = 1.0,
		pos = {min = vector.subtract(pos, 0.1), max = vector.add(pos, 0.1)},
		vel = {min = {x = -0.05, y = 0.1, z = -0.05}, max = {x = 0.05, y = 0.35, z = 0.05}},
		acc = {min = {x = -0.02, y = 0.05, z = -0.02}, max = {x = 0.02, y = 0.1, z = 0.02}},
		exptime = {min = 1.0, max = 2.0},
		size = {min = 0.5, max = 1.5},
		jitter = {min = {x = -0.05, y = -0.05, z = -0.05}, max = {x = 0.05, y = 0.05, z = 0.05}},
		drag = {min = {x = 0.05, y = 0.05, z = 0.05}, max = {x = 0.1, y = 0.1, z = 0.1}},
		texpool = {
			{name = "pale_watcher_particles.png^[verticalframe:8:2", blend = "alpha"},
			{name = "pale_watcher_particles.png^[verticalframe:8:3", blend = "alpha"},
		},
		scale_tween = {start = 1.0, finish = 0.2},
		alpha_tween = {start = 0.6, finish = 0.0},
	})
end

---Burst of ink mist and paper fragments when a cursed page is picked up.
---@param pos Vector Center position
---@return integer|nil
function pale_watcher.particles.page_pickup(pos)
	return pale_watcher.particles.spawn({
		amount = 45,
		time = 0.8,
		pos = {min = vector.subtract(pos, 0.25), max = vector.add(pos, 0.25)},
		vel = {min = {x = -0.8, y = 0.8, z = -0.8}, max = {x = 0.8, y = 2.2, z = 0.8}},
		acc = {min = {x = -0.1, y = 0.5, z = -0.1}, max = {x = 0.1, y = 1.5, z = 0.1}},
		exptime = {min = 0.8, max = 1.8},
		size = {min = 1.2, max = 3.5},
		jitter = {min = {x = -0.4, y = -0.4, z = -0.4}, max = {x = 0.4, y = 0.4, z = 0.4}},
		drag = {min = {x = 0.1, y = 0.1, z = 0.1}, max = {x = 0.25, y = 0.25, z = 0.25}},
		texpool = {
			{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:1", blend = "add"},
			{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:3", blend = "add"},
			{name = "pale_watcher_cursed_page_item.png^[multiply:#302020", blend = "alpha"},
		},
		scale_tween = {start = 1.2, finish = 0.3},
		alpha_tween = {start = 1.0, finish = 0.0},
		glow = 8,
	})
end

---Cold dark ash puff when an unready player right-clicks the ritual pyre.
---@param pos Vector Center position
---@return integer|nil
function pale_watcher.particles.pyre_cold_rejection(pos)
	return pale_watcher.particles.spawn({
		amount = 15,
		time = 0.5,
		pos = {min = vector.subtract(pos, 0.2), max = vector.add(pos, {x = 0.2, y = 0.4, z = 0.2})},
		vel = {min = {x = -0.2, y = 0.1, z = -0.2}, max = {x = 0.2, y = 0.6, z = 0.2}},
		acc = {min = {x = 0, y = 0, z = 0}, max = {x = 0, y = 0.1, z = 0}},
		exptime = {min = 0.5, max = 1.0},
		size = {min = 1.0, max = 2.0},
		texpool = {
			{name = "pale_watcher_particles.png^[verticalframe:8:4", blend = "alpha"},
			{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
		},
	})
end

---Towering cleansing flame loop for burning ritual pyre.
---@param pos Vector Center position
---@return integer|nil
function pale_watcher.particles.pyre_roaring_flames(pos)
	return pale_watcher.particles.spawn({
		amount = 40,
		time = 0,
		pos = {
			min = {x = pos.x - 0.3, y = pos.y, z = pos.z - 0.3},
			max = {x = pos.x + 0.3, y = pos.y + 0.5, z = pos.z + 0.3},
		},
		vel = {
			min = {x = -0.3, y = 1.0, z = -0.3},
			max = {x = 0.3, y = 2.5, z = 0.3},
		},
		acc = {
			min = {x = -0.1, y = 0.2, z = -0.1},
			max = {x = 0.1, y = 0.8, z = 0.1},
		},
		exptime = {min = 0.8, max = 1.6},
		size = {min = 1.5, max = 4.0},
		jitter = {min = {x = -0.2, y = -0.2, z = -0.2}, max = {x = 0.2, y = 0.2, z = 0.2}},
		texpool = {
			{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:1", blend = "add"},
			{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:4", blend = "add"},
		},
		scale_tween = {start = 1.5, finish = 0.2},
		alpha_tween = {start = 1.0, finish = 0.0},
		glow = 14,
	})
end

---High-intensity xenon sparks and smoke bursting forward from vintage flash camera.
---@param eye_pos Vector Player eye position
---@param look_dir Vector Player look direction
---@return integer|nil
function pale_watcher.particles.camera_sparks(eye_pos, look_dir)
	return pale_watcher.particles.spawn({
		amount = 25,
		time = 0.2,
		pos = {
			min = vector.add(eye_pos, vector.multiply(look_dir, 0.5)),
			max = vector.add(eye_pos, vector.multiply(look_dir, 0.8)),
		},
		vel = {
			min = vector.multiply(look_dir, 2.0),
			max = vector.multiply(look_dir, 6.0),
		},
		acc = {min = {x = -1, y = -1, z = -1}, max = {x = 1, y = 1, z = 1}},
		exptime = {min = 0.2, max = 0.6},
		size = {min = 1.0, max = 3.0},
		jitter = {min = {x = -0.5, y = -0.5, z = -0.5}, max = {x = 0.5, y = 0.5, z = 0.5}},
		texpool = {
			{name = "pale_watcher_hud_flash.png", blend = "add"},
		},
		glow = 14,
	})
end

---Dimensional void mist burst for teleportation, shroud blink, or mob repositioning.
---@param pos Vector Center position
---@param height? number Height of vertical column (default 0.5)
---@param amount? number Particle count (default 30)
---@return integer|nil
function pale_watcher.particles.void_mist(pos, height, amount)
	local h = height or 0.5
	return pale_watcher.particles.spawn({
		amount = amount or 30,
		time = 0.3,
		pos = {min = vector.subtract(pos, 0.5), max = vector.add(pos, {x = 0.5, y = h, z = 0.5})},
		vel = {min = {x = -1, y = 0.5, z = -1}, max = {x = 1, y = 2, z = 1}},
		acc = {min = {x = 0, y = -1, z = 0}, max = {x = 0, y = -0.5, z = 0}},
		exptime = {min = 0.5, max = 1.0},
		size = {min = 1.0, max = 2.5},
		texpool = {
			{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
			{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
			{name = "pale_watcher_particles.png^[verticalframe:8:7", blend = "add"},
		},
	})
end

---Radiant white-gold embers dissolving the mob at sunrise.
---@param pos Vector Mob base position
---@return integer|nil
function pale_watcher.particles.dawn_banish_burn(pos)
	return pale_watcher.particles.spawn({
		amount = 60,
		time = 2.0,
		pos = {min = vector.subtract(pos, 0.5), max = vector.add(pos, {x = 0.5, y = 3.0, z = 0.5})},
		vel = {min = {x = -0.5, y = 0.5, z = -0.5}, max = {x = 0.5, y = 2.0, z = 0.5}},
		acc = {min = {x = 0, y = 0.5, z = 0}, max = {x = 0, y = 1.0, z = 0}},
		exptime = {min = 1.0, max = 2.5},
		size = {min = 1.0, max = 3.5},
		texpool = {
			{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
			{name = "pale_watcher_particles.png^[verticalframe:8:4", blend = "alpha"},
		},
	})
end

---Soft vaporizing mist when the mob dissolves at the edge of sanctuary light.
---@param pos Vector Mob base position
---@return integer|nil
function pale_watcher.particles.sanctuary_dissolve(pos)
	return pale_watcher.particles.spawn({
		amount = 50,
		time = 1.0,
		pos = {min = vector.subtract(pos, 0.5), max = vector.add(pos, {x = 0.5, y = 3.0, z = 0.5})},
		vel = {min = {x = -0.5, y = 0.2, z = -0.5}, max = {x = 0.5, y = 1.5, z = 0.5}},
		acc = {min = {x = 0, y = 0, z = 0}, max = {x = 0, y = 0.2, z = 0}},
		exptime = {min = 1.0, max = 2.0},
		size = {min = 1.0, max = 3.0},
		texpool = {
			{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
			{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
		},
	})
end

---Swirling inward crimson and void particles around a player caught in bunker choke.
---@param player_pos Vector Player world position
---@return integer|nil
function pale_watcher.particles.psychic_choke(player_pos)
	return pale_watcher.particles.spawn({
		amount = 20,
		time = 0.3,
		pos = {min = vector.subtract(player_pos, 0.6), max = vector.add(player_pos, {x = 0.6, y = 1.8, z = 0.6})},
		vel = {min = {x = -0.5, y = -0.2, z = -0.5}, max = {x = 0.5, y = 0.5, z = 0.5}},
		exptime = {min = 0.4, max = 0.8},
		size = {min = 1.0, max = 2.5},
		texpool = {
			{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
			{name = "pale_watcher_particles.png^[verticalframe:8:7", blend = "add"},
		},
	})
end

---Massive pyre implosion burst when the Pale Watcher is cleansed in the flames.
---@param pos Vector Mob/Pyre position
---@return integer|nil
function pale_watcher.particles.pyre_implosion(pos)
	return pale_watcher.particles.spawn({
		amount = 120,
		time = 1.5,
		pos = {min = vector.subtract(pos, 0.8), max = vector.add(pos, {x = 0.8, y = 3.2, z = 0.8})},
		vel = {min = {x = -2.0, y = 1.0, z = -2.0}, max = {x = 2.0, y = 4.0, z = 2.0}},
		acc = {min = {x = 0, y = -2.0, z = 0}, max = {x = 0, y = -0.5, z = 0}},
		exptime = {min = 1.0, max = 2.5},
		size = {min = 1.5, max = 4.0},
		texpool = {
			{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
			{name = "pale_watcher_particles.png^[verticalframe:8:4", blend = "alpha"},
			{name = "pale_watcher_particles.png^[verticalframe:8:7", blend = "add"},
			{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:1", blend = "add"},
		},
	})
end

---Dramatic dimensional phase rift when the mob teleports away (after flash or dimensional slip).
---Produces a full 3.5m tall vortex of swirling void mist, pale embers, and crackling static sparks.
---@param pos Vector Mob feet position
---@return integer|nil
function pale_watcher.particles.teleport_rift(pos)
	return pale_watcher.particles.spawn({
		amount = 70,
		time = 0.5,
		pos = {
			min = vector.subtract(pos, {x = 0.6, y = 0.1, z = 0.6}),
			max = vector.add(pos, {x = 0.6, y = 3.2, z = 0.6}),
		},
		vel = {
			min = {x = -1.5, y = 0.5, z = -1.5},
			max = {x = 1.5, y = 3.5, z = 1.5},
		},
		acc = {
			min = {x = -0.5, y = -1.0, z = -0.5},
			max = {x = 0.5, y = 0.5, z = 0.5},
		},
		exptime = {min = 0.8, max = 1.6},
		size = {min = 1.8, max = 4.0},
		jitter = {min = {x = -0.4, y = -0.4, z = -0.4}, max = {x = 0.4, y = 0.4, z = 0.4}},
		drag = {min = {x = 0.1, y = 0.1, z = 0.1}, max = {x = 0.2, y = 0.2, z = 0.2}},
		texpool = {
			{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
			{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
			{name = "pale_watcher_particles.png^[verticalframe:8:7", blend = "add"},
			{name = "pale_watcher_hud_flash.png", blend = "add"},
		},
		scale_tween = {start = 1.8, finish = 0.2},
		alpha_tween = {start = 1.0, finish = 0.0},
		glow = 8,
	})
end

return pale_watcher.particles
