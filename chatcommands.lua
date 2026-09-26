--[[
	pale_watcher - Chat Commands
	In-game commands for player effect recovery and horror state management.
]]

core.register_chatcommand("pw_clear", {
	params = "[<player>]",
	description = "Clears all active Pale Watcher horror HUD overlays, audio, FOV changes, and domain fog",
	privs = {},
	func = function(name, param)
		local target_name = name
		if param and param:trim() ~= "" then
			if not core.check_player_privs(name, {server = true}) then
				return false, "Clearing effects for other players requires 'server' privilege."
			end
			target_name = param:trim()
		end

		local player = core.get_player_by_name(target_name)
		if not player then
			return false, "Player '" .. target_name .. "' not found."
		end

		pale_watcher.fx.clear_player(player)
		player:set_fov(0)
		pale_watcher.fx.clear_claustrophobic_fog(player)

		-- Emergency manual recovery: remove any legacy stuck elements from previous sessions
		for id = 0, 50 do
			local elem = player:hud_get(id)
			if elem and (elem.name == "pale_watcher_flash"
					or (type(elem.text) == "string" and elem.text:find("pale_watcher_hud_", 1, true))) then
				player:hud_remove(id)
			end
		end

		return true, "All Pale Watcher visual and audio effects cleared for " .. target_name .. "."
	end,
})

core.register_chatcommand("pw_locate", {
	params = "",
	description = "Locates remaining uncollected Cursed Pages in the active encounter",
	privs = {},
	func = function(name, _param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player '" .. name .. "' not found."
		end
		local p_pos = player:get_pos()
		local session, sid = pale_watcher.ritual.get_player_session(name, p_pos)
		if not session then
			return false, "No active Pale Watcher encounter found near you."
		end

		local remaining = {}
		if session.placed_pages then
			for _, pos in pairs(session.placed_pages) do
				local node = core.get_node(pos)
				local restored = false
				if node.name ~= "pale_watcher:cursed_page" then
					core.set_node(pos, {name = "pale_watcher:cursed_page"})
					local meta = core.get_meta(pos)
					if sid then meta:set_string("session_id", sid) end
					meta:set_int("age", 0)
					core.get_node_timer(pos):start(4.0)
					restored = true
				end
				local d = math.floor(vector.distance(p_pos, pos) + 0.5)
				table.insert(remaining, {pos = pos, dist = d, restored = restored})
			end
		end

		if #remaining == 0 then
			return true, string.format("All %d pages collected! Craft a Ritual Pyre to banish him!", session.pages_total)
		end

		table.sort(remaining, function(a, b) return a.dist < b.dist end)

		local lines = {
			string.format("Cursed Pages remaining: %d / %d", #remaining, session.pages_total)
		}
		for i, page in ipairs(remaining) do
			local p = page.pos
			local dx = p.x - p_pos.x
			local dz = p.z - p_pos.z
			local cardinal = ""
			if math.abs(dz) >= math.abs(dx) * 0.4 then
				cardinal = cardinal .. (dz > 0 and "North" or "South")
			end
			if math.abs(dx) >= math.abs(dz) * 0.4 then
				cardinal = cardinal .. (dx > 0 and "East" or "West")
			end
			if cardinal == "" then cardinal = "Nearby" end

			local info = string.format("  [%d] %dm away (%s) at (X: %d, Y: %d, Z: %d)",
				i, page.dist, cardinal, math.floor(p.x + 0.5), math.floor(p.y + 0.5), math.floor(p.z + 0.5))
			if page.restored then
				info = info .. " [Restored]"
			end
			table.insert(lines, info)
		end

		return true, table.concat(lines, "\n")
	end,
})
