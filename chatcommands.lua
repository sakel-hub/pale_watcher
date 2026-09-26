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
