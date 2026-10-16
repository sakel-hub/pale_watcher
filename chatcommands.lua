--[[
	pale_watcher - Chat Commands
	In-game commands for player effect recovery and horror state management.
]]

local S = pale_watcher.S

core.register_chatcommand("pw_clear", {
	params = "[<player>]",
	description = S("Clears all active Pale Watcher horror HUD overlays, audio, FOV changes, and domain fog"),
	privs = {},
	func = function(name, param)
		local target_name = name
		if param and param:trim() ~= "" then
			if not core.check_player_privs(name, {server = true}) then
				return false, S("Clearing effects for other players requires 'server' privilege.")
			end
			target_name = param:trim()
		end

		local player = core.get_player_by_name(target_name)
		if not player then
			return false, S("Player '@1' not found.", target_name)
		end

		pale_watcher.fx.clear_player(player)
		pale_watcher.fx.clear_claustrophobic_fog(player, true)
		pale_watcher.physics.clear_all(player)
		pale_watcher.items.clear_player(player)

		return true, S("All Pale Watcher visual and audio effects cleared for @1.", target_name)
	end,
})

core.register_chatcommand("pw_locate", {
	params = "",
	description = S("Locates remaining uncollected Cursed Pages in the active encounter"),
	privs = {},
	func = function(name, _param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player '" .. name .. "' not found."
		end
		local p_pos = player:get_pos()
		local session, sid = pale_watcher.ritual.get_player_session(name, p_pos)
		if not session then
			return false, S("No active Pale Watcher encounter found near you.")
		end

		local remaining = {}
		if session.placed_pages then
			for _, pos in pairs(session.placed_pages) do
				local node = core.get_node(pos)
				if node.name == "ignore" then
					core.load_area(pos)
					node = core.get_node(pos)
				end
				local restored = false
				if node.name ~= "pale_watcher:cursed_page" then
					core.set_node(pos, {name = "pale_watcher:cursed_page"})
					local meta = core.get_meta(pos)
					if sid then meta:set_string("session_id", sid) end
					core.get_node_timer(pos):start(4.0)
					pale_watcher.ritual.track_page(pos, sid)
					restored = true
				end
				local d = math.floor(vector.distance(p_pos, pos) + 0.5)
				table.insert(remaining, {pos = pos, dist = d, restored = restored})
			end
		end

		if #remaining == 0 then
			return true, S("All @1 pages collected! Craft a Ritual Pyre to banish him!", session.pages_total)
		end

		table.sort(remaining, function(a, b) return a.dist < b.dist end)

		local needed = math.max(0, session.pages_total - session.pages_collected)
		local lines = {
			S("Cursed Pages remaining to collect: @1 / @2 (Manifested in woods: @3)",
				needed, session.pages_total, #remaining)
		}
		for i, page in ipairs(remaining) do
			local p = page.pos
			local dx = p.x - p_pos.x
			local dz = p.z - p_pos.z
			local cardinal = ""
			if math.abs(dz) >= math.abs(dx) * 0.4 then
				cardinal = cardinal .. (dz > 0 and S("North") or S("South"))
			end
			if math.abs(dx) >= math.abs(dz) * 0.4 then
				cardinal = cardinal .. (dx > 0 and S("East") or S("West"))
			end
			if cardinal == "" then cardinal = S("Nearby") end

			local info = string.format("  [%d] %dm away (%s) at (X: %d, Y: %d, Z: %d)",
				i, page.dist, cardinal, math.floor(p.x + 0.5), math.floor(p.y + 0.5), math.floor(p.z + 0.5))
			if page.restored then
				info = info .. " [" .. S("Restored") .. "]"
			end
			table.insert(lines, info)
		end

		return true, table.concat(lines, "\n")
	end,
})

core.register_chatcommand("pw_test_hud", {
	params = "[<pages>]",
	description = S("Tests the cursed pages HUD overlay (default: all pages for completion highlight)"),
	privs = {server = true},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, S("Player '@1' not found.", name)
		end
		local p_pos = player:get_pos()

		local session = pale_watcher.ritual.get_player_session(name, p_pos)
		if session then
			local count = tonumber(param) or session.pages_total
			count = math.max(0, math.min(session.pages_total, count))
			session.pages_collected = count
			pale_watcher.ritual.update_session_players(session.session_id, p_pos)
			return true, S("Set active encounter HUD progress to @1 / @2 pages.", count, session.pages_total)
		end

		local obj = pale_watcher.spawn(p_pos)
		if obj then
			local ent = obj:get_luaentity()
			if ent and ent.session_id then
				local s = pale_watcher.ritual.get_player_session(name, p_pos)
				if s then
					local count = tonumber(param) or s.pages_total
					count = math.max(0, math.min(s.pages_total, count))
					s.pages_collected = count
					pale_watcher.ritual.update_session_players(ent.session_id, p_pos)
					return true, S("Started test encounter with @1 / @2 pages.", count, s.pages_total)
				end
			end
		end
		return false, S("Failed to initialize test encounter HUD.")
	end,
})

core.register_chatcommand("pw_purge_pages", {
	params = "",
	description = S("Purges all orphan or lingering cursed pages from the world"),
	privs = {server = true},
	func = function(_name, _param)
		local count = pale_watcher.ritual.purge_all_orphans(true)
		return true, S("Purged @1 orphan cursed pages from world records.", count)
	end,
})

core.register_chatcommand("pw_status", {
	params = "",
	description = S("Displays active Pale Watcher encounters, server cap, and player immunity cooldowns"),
	privs = {server = true},
	func = function(_name, _param)
		local active_count = pale_watcher.ritual.get_active_session_count()
		local max_count = pale_watcher.MAX_ACTIVE_ENCOUNTERS
		local cooldowns = pale_watcher.ritual.get_all_player_cooldowns()

		local lines = {
			S("=== Pale Watcher Multiplayer Status ==="),
			S("Active Encounters: @1 / @2 (Server Cap)", active_count, max_count),
			S("Natural Spawning: @1 (Chance: 1 in @2, Night Only: @3, Max Light: @4, Y: @5 to @6)",
				pale_watcher.ENABLE_SPAWNING and S("Enabled") or S("Disabled"),
				pale_watcher.SPAWN_CHANCE,
				pale_watcher.NIGHT_ONLY and S("Yes") or S("No"),
				pale_watcher.MAX_LIGHT,
				pale_watcher.MIN_ELEVATION,
				pale_watcher.MAX_ELEVATION),
			S("Respect Protection: @1", pale_watcher.RESPECT_PROTECTION and S("Yes") or S("No")),
		}

		local cd_list = {}
		for pname, remaining in pairs(cooldowns) do
			table.insert(cd_list, string.format("  • %s: %ds remaining", pname, remaining))
		end

		if #cd_list > 0 then
			table.insert(lines, S("Player Immunity Cooldowns (@1 active):", #cd_list))
			for _, cd_line in ipairs(cd_list) do
				table.insert(lines, cd_line)
			end
		else
			table.insert(lines, S("No players currently on encounter cooldown."))
		end

		return true, table.concat(lines, "\n")
	end,
})
