--[[
	pale_watcher - Physics Abstraction Layer
	Multi-mod physics compatibility supporting player_monoids, playerphysics, pova, and native fallback.
]]

---@class PaleWatcherPhysics
pale_watcher.physics = {}

-- Cache of baseline physics overrides per player
local default_physics = {}
local active_gaze_factors = {}
local active_terror = {}

local function get_effective_speed(name)
	local factor = 1.0
	if active_terror[name] then
		factor = factor * 0.8
	end
	if active_gaze_factors[name] then
		factor = factor * active_gaze_factors[name]
	end
	return factor
end

local function get_effective_jump(name)
	local factor = 1.0
	if active_terror[name] then
		factor = factor * 0.85
	end
	return factor
end

local function apply_native_override(player)
	local name = player:get_player_name()
	if not default_physics[name] then
		default_physics[name] = player:get_physics_override()
	end
	local base = default_physics[name] or {speed = 1.0, jump = 1.0, gravity = 1.0}
	player:set_physics_override({
		speed = (base.speed or 1.0) * get_effective_speed(name),
		jump = (base.jump or 1.0) * get_effective_jump(name),
	})
end

---Applies terror debuff to a fleeing player.
---@param player ObjectRef
function pale_watcher.physics.apply_terror(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	active_terror[name] = true

	if core.global_exists("player_monoids") then
		player_monoids.speed:add_change(player, 0.8, "pale_watcher:terror")
		player_monoids.jump:add_change(player, 0.85, "pale_watcher:terror")
	elseif core.global_exists("playerphysics") then
		playerphysics.add_physics_factor(player, "speed", "pale_watcher:terror", 0.8)
		playerphysics.add_physics_factor(player, "jump", "pale_watcher:terror", 0.85)
	elseif core.global_exists("pova") then
		pova.add_override(name, "pale_watcher_terror", {speed = -0.2, jump = -0.15})
		pova.do_override(player)
	else
		apply_native_override(player)
	end
end

---Clears terror debuff from a player.
---@param player ObjectRef
function pale_watcher.physics.clear_terror(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	active_terror[name] = nil

	if core.global_exists("player_monoids") then
		player_monoids.speed:del_change(player, "pale_watcher:terror")
		player_monoids.jump:del_change(player, "pale_watcher:terror")
	elseif core.global_exists("playerphysics") then
		playerphysics.remove_physics_factor(player, "speed", "pale_watcher:terror")
		playerphysics.remove_physics_factor(player, "jump", "pale_watcher:terror")
	elseif core.global_exists("pova") then
		pova.del_override(name, "pale_watcher_terror")
		pova.do_override(player)
	else
		if not active_gaze_factors[name] and default_physics[name] then
			player:set_physics_override(default_physics[name])
			default_physics[name] = nil
		elseif default_physics[name] then
			apply_native_override(player)
		end
	end
end

---Applies direct gaze movement paralysis / slowdown to a player staring at the Pale Watcher.
---@param player ObjectRef
---@param factor number Speed multiplier (e.g. 0.4 to 0.7)
function pale_watcher.physics.apply_gaze_slow(player, factor)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local clamped = math.max(0.12, math.min(1.0, factor))
	active_gaze_factors[name] = clamped

	if core.global_exists("player_monoids") then
		player_monoids.speed:add_change(player, clamped, "pale_watcher:gaze")
	elseif core.global_exists("playerphysics") then
		playerphysics.add_physics_factor(player, "speed", "pale_watcher:gaze", clamped)
	elseif core.global_exists("pova") then
		pova.add_override(name, "pale_watcher_gaze", {speed = clamped - 1.0})
		pova.do_override(player)
	else
		apply_native_override(player)
	end
end

---Clears direct gaze paralysis from a player.
---@param player ObjectRef
function pale_watcher.physics.clear_gaze_slow(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	if not active_gaze_factors[name] then return end
	active_gaze_factors[name] = nil

	if core.global_exists("player_monoids") then
		player_monoids.speed:del_change(player, "pale_watcher:gaze")
	elseif core.global_exists("playerphysics") then
		playerphysics.remove_physics_factor(player, "speed", "pale_watcher:gaze")
	elseif core.global_exists("pova") then
		pova.del_override(name, "pale_watcher_gaze")
		pova.do_override(player)
	else
		if not active_terror[name] and default_physics[name] then
			player:set_physics_override(default_physics[name])
			default_physics[name] = nil
		elseif default_physics[name] then
			apply_native_override(player)
		end
	end
end

---Cleans up all physics debuffs on disconnect or session reset.
---@param player ObjectRef
function pale_watcher.physics.clear_all(player)
	if not player or not player:is_player() then return end
	pale_watcher.physics.clear_terror(player)
	pale_watcher.physics.clear_gaze_slow(player)
	local name = player:get_player_name()
	if default_physics[name] then
		player:set_physics_override(default_physics[name])
		default_physics[name] = nil
	end
end

core.register_on_leaveplayer(function(player)
	pale_watcher.physics.clear_all(player)
	local name = player:get_player_name()
	active_terror[name] = nil
	active_gaze_factors[name] = nil
	default_physics[name] = nil
end)

core.register_on_dieplayer(function(player)
	pale_watcher.physics.clear_all(player)
end)

core.register_on_joinplayer(function(player)
	pale_watcher.physics.clear_all(player)
end)

core.register_on_shutdown(function()
	for _, player in ipairs(core.get_connected_players()) do
		pale_watcher.physics.clear_all(player)
	end
end)

return pale_watcher.physics
