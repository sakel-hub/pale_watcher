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
---@field sound_handle? any
---@field intensity number
---@field time number
---@field is_gazing boolean
---@field fog_active boolean
---@field _refreshed_this_tick boolean

---@type table<string, PaleWatcherPlayerFXState>
local active_fx = {}

---@class PaleWatcherFlashState
---@field id integer HUD element ID
---@field timer number Remaining flash duration in seconds

---@type table<string, PaleWatcherFlashState>
local active_flashes = {}

local FLASH_DURATION = 0.65 -- Total flash duration in seconds
local FLASH_PEAK = 0.08     -- Full-brightness blinding peak before fade begins

local function get_static_texture(intensity, time)
	if intensity <= 0.01 then return "" end
	local frame = (math.floor(time * 15) % 3) + 1
	-- Cap maximum static opacity to ~41% (alpha 105) so terrain, trees, and notes remain legible in the dark
	local alpha = math.min(105, math.floor(intensity * 105))
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

		-- Dread Drag: Exponential movement slowdown & tunnel vision within 8m proximity
		local slow_factor
		local fov_factor
		if distance <= 8.0 then
			-- Heavy psychic drag: drops sharply from 0.45 down to 0.15 at 3.5m
			local dread_t = math.max(0.0, math.min(1.0, (distance - 3.5) / 4.5))
			slow_factor = 0.15 + (dread_t * 0.30)
			fov_factor = 0.45 + (dread_t * 0.15)
		else
			-- Standard medium-range gaze slow (0.70 down to 0.45 at 8m)
			local gaze_t = math.max(0.0, math.min(1.0, (distance - 8.0) / 16.0))
			slow_factor = 0.45 + (gaze_t * 0.25)
			fov_factor = 0.60 + (gaze_t * 0.25)
		end
		player:set_fov(fov_factor, true, 0.25)
		pale_watcher.physics.apply_gaze_slow(player, slow_factor)

		-- Sanity & Health drain (accelerates under 8m dread drag)
		if distance <= 20.0 then
			local drain_interval = (distance <= 8.0) and 0.75 or 1.0
			state._drain_acc = (state._drain_acc or 0) + dtime
			if state._drain_acc >= drain_interval then
				state._drain_acc = 0
				local cur_hp = player:get_hp()
				if cur_hp > 1 then
					player:set_hp(cur_hp - 1, "pale_watcher:gaze_drain")
					core.sound_play("pale_watcher_static", {
						to_player = name,
						gain = (distance <= 8.0) and 0.6 or 0.4,
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
		-- 1. Responsive Vignette (rendered on top of static noise)
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
				z_index = -2, -- Above static noise (-3) so dark border frames the view
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
				z_index = -3, -- Below vignette (-2)
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

---Triggers full-screen camera flash effect for a player with smooth quadratic opacity fade-out.
---@param player ObjectRef
function pale_watcher.fx.trigger_flash(player)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local flash = active_flashes[name]

	if flash then
		-- Re-burst existing flash: reset timer and immediately restore peak opacity
		flash.timer = FLASH_DURATION
		player:hud_change(flash.id, "text", "pale_watcher_hud_flash.png^[opacity:255")
	else
		local id = player:hud_add({
			hud_elem_type = "image",
			position = {x = 0.5, y = 0.5},
			name = "pale_watcher_flash",
			scale = {x = -100, y = -100},
			text = "pale_watcher_hud_flash.png^[opacity:255",
			alignment = {x = 0, y = 0},
			z_index = 100,
		})
		active_flashes[name] = {
			id = id,
			timer = FLASH_DURATION,
		}
	end

	-- Fail-safe timer to guarantee removal if server steps are interrupted
	core.after(FLASH_DURATION + 0.15, function()
		local f = active_flashes[name]
		if f and f.timer <= 0.05 then
			if player:is_player() then
				player:hud_remove(f.id)
			end
			active_flashes[name] = nil
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

	-- Clean up camera flash
	local flash = active_flashes[name]
	if flash then
		player:hud_remove(flash.id)
		active_flashes[name] = nil
	end

	-- Clean up horror mob FX
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
end

---Cleans up all active effects across all players.
function pale_watcher.fx.clear_all()
	for name, flash in pairs(active_flashes) do
		local player = core.get_player_by_name(name)
		if player then
			player:hud_remove(flash.id)
		end
	end
	active_flashes = {}

	for name, _ in pairs(active_fx) do
		local player = core.get_player_by_name(name)
		if player then
			pale_watcher.fx.clear_player(player)
		end
	end
	active_fx = {}
end

-- Globalstep decay for camera flash and horror effects
core.register_globalstep(function(dtime)
	-- 1. Camera flash decay with smooth quadratic ease-out opacity transition
	if next(active_flashes) then
		local fade_window = FLASH_DURATION - FLASH_PEAK
		for name, flash in pairs(active_flashes) do
			flash.timer = flash.timer - dtime
			local player = core.get_player_by_name(name)

			if flash.timer > 0 and player then
				local alpha
				if flash.timer >= fade_window then
					alpha = 255
				else
					local progress = math.max(0, flash.timer / fade_window)
					-- Quadratic ease-out curve for natural camera phosphor fade
					alpha = math.floor(255 * (progress * progress))
				end
				player:hud_change(flash.id, "text",
					string.format("pale_watcher_hud_flash.png^[opacity:%d", alpha))
			else
				if player then
					player:hud_remove(flash.id)
				end
				active_flashes[name] = nil
			end
		end
	end

	-- 2. Horror mob static decay
	if next(active_fx) then
		for name, state in pairs(active_fx) do
			local player = core.get_player_by_name(name)

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

			-- Prune player from active_fx only when all horror effects are idle
			local is_busy = (state.intensity > 0.02)
				or (state.hud_vignette_id ~= nil)
				or (state.hud_static_id ~= nil)
				or state.fog_active
				or state.is_gazing
				or (state.sound_handle ~= nil)

			if not is_busy then
				active_fx[name] = nil
			end
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

return pale_watcher.fx
