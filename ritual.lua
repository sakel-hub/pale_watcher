--[[
	pale_watcher - Multiplayer Ritual Session Manager
	Dynamic Player Scaling, Surface Placement, Shared Group Progress,
	Surplus Page Mercy Rule, Stalker Tiers, and Cleansing Flame Banishment.
]]

pale_watcher.ritual = pale_watcher.ritual or {}

local active_sessions = {}
-- active_sessions[session_id] = {
--     session_id = string,
--     pages_collected = 0,
--     pages_total = 5,
--     mob_ref = ObjectRef,
--     center = Vector,
--     elapsed_time = 0.0,
--     stalker_tier = 0,
--     placed_pages = { [hash] = Vector },
--     players = { [name] = { hud_bg_id = id, hud_text_id = id, last_text = "", last_bg = "", pages_found = 0 } },
--     departed_players = { [name] = number },
--     orphan_timer = number,
-- }

pale_watcher.ritual.SESSION_RADIUS = 85.0
pale_watcher.ritual.SESSION_EXIT_RADIUS = 120.0
pale_watcher.ritual.SESSION_COMPLETE_EXIT_RADIUS = 160.0

local SESSION_RADIUS = pale_watcher.ritual.SESSION_RADIUS
local SESSION_EXIT_RADIUS = pale_watcher.ritual.SESSION_EXIT_RADIUS
local SESSION_COMPLETE_EXIT_RADIUS = pale_watcher.ritual.SESSION_COMPLETE_EXIT_RADIUS
local SPAWN_RADIUS_MIN = 15.0
local SPAWN_RADIUS_MAX = 45.0
local MIN_PAGE_DISTANCE = 8.0 -- Primary spacing between pages

---Calculates target cursed page count dynamically scaled by active player count.
---Solo = 5, Duo = 8, Trio = 11, Squad (4+) = 14.
---@param player_count integer Number of active participating players
---@return integer target_pages
local function calculate_target_pages(player_count)
	local count = math.max(1, player_count or 1)
	return math.min(14, 5 + (count - 1) * 3)
end

---Computes stalker aggression tier dynamically based on percentage of pages found and elapsed encounter duration.
---@param session table
---@return integer tier 0 to 4
local function calculate_stalker_tier(session)
	local pages = session.pages_collected or 0
	local total = session.pages_total or 8
	local time_mins = (session.elapsed_time or 0) / 60.0

	local tier = 0
	local ratio = total > 0 and (pages / total) or 0
	if (pages >= (total - 1) and pages > 0) or ratio >= 0.85 or time_mins >= 8.0 then
		tier = 4
	elseif ratio >= 0.60 or time_mins >= 5.0 then
		tier = 3
	elseif ratio >= 0.35 or time_mins >= 3.0 then
		tier = 2
	elseif pages >= 1 or time_mins >= 1.5 then
		tier = 1
	end
	return tier
end

---Dynamic Surface Placement: Finds safe eye-level surfaces on tree trunks or stone walls.
---Ensures walkable solid ground underneath each placed page.
---@param center Vector Encounter center coordinate
---@param count integer Desired number of pages to manifest
---@param session_id string? Associated session ID
---@param existing_placed table<string, Vector>? Existing placed pages to maintain minimum distance from
---@return table<string, Vector> placed_pages Hash map of newly placed positions
local function spawn_pages_dynamically(center, count, session_id, existing_placed)
	local placed = {}
	local placed_list = {}
	if existing_placed then
		for _, pos in pairs(existing_placed) do
			table.insert(placed_list, pos)
		end
	end
	local spawned = 0

	local p1 = {x = center.x - SPAWN_RADIUS_MAX, y = center.y - 10, z = center.z - SPAWN_RADIUS_MAX}
	local p2 = {x = center.x + SPAWN_RADIUS_MAX, y = center.y + 16, z = center.z + SPAWN_RADIUS_MAX}

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

	-- Primary pass: strict distance spacing (MIN_PAGE_DISTANCE = 8.0)
	for _, node_pos in ipairs(surface_nodes) do
		local dist = vector.distance(center, node_pos)
		if dist >= SPAWN_RADIUS_MIN and dist <= SPAWN_RADIUS_MAX then
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

	-- Secondary fallback pass with reduced spacing (5.0m) if dense page quota in small groves
	if spawned < count and #surface_nodes > 0 then
		for _, node_pos in ipairs(surface_nodes) do
			local dist = vector.distance(center, node_pos)
			if dist >= SPAWN_RADIUS_MIN and dist <= SPAWN_RADIUS_MAX then
				local too_close = false
				for _, prev in ipairs(placed_list) do
					if vector.distance(node_pos, prev) < 5.0 then
						too_close = true
						break
					end
				end

				if not too_close then
					for _, dir in ipairs(cardinal_dirs) do
						local air_pos = vector.add(node_pos, dir)
						local node_at_air = core.get_node(air_pos)

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
		p_data = {pages_found = 0, hud_bg_id = nil, hud_text_id = nil, last_text = nil, last_bg = nil}
		session.players[name] = p_data
	end

	local complete = session.pages_collected >= session.pages_total
	local raw_text = complete and
		string.format("PAGES: %d / %d — IGNITE RITUAL PYRE!", session.pages_collected, session.pages_total) or
		string.format("CURSED PAGES: %d / %d", session.pages_collected, session.pages_total)

	-- Direct string colorization guarantees vibrant visual formatting across all font backends
	local display_text = complete and
		core.colorize(pale_watcher.colors.warning, "★ " .. raw_text .. " ★") or
		core.colorize("#FFF8EC", raw_text)

	local text_color = complete and 0xFFD700 or 0xFFF8EC
	local bg_texture = complete and "pale_watcher_hud_pages_bg_active.png" or "pale_watcher_hud_pages_bg.png"

	-- Centered Gothic Plaque Background (384x32) with golden active highlight
	if not p_data.hud_bg_id then
		p_data.hud_bg_id = player:hud_add({
			type = "image",
			position = {x = 0.5, y = 0.04},
			alignment = {x = 0, y = 0},
			offset = {x = 0, y = 0},
			scale = {x = 1, y = 1},
			text = bg_texture,
			z_index = 100,
		})
		p_data.last_bg = bg_texture
	elseif p_data.last_bg ~= bg_texture then
		player:hud_change(p_data.hud_bg_id, "text", bg_texture)
		p_data.last_bg = bg_texture
	end

	-- Horizontally Centered Accessible Text Element
	if not p_data.hud_text_id then
		p_data.hud_text_id = player:hud_add({
			type = "text",
			position = {x = 0.5, y = 0.04},
			alignment = {x = 0, y = 0},
			offset = {x = 0, y = 0},
			text = display_text,
			number = text_color,
			scale = {x = 100, y = 100},
			z_index = 101,
		})
		p_data.last_text = display_text
	elseif p_data.last_text ~= display_text then
		player:hud_change(p_data.hud_text_id, "text", display_text)
		player:hud_change(p_data.hud_text_id, "number", text_color)
		p_data.last_text = display_text
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
		p_data.last_bg = nil
	end
end

---Instant Cleanup Purge: Reverts all remaining uncollected cursed pages back to air.
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

---Counts active participating players in a session who are alive, connected, and not in grace period.
---@param session table
---@return integer count
local function get_active_player_count(session)
	local count = 0
	for name, _ in pairs(session.players) do
		if not (session.departed_players and session.departed_players[name]) then
			local player = core.get_player_by_name(name)
			if player and x_mob_core.is_player_alive(player) then
				count = count + 1
			end
		end
	end
	return count
end

---Synchronizes participants within encounter radius (Dynamic Join & Leave with Grace Period).
---@param session_id string
---@param center_pos? Vector
function pale_watcher.ritual.update_session_players(session_id, center_pos)
	local session = active_sessions[session_id]
	if not session then return end

	local mob_obj = session.mob_ref
	if mob_obj and not mob_obj:is_valid() then
		session.mob_ref = nil
		mob_obj = nil
	end

	local center = session.center or center_pos
	local mob_pos = center_pos or (mob_obj and mob_obj:get_pos())
	local complete = (session.pages_collected >= session.pages_total)
	local join_radius = complete and (SESSION_RADIUS * 1.5) or SESSION_RADIUS
	local exit_radius = complete and SESSION_COMPLETE_EXIT_RADIUS or SESSION_EXIT_RADIUS

	session.departed_players = session.departed_players or {}

	local players = core.get_connected_players()
	for _, player in ipairs(players) do
		local p_pos = player:get_pos()
		if p_pos then
			local dist_center = center and vector.distance(p_pos, center) or 9999
			local dist_mob = mob_pos and vector.distance(p_pos, mob_pos) or 9999
			local dist = math.min(dist_center, dist_mob)
			local name = player:get_player_name()
			local is_enrolled = (session.players and session.players[name] ~= nil)

			-- Mutual exclusivity: Do not enroll players who are actively participating in another session
			local enrolled_elsewhere = false
			if not is_enrolled then
				for other_id, other_session in pairs(active_sessions) do
					if other_id ~= session_id and other_session.players and other_session.players[name] then
						enrolled_elsewhere = true
						break
					end
				end
			end

			local in_bounds = not enrolled_elsewhere and (is_enrolled and (dist <= exit_radius) or (dist <= join_radius))

			if in_bounds and x_mob_core.is_player_alive(player) then
				-- Check if player was returning from grace period
				local was_in_grace = (session.departed_players[name] ~= nil)
				if was_in_grace then
					session.departed_players[name] = nil
					core.chat_send_player(name,
						core.colorize(pale_watcher.colors.whisper,
							"★ You step back into the cursed mist... The ritual claims you once more."))
				end

				local is_new = not is_enrolled
				if is_new then
					session.players[name] = {
						pages_found = 0,
						hud_bg_id = nil,
						hud_text_id = nil,
						last_text = nil,
						last_bg = nil,
					}

					-- Dynamic Scaling Up: If ritual is in progress, scale required pages for additional players
					if not complete then
						local active_count = get_active_player_count(session)
						local new_target = calculate_target_pages(active_count)
						if new_target > session.pages_total then
							local delta = new_target - session.pages_total
							local newly_placed = spawn_pages_dynamically(center, delta, session_id, session.placed_pages)
							local spawned_count = 0
							for hash, p in pairs(newly_placed) do
								session.placed_pages[hash] = p
								spawned_count = spawned_count + 1
							end

							if spawned_count > 0 then
								session.pages_total = session.pages_total + spawned_count
								session.stalker_tier = calculate_stalker_tier(session)

								local expand_msg = string.format(
									"★ The anomaly expands... %d additional cursed pages manifest in the dark woods! (%d total) ★",
									spawned_count, session.pages_total)
								for pname, _ in pairs(session.players) do
									core.chat_send_player(pname, core.colorize(pale_watcher.colors.danger, expand_msg))
								end
								core.sound_play("pale_watcher_page_whisper", {pos = center, gain = 0.8, max_hear_distance = 60}, true)

								-- Synchronously refresh all enrolled players' HUDs with the new total
								for pname, _ in pairs(session.players) do
									local p_obj = core.get_player_by_name(pname)
									if p_obj then
										update_player_hud(p_obj, session)
									end
								end
							end
						end
					end

					local join_msg = complete and
						"The nightmare reaches its climax... Ignite the Ritual Pyre to banish him!" or
						string.format("A chilling presence surrounds you... Find the %d Cursed Pages!", session.pages_total)
					core.chat_send_player(name, core.colorize(pale_watcher.colors.void, join_msg))
				end

				-- Ensure this player's HUD is updated
				update_player_hud(player, session)

				-- Apply atmospheric domain fog to all enrolled encounter participants
				pale_watcher.fx.apply_claustrophobic_fog(player)
			elseif dist > exit_radius and session.players[name] then
				-- Player moved outside encounter zone: start 20s departure grace
				if not session.departed_players[name] then
					remove_player_hud(player, session)
					pale_watcher.fx.clear_claustrophobic_fog(player)
					pale_watcher.physics.clear_all(player)
					session.departed_players[name] = 20.0
					core.chat_send_player(name,
						core.colorize(pale_watcher.colors.dimmed,
							"★ You have retreated from the cursed mist. Return within 20s or your tether to the ritual will sever."))
				end
			end
		end
	end
end

---Rebinds a newly loaded or restored mob entity to an existing active session.
---@param session_id string
---@param mob_ref ObjectRef
---@return Vector|nil center
function pale_watcher.ritual.rebind_mob(session_id, mob_ref)
	local session = active_sessions[session_id]
	if session then
		session.mob_ref = mob_ref
		return session.center
	end
	return nil
end

---Retrieves the origin center coordinates of an active encounter session.
---@param session_id string
---@return Vector|nil center
function pale_watcher.ritual.get_session_center(session_id)
	local session = active_sessions[session_id]
	return session and session.center
end

---Starts a new Ephemeral Encounter Session bound to the Pale Watcher entity instance.
---@param mob_ref ObjectRef Pale Watcher entity instance
---@param center_pos Vector Origin spawn point
---@return string session_id Unique identifier for session
function pale_watcher.ritual.start_session(mob_ref, center_pos)
	-- Deduplicate: Check if an active encounter session already exists in this area
	for sid, session in pairs(active_sessions) do
		if session.center and vector.distance(center_pos, session.center) <= (SESSION_RADIUS * 1.5) then
			if mob_ref and mob_ref:is_valid() and (not session.mob_ref or not session.mob_ref:is_valid()) then
				session.mob_ref = mob_ref
			end
			return sid
		end
	end

	-- Count alive players within encounter radius at spawn time
	local initial_count = 0
	local players = core.get_connected_players()
	for _, player in ipairs(players) do
		if x_mob_core.is_player_alive(player) then
			local p_pos = player:get_pos()
			if p_pos and vector.distance(p_pos, center_pos) <= SESSION_RADIUS then
				-- If player is already enrolled in an active session, reuse that session
				local p_name = player:get_player_name()
				for sid, session in pairs(active_sessions) do
					if session.players and session.players[p_name] then
						if mob_ref and mob_ref:is_valid() and (not session.mob_ref or not session.mob_ref:is_valid()) then
							session.mob_ref = mob_ref
						end
						return sid
					end
				end
				initial_count = initial_count + 1
			end
		end
	end
	if initial_count < 1 then
		initial_count = 1
	end

	local session_id = x_mob_core.generate_uuid()

	local target_pages = calculate_target_pages(initial_count)
	local placed_pages = spawn_pages_dynamically(center_pos, target_pages, session_id)
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
		departed_players = {},
	}
	active_sessions[session_id] = session

	pale_watcher.ritual.update_session_players(session_id, center_pos)
	x_mob_core.emit("pale_watcher:session_started", session_id, center_pos, page_count)

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

---Checks if a player is currently an enrolled participant in a session.
---@param session_id string
---@param player_name string
---@return boolean is_enrolled
function pale_watcher.ritual.is_player_enrolled(session_id, player_name)
	local session = active_sessions[session_id]
	if not session or not session.players then return false end
	return session.players[player_name] ~= nil
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

	x_mob_core.emit("pale_watcher:session_ended", session_id, victory)

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
	if session.pages_collected > session.pages_total then
		session.pages_total = session.pages_collected
	end
	session.stalker_tier = calculate_stalker_tier(session)

	local clicker_name = clicker:get_player_name()
	if not session.players[clicker_name] then
		session.players[clicker_name] = {
			pages_found = 0,
			hud_bg_id = nil,
			hud_text_id = nil,
			last_text = nil,
			last_bg = nil,
		}
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
			pale_watcher.fx.update_player(p, 25, false, 0.3, session.stalker_tier)
		end
	end

	-- Whispered Survival Tip for the collector (No inventory clutter)
	local survival_tips = {
		"Never run in a straight line... weaving through dense trees disrupts his intercept vector.",
		"The glancing check... spin around every few seconds to freeze his silent advance.",
		"Head for the torches... sanctuary light (14+) holds him at bay at the dark tree line.",
		"He phase-teleports into cramped holes... never attempt to hide in a 3-block dirt bunker!",
		"A camera's xenon flash can stun him for 3-5 seconds and force an evasive retreat.",
		"Once all cursed pages are found, ignite a Ritual Pyre to summon and banish him in holy fire.",
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

	x_mob_core.emit("pale_watcher:page_collected", clicker,
		session.pages_collected, session.pages_total, session.session_id)

	-- Check if all cursed pages collected: inform players to ignite the Ritual Pyre
	if session.pages_collected >= session.pages_total then
		x_mob_core.emit("pale_watcher:all_pages_collected", clicker, session.session_id)
		for name, _ in pairs(session.players) do
			local p = core.get_player_by_name(name)
			if p then
				core.chat_send_player(name,
					core.colorize(pale_watcher.colors.warning,
						string.format("★ ALL %d CURSED PAGES COLLECTED! Craft a Ritual Pyre and burn them to banish the nightmare! ★",
							session.pages_total)))
				core.sound_play("pale_watcher_bell", {to_player = name, gain = 1.0}, true)
			end
		end
	end
end

---Executes the Cleansing Flame Banishment Sequence.
---Forcibly teleports Pale Watcher into the pyre, paralyzes him, plays death implode, and implodes into loot.
---@param pyre_pos Vector
---@param summoner? ObjectRef
---@param session_id? string
function pale_watcher.ritual.trigger_pyre_banishment(pyre_pos, summoner, session_id)
	local target_session_id = session_id
	if not target_session_id and summoner and summoner:is_player() then
		local _, sid = pale_watcher.ritual.get_player_session(summoner:get_player_name(), pyre_pos)
		target_session_id = sid
	end

	if not target_session_id then
		-- Find closest active Pale Watcher
		local min_dist = math.huge
		for id, session in pairs(active_sessions) do
			local d = vector.distance(pyre_pos, session.center)
			if d < min_dist then
				min_dist = d
				target_session_id = id
			end
		end
	end

	if not target_session_id then return end
	local session = active_sessions[target_session_id]
	if not session then return end

	local mob_obj = session.mob_ref
	if not mob_obj or not mob_obj:is_valid() then
		-- Fallback: If mob was despawned or unloaded during page collection, summon fresh entity at pyre
		local static_str = core.serialize({pyre_banish = true, session_id = target_session_id})
		mob_obj = core.add_entity(vector.add(pyre_pos, {x = 0, y = 0.5, z = 0}), "pale_watcher:pale_watcher", static_str)
		if mob_obj then
			session.mob_ref = mob_obj
			local ent = mob_obj:get_luaentity()
			if ent then
				ent.session_id = target_session_id
			end
		end
	end

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

-- Globalstep: Watchdog timer, player sync, grace countdown, dynamic down-scaling, and stalker progression
local ritual_step_timer = 0
core.register_globalstep(function(dtime)
	if not next(active_sessions) then return end
	ritual_step_timer = ritual_step_timer + dtime
	if ritual_step_timer < 1.0 then return end
	ritual_step_timer = 0

	for session_id, session in pairs(active_sessions) do
		-- Synchronize player positions & HUD states
		pale_watcher.ritual.update_session_players(session_id)

		-- Update departure grace timers
		local expired_any = false
		if session.departed_players then
			for pname, remaining_time in pairs(session.departed_players) do
				local next_time = remaining_time - 1.0
				if next_time <= 0 then
					session.departed_players[pname] = nil
					session.players[pname] = nil
					expired_any = true
				else
					session.departed_players[pname] = next_time
				end
			end
		end

		local active_count = get_active_player_count(session)

		-- Dynamic Scaling Down: when a player has permanently left after 20s grace
		if expired_any and active_count > 0 then
			local complete = (session.pages_collected >= session.pages_total)
			if not complete then
				local new_target = calculate_target_pages(active_count)
				if new_target < session.pages_total then
					-- Mercy rule: Surplus placed pages in the world are kept intact for survivors.
					-- Check instant completion safeguard if survivors already collected >= new_target
					if session.pages_collected >= new_target then
						session.pages_total = session.pages_collected
						session.stalker_tier = 4
						x_mob_core.emit("pale_watcher:all_pages_collected", nil, session_id)
						for pname, _ in pairs(session.players) do
							local p = core.get_player_by_name(pname)
							if p then
								update_player_hud(p, session)
								local contract_msg = string.format(
									"★ The presence contracts... You have gathered enough pages (%d/%d)!" ..
									" Craft a Ritual Pyre and burn them to banish the nightmare! ★",
									session.pages_collected, session.pages_total)
								core.chat_send_player(pname,
									core.colorize(pale_watcher.colors.warning, contract_msg))
								core.sound_play("pale_watcher_bell", {to_player = pname, gain = 1.0}, true)
							end
						end
					else
						session.pages_total = new_target
						session.stalker_tier = calculate_stalker_tier(session)
						for pname, _ in pairs(session.players) do
							local p = core.get_player_by_name(pname)
							if p then
								update_player_hud(p, session)
								core.chat_send_player(pname,
									core.colorize(pale_watcher.colors.whisper,
										string.format("★ The presence contracts... The required cursed pages have reduced to %d (%d/%d collected). ★",
											session.pages_total, session.pages_collected, session.pages_total)))
							end
						end
					end
				end
			end
		end

		-- Orphan & session progression checks
		local has_online_players = (active_count > 0)
		if not has_online_players and session.departed_players and next(session.departed_players) then
			-- Players are currently in grace period; give them time before declaring session orphaned
			has_online_players = true
		end

		if not has_online_players then
			session.orphan_timer = (session.orphan_timer or 0) + 1.0
			if session.orphan_timer >= 60.0 then
				pale_watcher.ritual.end_session(session_id, false)
			end
		else
			session.orphan_timer = 0
			session.elapsed_time = (session.elapsed_time or 0) + 1.0
			session.stalker_tier = calculate_stalker_tier(session)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	for _, session in pairs(active_sessions) do
		if session.players and session.players[name] then
			remove_player_hud(player, session)
			session.departed_players = session.departed_players or {}
			session.departed_players[name] = 20.0
		end
	end
end)

core.register_on_dieplayer(function(player)
	local name = player:get_player_name()
	for _, session in pairs(active_sessions) do
		if session.players and session.players[name] then
			remove_player_hud(player, session)
			session.departed_players = session.departed_players or {}
			session.departed_players[name] = 20.0
		end
	end
end)

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	for _, session in pairs(active_sessions) do
		if session.players and session.players[name] then
			session.players[name].hud_bg_id = nil
			session.players[name].hud_text_id = nil
			session.players[name].last_text = nil
			session.players[name].last_bg = nil
			if session.departed_players then
				session.departed_players[name] = nil
			end
		end
	end

	-- Delayed multi-stage resync once the client's local renderer finishes initializing
	core.after(0.5, function()
		if not player:is_player() or not player:is_valid() then return end
		local p_name = player:get_player_name()
		local p_pos = player:get_pos()
		if not p_pos then return end

		for session_id, session in pairs(active_sessions) do
			local center = session.center
			local mob_obj = session.mob_ref
			local mob_pos = mob_obj and mob_obj:is_valid() and mob_obj:get_pos()
			local dist_center = center and vector.distance(p_pos, center) or 9999
			local dist_mob = mob_pos and vector.distance(p_pos, mob_pos) or 9999
			local dist = math.min(dist_center, dist_mob)

			local complete = (session.pages_collected >= session.pages_total)
			local max_r = complete and SESSION_COMPLETE_EXIT_RADIUS or SESSION_EXIT_RADIUS
			local is_enrolled = (session.players and session.players[p_name] ~= nil)
			local in_bounds = is_enrolled and (dist <= max_r)
				or (dist <= (complete and (SESSION_RADIUS * 1.5) or SESSION_RADIUS))

			if in_bounds and x_mob_core.is_player_alive(player) then
				pale_watcher.ritual.update_session_players(session_id)
				pale_watcher.fx.apply_claustrophobic_fog(player, true)
				break
			end
		end
	end)

	-- Secondary backup at 1.5s to ensure slow-loading clients firmly receive fog & HUD
	core.after(1.5, function()
		if not player:is_player() or not player:is_valid() then return end
		local p_name = player:get_player_name()
		local p_pos = player:get_pos()
		if not p_pos then return end

		for _, session in pairs(active_sessions) do
			if session.players and session.players[p_name] then
				pale_watcher.fx.apply_claustrophobic_fog(player, true)
				break
			end
		end
	end)
end)

core.register_on_shutdown(function()
	for session_id, _ in pairs(active_sessions) do
		pale_watcher.ritual.end_session(session_id, false)
	end
end)

return pale_watcher.ritual
