--[[
	pale_watcher - Client HUD, Audio Interference & Visual Horror FX
	Responsive screen vignette, animated static noise, FOV narrowing, claustrophobic fog,
	and audio whispering / Geiger compass effects.
]]

---@class PaleWatcherFX
pale_watcher.fx = {}

---@class PaleWatcherPlayerFXState
---@field hud_static_id? integer
---@field hud_vignette_id? integer
---@field hud_flash_id? integer
---@field flash_timer? number
---@field sound_handle? any
---@field intensity number
---@field time number
---@field is_gazing boolean
---@field fog_active boolean
---@field _refreshed_this_tick boolean

---@type table<string, PaleWatcherPlayerFXState>
local active_fx = {}

local function get_static_texture(intensity, time)
	if intensity <= 0.01 then return "" end
	local frame = (math.floor(time * 15) % 3) + 1
	local alpha = math.min(255, math.floor(intensity * 255))
	return string.format("pale_watcher_hud_static_%d.png^[opacity:%d", frame, alpha)
end

---Updates player horror effects per tick (called by Pale Watcher AI).
---@param player ObjectRef Target player
---@param distance number Distance to Pale Watcher
---@param is_looked_at boolean Whether player's crosshair is on Pale Watcher
---@param dtime number Delta time
---@param stalker_tier integer Current stalker tier (0 to 4)
function pale_watcher.fx.update_player(player, distance, is_looked_at, dtime, stalker_tier)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local state = active_fx[name]

	if not state then
		state = {
			time = 0,
			intensity = 0,
			hud_static_id = nil,
			hud_vignette_id = nil,
			hud_flash_id = nil,
			flash_timer = 0,
			sound_handle = nil,
			is_gazing = false,
			fog_active = false,
		}
		active_fx[name] = state
	end

	state.time = state.time + dtime
	state._refreshed_this_tick = true

	local tier = stalker_tier or 0
	-- Base static radius widens with each collected page / tier
	local static_max_radius = 25.0 + (tier * 6.0)

	-- Calculate target static intensity
	local target_intensity = 0.0
	if distance and distance < static_max_radius then
		target_intensity = 1.0 - (distance / static_max_radius)
		if is_looked_at then
			-- Direct gaze heavily intensifies static interference
			target_intensity = target_intensity * 1.6 + 0.25
		end
	end
	target_intensity = math.max(0.0, math.min(1.0, target_intensity))

	-- Smooth transition for natural static surging
	state.intensity = state.intensity + (target_intensity - state.intensity) * dtime * 2.5

	-- Direct Gaze Mechanics: FOV narrowing, movement slow, sanity drain
	if is_looked_at and distance and distance < static_max_radius then
		if not state.is_gazing then
			state.is_gazing = true
		end

		-- Narrows FOV dynamically based on proximity (0.85 down to 0.55)
		local fov_factor = 0.85 - (1.0 - math.min(1.0, distance / 25.0)) * 0.30
		fov_factor = math.max(0.55, math.min(0.90, fov_factor))
		player:set_fov(fov_factor, true, 0.25)

		-- Slow movement speed during direct gaze
		local slow_factor = 0.70 - (1.0 - math.min(1.0, distance / 20.0)) * 0.35
		pale_watcher.physics.apply_gaze_slow(player, slow_factor)

		-- Sanity & Health drain
		if distance <= 20.0 then
			state._drain_acc = (state._drain_acc or 0) + dtime
			if state._drain_acc >= 1.0 then
				state._drain_acc = 0
				local cur_hp = player:get_hp()
				if cur_hp > 1 then
					player:set_hp(cur_hp - 1, "pale_watcher:gaze_drain")
					core.sound_play("pale_watcher_static", {
						to_player = name,
						gain = 0.4,
						pitch = 1.2
					})
				end
			end
		end
	else
		if state.is_gazing then
			state.is_gazing = false
			-- Smoothly restore normal FOV and physics
			player:set_fov(0, false, 0.35)
			pale_watcher.physics.clear_gaze_slow(player)
		end
	end

	-- HUD Overlays: Responsive Vignette + Animated Static
	if state.intensity > 0.02 then
		-- 1. Responsive Vignette
		local vignette_alpha = math.min(255, math.floor(state.intensity * 230 + 25))
		local vig_tex = string.format("pale_watcher_hud_vignette.png^[opacity:%d", vignette_alpha)
		if not state.hud_vignette_id then
			state.hud_vignette_id = player:hud_add({
				hud_elem_type = "image",
				position = {x = 0.5, y = 0.5},
				name = "pale_watcher_vignette",
				scale = {x = -100, y = -100}, -- Responsively spans 100% of viewport
				text = vig_tex,
				alignment = {x = 0, y = 0},
				z_index = -3,
			})
		else
			player:hud_change(state.hud_vignette_id, "text", vig_tex)
		end

		-- 2. Static Noise Overlay
		local static_tex = get_static_texture(state.intensity, state.time)
		if not state.hud_static_id then
			state.hud_static_id = player:hud_add({
				hud_elem_type = "image",
				position = {x = 0.5, y = 0.5},
				name = "pale_watcher_static",
				scale = {x = -100, y = -100},
				text = static_tex,
				alignment = {x = 0, y = 0},
				z_index = -2,
			})
		else
			player:hud_change(state.hud_static_id, "text", static_tex)
		end

		-- 3. Looping Static Audio
		if not state.sound_handle then
			state.sound_handle = core.sound_play("pale_watcher_static", {
				to_player = name,
				loop = true,
				gain = math.max(0.1, state.intensity * 0.65)
			})
		end
	else
		-- Remove HUD overlays when calm
		if state.hud_vignette_id then
			player:hud_remove(state.hud_vignette_id)
			state.hud_vignette_id = nil
		end
		if state.hud_static_id then
			player:hud_remove(state.hud_static_id)
			state.hud_static_id = nil
		end
		if state.sound_handle then
			core.sound_stop(state.sound_handle)
			state.sound_handle = nil
		end
	end
end

---Sweeps and removes any orphaned Pale Watcher flash HUD elements from a player.
---@param player ObjectRef
local function sweep_orphaned_flash(player)
	if not player or not player:is_player() then return end
	for id = 0, 200 do
		local elem = player:hud_get(id)
		if elem then
			local is_flash = elem.name == "pale_watcher_flash"
				or (type(elem.text) == "string" and elem.text:find("pale_watcher_hud_flash", 1, true) ~= nil)
			if is_flash then
				player:hud_remove(id)
			end
		end
	end
end

---Sweeps and removes all orphaned Pale Watcher HUD elements from a player.
---@param player ObjectRef
local function sweep_orphaned_hud(player)
	if not player or not player:is_player() then return end
	for id = 0, 200 do
		local elem = player:hud_get(id)
		if elem then
			local is_pw = elem.name == "pale_watcher_flash"
				or elem.name == "pale_watcher_vignette"
				or elem.name == "pale_watcher_static"
				or (type(elem.text) == "string" and elem.text:find("pale_watcher_hud_", 1, true) ~= nil)
			if is_pw then
				player:hud_remove(id)
			end
		end
	end
end

---Triggers full-screen camera flash effect for a player.
---@param player ObjectRef
function pale_watcher.fx.trigger_flash(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local state = active_fx[name]
	if not state then
		state = {
			time = 0,
			intensity = 0,
			hud_static_id = nil,
			hud_vignette_id = nil,
			hud_flash_id = nil,
			flash_timer = 0,
			sound_handle = nil,
			is_gazing = false,
			fog_active = false,
		}
		active_fx[name] = state
	end

	state.flash_timer = 0.4 -- 0.4s flash decay

	-- Check if existing hud_flash_id is still valid on player
	if state.hud_flash_id then
		local existing = player:hud_get(state.hud_flash_id)
		if not existing then
			state.hud_flash_id = nil
		end
	end

	if not state.hud_flash_id then
		sweep_orphaned_flash(player)
		state.hud_flash_id = player:hud_add({
			hud_elem_type = "image",
			position = {x = 0.5, y = 0.5},
			name = "pale_watcher_flash",
			scale = {x = -100, y = -100},
			text = "pale_watcher_hud_flash.png^[opacity:255",
			alignment = {x = 0, y = 0},
			z_index = 100,
		})
	else
		player:hud_change(state.hud_flash_id, "text", "pale_watcher_hud_flash.png^[opacity:255")
	end

	-- Fail-safe timer to guarantee removal even if globalstep is suspended or delayed
	core.after(0.45, function()
		if not player:is_player() then return end
		local s = active_fx[name]
		if s and s.hud_flash_id and (s.flash_timer or 0) <= 0.05 then
			player:hud_remove(s.hud_flash_id)
			s.hud_flash_id = nil
			s.flash_timer = 0
		end
	end)
end

---Sets claustrophobic black domain fog for a player inside the haunted zone.
---@param player ObjectRef
function pale_watcher.fx.apply_claustrophobic_fog(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local state = active_fx[name]
	if state and state.fog_active then return end

	if not state then
		state = {
			time = 0,
			intensity = 0,
			hud_static_id = nil,
			hud_vignette_id = nil,
			hud_flash_id = nil,
			flash_timer = 0,
			sound_handle = nil,
			is_gazing = false,
			fog_active = false,
		}
		active_fx[name] = state
	end

	state.fog_active = true
	player:set_sky({
		fog = {
			fog_distance = 12,
			fog_start = 0.1,
		}
	})
end

---Restores standard fog and view distance when escaping domain or defeating Pale Watcher.
---@param player ObjectRef
function pale_watcher.fx.clear_claustrophobic_fog(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local state = active_fx[name]
	if state then
		state.fog_active = false
	end
	player:set_sky({
		fog = {
			fog_distance = -1,
			fog_start = -1,
		}
	})
end

---Cleans up all HUD and audio effects for a single player.
---@param player ObjectRef
function pale_watcher.fx.clear_player(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local state = active_fx[name]
	if state then
		if state.hud_vignette_id then
			player:hud_remove(state.hud_vignette_id)
			state.hud_vignette_id = nil
		end
		if state.hud_static_id then
			player:hud_remove(state.hud_static_id)
			state.hud_static_id = nil
		end
		if state.hud_flash_id then
			player:hud_remove(state.hud_flash_id)
			state.hud_flash_id = nil
		end
		state.flash_timer = 0
		if state.sound_handle then
			core.sound_stop(state.sound_handle)
			state.sound_handle = nil
		end
		if state.is_gazing then
			player:set_fov(0, false, 0.3)
			pale_watcher.physics.clear_gaze_slow(player)
			state.is_gazing = false
		end
		if state.fog_active then
			pale_watcher.fx.clear_claustrophobic_fog(player)
		end
		active_fx[name] = nil
	end
	sweep_orphaned_hud(player)
end

---Cleans up all active effects across all players.
function pale_watcher.fx.clear_all()
	for name, _ in pairs(active_fx) do
		local player = core.get_player_by_name(name)
		if player then
			pale_watcher.fx.clear_player(player)
		end
	end
	active_fx = {}
	for _, player in ipairs(core.get_connected_players()) do
		sweep_orphaned_hud(player)
	end
end

-- Globalstep decay and Geiger-counter check
core.register_globalstep(function(dtime)
	if not next(active_fx) then return end

	for name, state in pairs(active_fx) do
		local player = core.get_player_by_name(name)

		-- Flash overlay decay
		if (state.flash_timer or 0) > 0 then
			state.flash_timer = state.flash_timer - dtime
			if state.flash_timer > 0 then
				if player and state.hud_flash_id then
					local flash_alpha = math.max(0, math.min(255, math.floor((state.flash_timer / 0.4) * 255)))
					player:hud_change(state.hud_flash_id, "text",
						string.format("pale_watcher_hud_flash.png^[opacity:%d", flash_alpha))
				end
			else
				state.flash_timer = 0
				if player and state.hud_flash_id then
					player:hud_remove(state.hud_flash_id)
				end
				state.hud_flash_id = nil
			end
		elseif state.hud_flash_id then
			if player then
				player:hud_remove(state.hud_flash_id)
			end
			state.hud_flash_id = nil
			state.flash_timer = 0
		end

		-- Natural static decay when player looks away or distance increases
		if not state._refreshed_this_tick then
			state.intensity = (state.intensity or 0) - dtime * 2.0
			if state.is_gazing and player then
				state.is_gazing = false
				player:set_fov(0, false, 0.35)
				pale_watcher.physics.clear_gaze_slow(player)
			end

			if player and state.intensity > 0.02 then
				local vig_alpha = math.min(255, math.floor(state.intensity * 230 + 25))
				local vig_tex = string.format("pale_watcher_hud_vignette.png^[opacity:%d", vig_alpha)
				if state.hud_vignette_id then
					player:hud_change(state.hud_vignette_id, "text", vig_tex)
				end
				local static_tex = get_static_texture(state.intensity, state.time + dtime)
				if state.hud_static_id then
					player:hud_change(state.hud_static_id, "text", static_tex)
				end
			else
				state.intensity = 0
				if player then
					if state.hud_vignette_id then
						player:hud_remove(state.hud_vignette_id)
						state.hud_vignette_id = nil
					end
					if state.hud_static_id then
						player:hud_remove(state.hud_static_id)
						state.hud_static_id = nil
					end
				else
					state.hud_vignette_id = nil
					state.hud_static_id = nil
				end
				if state.sound_handle then
					core.sound_stop(state.sound_handle)
					state.sound_handle = nil
				end
			end
		end

		state._refreshed_this_tick = false

		-- Prune player from active_fx only when ALL horror & flash effects are completely idle
		local is_busy = (state.intensity > 0.02)
			or ((state.flash_timer or 0) > 0)
			or (state.hud_flash_id ~= nil)
			or (state.hud_vignette_id ~= nil)
			or (state.hud_static_id ~= nil)
			or state.fog_active
			or state.is_gazing
			or (state.sound_handle ~= nil)

		if not is_busy then
			active_fx[name] = nil
		end
	end
end)

core.register_on_leaveplayer(function(player)
	pale_watcher.fx.clear_player(player)
end)

core.register_on_dieplayer(function(player)
	pale_watcher.fx.clear_player(player)
end)

core.register_on_joinplayer(function(player)
	pale_watcher.fx.clear_player(player)
	player:set_fov(0)
	pale_watcher.fx.clear_claustrophobic_fog(player)
end)

core.register_on_shutdown(function()
	pale_watcher.fx.clear_all()
end)

core.register_chatcommand("pw_clear", {
	description = "Clears all active Pale Watcher horror HUD and visual effects",
	privs = {},
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		pale_watcher.fx.clear_player(player)
		player:set_fov(0)
		pale_watcher.fx.clear_claustrophobic_fog(player)
		return true, "All Pale Watcher visual and audio effects cleared."
	end,
})

return pale_watcher.fx
