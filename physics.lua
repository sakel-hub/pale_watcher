--[[
	pale_watcher - Physics & Gaze Debuff Facade
	Delegates player movement and FOV modifiers to x_mob_core's status effect subsystem
	with delta/interval throttling to prevent per-tick network and metadata churn.
]]

local TERROR_EFFECT_ID = "pale_watcher:terror"
local GAZE_EFFECT_ID = "pale_watcher:gaze"

x_mob_core.register_status_effect_preset(TERROR_EFFECT_ID, {
	id = TERROR_EFFECT_ID,
	type = "slow",
	category = "debuff",
	duration = 2.5,
	speed_factor = 0.85,
})

-- Per-player throttle cache: { terror_time = number, gaze_time = number, gaze_speed = number, gaze_fov = number }
local player_state = {}

local function get_now()
	return core.get_us_time() / 1000000
end

---Applies sprint terror debuff to a fleeing player (throttled to avoid per-tick re-application).
---@param player ObjectRef
function pale_watcher.physics.apply_terror(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local now = get_now()
	local st = player_state[name]
	if st and st.terror_time and (now - st.terror_time) < 0.4 and
		x_mob_core.has_status_effect(player, TERROR_EFFECT_ID) then
		return
	end
	if not st then
		st = {}
		player_state[name] = st
	end
	st.terror_time = now
	x_mob_core.apply_status_effect(player, TERROR_EFFECT_ID)
end

---Clears sprint terror debuff from a player.
---@param player ObjectRef
function pale_watcher.physics.clear_terror(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local st = player_state[name]
	if st then
		st.terror_time = nil
	end
	if x_mob_core.has_status_effect(player, TERROR_EFFECT_ID) then
		x_mob_core.remove_status_effect(player, TERROR_EFFECT_ID)
	end
end

---Applies direct gaze movement slowdown and optional camera FOV narrowing to a player staring at the Pale Watcher.
---@param player ObjectRef
---@param factor number Speed multiplier (clamped to [0.12, 1.0])
---@param fov_factor? number Optional camera FOV multiplier
function pale_watcher.physics.apply_gaze_slow(player, factor, fov_factor)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local clamped = math.max(0.12, math.min(1.0, factor))
	local now = get_now()
	local st = player_state[name]

	if st and st.gaze_time and (now - st.gaze_time) < 0.25 and
		math.abs((st.gaze_speed or 0) - clamped) < 0.02 and
		math.abs((st.gaze_fov or 0) - (fov_factor or 0)) < 0.02 and
		x_mob_core.has_status_effect(player, GAZE_EFFECT_ID) then
		return
	end

	if not st then
		st = {}
		player_state[name] = st
	end
	st.gaze_time = now
	st.gaze_speed = clamped
	st.gaze_fov = fov_factor

	x_mob_core.apply_status_effect(player, {
		id = GAZE_EFFECT_ID,
		type = "slow",
		category = "debuff",
		duration = 1.0,
		speed_factor = clamped,
		fov_factor = fov_factor,
		fov_transition = 0.25,
	})
end

---Clears direct gaze slowdown and FOV narrowing from a player.
---@param player ObjectRef
function pale_watcher.physics.clear_gaze_slow(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local st = player_state[name]
	if st then
		st.gaze_time = nil
		st.gaze_speed = nil
		st.gaze_fov = nil
	end
	if x_mob_core.has_status_effect(player, GAZE_EFFECT_ID) then
		x_mob_core.remove_status_effect(player, GAZE_EFFECT_ID)
	end
end

---Cleans up all Pale Watcher physics and FOV debuffs on a player.
---@param player ObjectRef
function pale_watcher.physics.clear_all(player)
	if not player or not player:is_player() then return end
	pale_watcher.physics.clear_terror(player)
	pale_watcher.physics.clear_gaze_slow(player)
	player_state[player:get_player_name()] = nil
end

core.register_on_leaveplayer(function(player)
	player_state[player:get_player_name()] = nil
end)

return pale_watcher.physics
