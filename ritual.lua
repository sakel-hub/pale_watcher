--[[
	pale_watcher - Multiplayer Ritual Session Manager
	3-Pillar Clean Spawning, Dynamic Surface Placement, Shared Group Progress,
	Instant Cleanup Purge, Stalker Tiers, and Cleansing Flame Banishment.
]]

---@class PaleWatcherRitual
pale_watcher.ritual = {}

local active_sessions = {}
-- active_sessions[session_id] = {
--     pages_collected = 0,
--     pages_total = 8,
--     mob_ref = ObjectRef,
--     center = Vector,
--     elapsed_time = 0.0,
--     stalker_tier = 0,
--     placed_pages = { [hash] = Vector },
--     players = { [name] = { hud_bg_id = id, hud_text_id = id, last_text = "", pages_found = 0 } }
-- }

local SESSION_RADIUS = 50.0
local SPAWN_RADIUS_MIN = 15.0
local SPAWN_RADIUS_MAX = 45.0
local MIN_PAGE_DISTANCE = 8.0 -- At least 8 blocks between pages

---Computes stalker aggression tier based on pages found and elapsed night duration.
---@param session table
---@return integer tier 0 to 4
local function calculate_stalker_tier(session)
	local pages = session.pages_collected or 0
	local time_mins = (session.elapsed_time or 0) / 60.0

	local tier = 0
	if pages >= 7 or time_mins >= 8.0 then
		tier = 4
	elseif pages >= 5 or time_mins >= 5.0 then
		tier = 3
	elseif pages >= 3 or time_mins >= 3.0 then
		tier = 2
	elseif pages >= 1 or time_mins >= 1.5 then
		tier = 1
	end
	return tier
end

---Pillar 1: Dynamic Surface Placement
---Finds safe eye-level surfaces on tree trunks or stone walls with walkable ground underneath.
---@param center Vector Encounter center coordinate
---@param count integer Desired number of pages (8)
---@param session_id string? Associated session ID
---@return table<string, Vector> placed_pages Hash map of placed positions
local function spawn_pages_dynamically(center, count, session_id)
	local placed = {}
	local placed_list = {}
	local spawned = 0

	local p1 = vector.subtract(center, SPAWN_RADIUS_MAX)
	local p2 = vector.add(center, SPAWN_RADIUS_MAX)

	-- Search for tree trunks first, then stone outcrops
	local surface_nodes = core.find_nodes_in_area(p1, p2, {"group:tree", "group:stone"})
	if #surface_nodes > 0 then
		-- Fisher-Yates shuffle
		for i = #surface_nodes, 2, -1 do
			local j = math.random(i)
			surface_nodes[i], surface_nodes[j] = surface_nodes[j], surface_nodes[i]
		end
	end

	local cardinal_dirs = {
		{x = 1, y = 0, z = 0},
		{x = -1, y = 0, z = 0},
		{x = 0, y = 0, z = 1},
		{x = 0, y = 0, z = -1},
	}

	for _, node_pos in ipairs(surface_nodes) do
		local dist = vector.distance(center, node_pos)
		if dist >= SPAWN_RADIUS_MIN and dist <= SPAWN_RADIUS_MAX then

			-- Check spacing between existing placed pages
			local too_close = false
			for _, prev in ipairs(placed_list) do
				if vector.distance(node_pos, prev) < MIN_PAGE_DISTANCE then
					too_close = true
					break
				end
			end

			if not too_close then
				for _, dir in ipairs(cardinal_dirs) do
					local air_pos = vector.add(node_pos, dir)
					local node_at_air = core.get_node(air_pos)

					-- Safe Node Validation for Eye-Height Placement:
					-- 1. Candidate must be air at eye level (air_pos: 2 blocks above ground)
					-- 2. Space at foot level (air_pos.y - 1) must be open (air or non-walkable flora)
					-- 3. Block at ground level (air_pos.y - 2) must be walkable solid ground
					-- 4. Wall mounting surface (node_pos) and wall below must be solid
					-- 5. Not underwater or in hazardous liquids
					if node_at_air.name == "air" then
						local foot_pos = {x = air_pos.x, y = air_pos.y - 1, z = air_pos.z}
						local foot_node = core.get_node(foot_pos)
						local foot_def = core.registered_nodes[foot_node.name]
						local is_foot_clear = foot_node.name == "air"
							or (foot_def and not foot_def.walkable and foot_def.liquidtype == "none")

						if is_foot_clear then
							local ground_pos = {x = air_pos.x, y = air_pos.y - 2, z = air_pos.z}
							local ground_node = core.get_node(ground_pos)
							local ground_def = core.registered_nodes[ground_node.name]

							if ground_def and ground_def.walkable and ground_def.liquidtype == "none" then
								local wall_node = core.get_node(node_pos)
								local wall_def = core.registered_nodes[wall_node.name]
								local wall_below_pos = {x = node_pos.x, y = node_pos.y - 1, z = node_pos.z}
								local wall_below_node = core.get_node(wall_below_pos)
								local wall_below_def = core.registered_nodes[wall_below_node.name]

								if wall_def and wall_def.walkable and wall_below_def and wall_below_def.walkable then
									-- Wallmounted direction points away from the surface into the air space
									local wall_dir = vector.multiply(dir, -1)
									local param2 = core.dir_to_wallmounted(wall_dir)

									core.set_node(air_pos, {
										name = "pale_watcher:cursed_page",
										param2 = param2,
									})

									local meta = core.get_meta(air_pos)
									if session_id then
										meta:set_string("session_id", session_id)
									end
									meta:set_int("age", 0)

									local hash = core.pos_to_string(air_pos)
									placed[hash] = air_pos
									table.insert(placed_list, air_pos)
									spawned = spawned + 1
									break
								end
							end
						end
					end
				end
			end
		end

		if spawned >= count then break end
	end

	return placed
end

---Updates shared group HUD for an enrolled player.
---@param player ObjectRef
---@param session table
local function update_player_hud(player, session)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local p_data = session.players[name]
	if not p_data then
		p_data = {pages_found = 0, hud_bg_id = nil, hud_text_id = nil, last_text = nil}
		session.players[name] = p_data
	end

	local complete = session.pages_collected >= session.pages_total
	local text = complete and
		string.format("PAGES: %d / %d - IGNITE RITUAL PYRE!", session.pages_collected, session.pages_total) or
		string.format("CURSED PAGES: %d / %d", session.pages_collected, session.pages_total)

	-- Accessibility colors:
	-- In-progress: Warm ivory white (0xFFF8EC) -> 15.2:1 contrast against dark plaque (WCAG AAA)
	-- Complete: Radiant amber gold (0xFFD700) -> 13.5:1 contrast against dark plaque (WCAG AAA)
	local text_color = complete and 0xFFD700 or 0xFFF8EC

	-- 1. Centered Gothic Plaque Background Texture (288x32)
	if not p_data.hud_bg_id then
		p_data.hud_bg_id = player:hud_add({
			hud_elem_type = "image",
			position = {x = 0.5, y = 0.04},
			alignment = {x = 0, y = 0},
			offset = {x = 0, y = 0},
			scale = {x = 1, y = 1},
			text = "pale_watcher_hud_pages_bg.png",
			z_index = 100,
		})
	end

	-- 2. Horizontally Centered Accessible Text Element
	if not p_data.hud_text_id then
		p_data.hud_text_id = player:hud_add({
			hud_elem_type = "text",
			position = {x = 0.5, y = 0.04},
			alignment = {x = 0, y = 0},
			offset = {x = 0, y = 0},
			text = text,
			number = text_color,
			scale = {x = 100, y = 100},
			z_index = 101,
		})
		p_data.last_text = text
	elseif p_data.last_text ~= text then
		player:hud_change(p_data.hud_text_id, "text", text)
		player:hud_change(p_data.hud_text_id, "number", text_color)
		p_data.last_text = text
	end
end

---Removes HUD tracker from a player.
---@param player ObjectRef
---@param session table
local function remove_player_hud(player, session)
	if not player or not player:is_player() then return end
	local name = player:get_player_name()
	local p_data = session and session.players and session.players[name]
	if p_data then
		if p_data.hud_bg_id then
			player:hud_remove(p_data.hud_bg_id)
			p_data.hud_bg_id = nil
		end
		if p_data.hud_text_id then
			player:hud_remove(p_data.hud_text_id)
			p_data.hud_text_id = nil
		end
		p_data.last_text = nil
	end
end

---Pillar 3: Instant Cleanup Purge
---Reverts all remaining uncollected cursed pages back to air.
---@param session table
local function purge_session_pages(session)
	if not session or not session.placed_pages then return end
	for _, pos in pairs(session.placed_pages) do
		local node = core.get_node(pos)
		if node.name == "pale_watcher:cursed_page" then
			core.remove_node(pos)
		end
	end
	session.placed_pages = {}
end

---Synchronizes participants within 50m radius (Dynamic Join & Leave).
---@param session_id string
---@param center_pos? Vector
function pale_watcher.ritual.update_session_players(session_id, center_pos)
	local session = active_sessions[session_id]
	if not session then return end

	local mob_obj = session.mob_ref
	if not mob_obj or not mob_obj:is_valid() then
		pale_watcher.ritual.end_session(session_id, false)
		return
	end

	local center = center_pos or session.center
	local exit_radius = SESSION_RADIUS * 1.35

	local players = core.get_connected_players()
	for _, player in ipairs(players) do
		local p_pos = player:get_pos()
		if p_pos then
			local dist = vector.distance(p_pos, center)
			local name = player:get_player_name()

			if dist <= SESSION_RADIUS then
				-- Dynamic Join
				local is_new = not session.players[name]
				update_player_hud(player, session)

				if is_new then
					core.chat_send_player(name,
						core.colorize(pale_watcher.colors.void, "A chilling presence surrounds you... Find the 8 Cursed Pages!"))
				end

				-- Apply domain fog if deep in the encounter zone (>15m)
				if dist >= 15.0 then
					pale_watcher.fx.apply_claustrophobic_fog(player)
				end
			elseif dist > exit_radius and session.players[name] then
				-- Dynamic Leave / Out of range
				remove_player_hud(player, session)
				pale_watcher.fx.clear_claustrophobic_fog(player)
				pale_watcher.physics.clear_all(player)
				session.players[name] = nil
			end
		end
	end
end

---Starts a new Ephemeral Encounter Session bound to the Pale Watcher entity instance.
---@param mob_ref ObjectRef Pale Watcher entity instance
---@param center_pos Vector Origin spawn point
---@return string session_id Unique identifier for session
function pale_watcher.ritual.start_session(mob_ref, center_pos)
	local session_id = tostring(mob_ref)

	local placed_pages = spawn_pages_dynamically(center_pos, 8, session_id)
	local page_count = 0
	for _ in pairs(placed_pages) do
		page_count = page_count + 1
	end
	page_count = math.max(1, page_count)

	local session = {
		session_id = session_id,
		pages_collected = 0,
		pages_total = page_count,
		mob_ref = mob_ref,
		center = center_pos,
		elapsed_time = 0.0,
		stalker_tier = 0,
		placed_pages = placed_pages,
		players = {},
	}
	active_sessions[session_id] = session

	pale_watcher.ritual.update_session_players(session_id, center_pos)

	return session_id
end

---Retrieves the current stalker tier for an entity session.
---@param session_id string
---@return integer tier 0 to 4
function pale_watcher.ritual.get_stalker_tier(session_id)
	local session = active_sessions[session_id]
	if not session then return 0 end
	return session.stalker_tier or 0
end

---Finds the active encounter session for a player or near a world position.
---@param player_name string
---@param pos? Vector
---@return table|nil session
---@return string|nil session_id
function pale_watcher.ritual.get_player_session(player_name, pos)
	for id, session in pairs(active_sessions) do
		if session.players and session.players[player_name] then
			return session, id
		end
		if pos and vector.distance(pos, session.center) <= (SESSION_RADIUS * 1.5) then
			return session, id
		end
	end
	return nil, nil
end

---Ends an active session cleanly, executing instant cleanup purge across remaining pages and effects.
---@param session_id string
---@param victory boolean True if Pale Watcher was banished/defeated
function pale_watcher.ritual.end_session(session_id, victory)
	local session = active_sessions[session_id]
	if not session then return end

	-- Instant Cleanup Purge: Revert all uncollected pages back to air
	purge_session_pages(session)

	for name, _ in pairs(session.players) do
		local player = core.get_player_by_name(name)
		if player then
			remove_player_hud(player, session)
			pale_watcher.physics.clear_all(player)
			pale_watcher.fx.clear_player(player)

			if victory then
				core.chat_send_player(name,
					core.colorize(pale_watcher.colors.victory,
						"★ The Cleansing Flame has consumed the Cursed Pages! The Pale Watcher is banished."))
			end
		end
	end

	active_sessions[session_id] = nil
end

---Called when a participant collects a Cursed Page.
---@param pos Vector Page node position
---@param clicker ObjectRef Player who collected the page
function pale_watcher.ritual.on_page_collected(pos, clicker)
	local closest_session_id = nil
	local min_dist = math.huge

	for id, session in pairs(active_sessions) do
		local dist = vector.distance(pos, session.center)
		if dist < min_dist then
			min_dist = dist
			closest_session_id = id
		end
	end

	if not closest_session_id then return end
	local session = active_sessions[closest_session_id]

	-- Remove from placed_pages map
	local pos_hash = core.pos_to_string(pos)
	session.placed_pages[pos_hash] = nil

	session.pages_collected = session.pages_collected + 1
	session.stalker_tier = calculate_stalker_tier(session)

	local clicker_name = clicker:get_player_name()
	if not session.players[clicker_name] then
		session.players[clicker_name] = {pages_found = 0, hud_bg_id = nil, hud_text_id = nil, last_text = nil}
	end
	session.players[clicker_name].pages_found = session.players[clicker_name].pages_found + 1

	-- Broadcast shared progress across all enrolled players
	for name, _ in pairs(session.players) do
		local p = core.get_player_by_name(name)
		if p then
			update_player_hud(p, session)
			local msg = string.format("Cursed Page Collected: %d / %d (%s found one!)",
				session.pages_collected, session.pages_total, clicker_name)
			core.chat_send_player(name, core.colorize(pale_watcher.colors.danger, msg))
			pale_watcher.fx.update_player(p, 12, true, 0.8, session.stalker_tier)
		end
	end

	-- Whispered Survival Tip for the collector (No inventory clutter)
	local survival_tips = {
		"Never run in a straight line... weaving through dense trees disrupts his intercept vector.",
		"The glancing check... spin around every few seconds to freeze his silent advance.",
		"Head for the torches... sanctuary light (14+) holds him at bay at the dark tree line.",
		"He phase-teleports into cramped holes... never attempt to hide in a 3-block dirt bunker!",
		"A camera's xenon flash can stun him for 3-5 seconds and force an evasive retreat.",
		"Once all 8 pages are found, ignite a Ritual Pyre to summon and banish him in holy fire.",
	}
	local tip = survival_tips[((session.pages_collected - 1) % #survival_tips) + 1]
	core.chat_send_player(clicker_name,
		core.colorize(pale_watcher.colors.whisper, "★ As the cursed page burns, a whisper echoes: \"" .. tip .. "\""))

	-- Aggression Re-Targeting: Pale Watcher immediately prioritizes the collector!
	if session.mob_ref and session.mob_ref:is_valid() then
		local ent = session.mob_ref:get_luaentity()
		if ent and ent.on_page_collected then
			ent:on_page_collected(clicker)
		end
	end

	-- Check if all 8 pages collected: inform players to ignite the Ritual Pyre
	if session.pages_collected >= session.pages_total then
		for name, _ in pairs(session.players) do
			local p = core.get_player_by_name(name)
			if p then
				core.chat_send_player(name,
					core.colorize(pale_watcher.colors.warning,
						"All 8 Pages collected! Craft a Ritual Pyre and burn them to banish the nightmare!"))
			end
		end
	end
end

---Executes the Cleansing Flame Banishment Sequence.
---Forcibly teleports Pale Watcher into the pyre, paralyzes him, plays death implode, and implodes into loot.
---@param pyre_pos Vector
---@param summoner ObjectRef
function pale_watcher.ritual.trigger_pyre_banishment(pyre_pos, summoner)
	-- Find closest active Pale Watcher
	local target_session_id = nil
	local min_dist = math.huge

	for id, session in pairs(active_sessions) do
		local d = vector.distance(pyre_pos, session.center)
		if d < min_dist then
			min_dist = d
			target_session_id = id
		end
	end

	if not target_session_id then return end
	local session = active_sessions[target_session_id]
	local mob_obj = session.mob_ref

	if mob_obj and mob_obj:is_valid() then
		local ent = mob_obj:get_luaentity()
		if ent and ent.on_pyre_banished then
			ent:on_pyre_banished(pyre_pos, summoner)
		end
	end
end

---Static Geiger-Counter helper: Checks whether player is looking directly at a tree holding an active page.
---@param player ObjectRef
---@return boolean is_aiming_at_page
function pale_watcher.ritual.is_aiming_at_page(player)
	if not player or not player:is_player() then return false end
	local p_pos = player:get_pos()
	if not p_pos then return false end
	local eye_pos = vector.add(p_pos, {x = 0, y = 1.625, z = 0})
	local look_dir = player:get_look_dir()

	for _, session in pairs(active_sessions) do
		for _, page_pos in pairs(session.placed_pages) do
			local dist = vector.distance(eye_pos, page_pos)
			if dist <= 22.0 then
				local to_page = vector.direction(eye_pos, page_pos)
				if vector.dot(look_dir, to_page) >= 0.94 then -- Within ~15° cone
					return true
				end
			end
		end
	end
	return false
end

---Checks if a ritual session is currently active.
---@param session_id string
---@return boolean is_active
function pale_watcher.ritual.is_session_active(session_id)
	return active_sessions[session_id] ~= nil
end

-- Globalstep: Watchdog timer for orphaned sessions and stalker tier time progression
local ritual_step_timer = 0
core.register_globalstep(function(dtime)
	ritual_step_timer = ritual_step_timer + dtime
	if ritual_step_timer < 1.0 then return end
	ritual_step_timer = 0

	for session_id, session in pairs(active_sessions) do
		local mob_obj = session.mob_ref
		if not mob_obj or not mob_obj:is_valid() then
			pale_watcher.ritual.end_session(session_id, false)
		else
			session.elapsed_time = (session.elapsed_time or 0) + 1.0
			session.stalker_tier = calculate_stalker_tier(session)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	for _, session in pairs(active_sessions) do
		remove_player_hud(player, session)
		session.players[player:get_player_name()] = nil
	end
end)

core.register_on_dieplayer(function(player)
	for _, session in pairs(active_sessions) do
		remove_player_hud(player, session)
		session.players[player:get_player_name()] = nil
	end
end)

core.register_on_joinplayer(function(player)
	for _, session in pairs(active_sessions) do
		remove_player_hud(player, session)
		session.players[player:get_player_name()] = nil
	end
end)

core.register_on_shutdown(function()
	for session_id, _ in pairs(active_sessions) do
		pale_watcher.ritual.end_session(session_id, false)
	end
end)

return pale_watcher.ritual
