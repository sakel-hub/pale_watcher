--[[
	pale_watcher - Wieldable Tools & Dimensional Artifacts
	Vintage Flash Camera, Shroud of Stalking, Dimensional Cloth, Static Core.
]]

pale_watcher.items = pale_watcher.items or {}

local colors = pale_watcher.colors
local S = pale_watcher.S

---Checks if pointed target (node or entity) handles right-click interactions.
---Allows players to open chests, collect cursed pages, or open doors while holding tools.
---@param itemstack ItemStack
---@param user ObjectRef
---@param pointed_thing table
---@return boolean handled Whether rightclick was consumed
---@return ItemStack? result The remaining itemstack
local function handle_target_rightclick(itemstack, user, pointed_thing)
	if not user or not user:is_player() then return false, itemstack end
	local controls = user:get_player_control()

	-- Pointed node interaction (chests, cursed pages, doors, furnaces)
	if pointed_thing and pointed_thing.type == "node" then
		local under = pointed_thing.under
		local node = core.get_node(under)
		local def = core.registered_nodes[node.name]
		if def and def.on_rightclick and not controls.sneak then
			local res = def.on_rightclick(under, node, user, itemstack, pointed_thing)
			return true, res or itemstack
		end
	end

	-- Pointed object/entity interaction (mobs, NPCs)
	if pointed_thing and pointed_thing.type == "object" then
		local obj = pointed_thing.ref
		if obj then
			local luaent = obj:get_luaentity()
			if luaent and luaent.on_rightclick and not controls.sneak then
				local res = luaent:on_rightclick(user)
				return true, res or itemstack
			end
		end
	end

	return false, itemstack
end

-- Vintage Flash Camera Tool (3 Uses via add_wear_by_uses)
local CAMERA_COOLDOWN = 10.0
local CAMERA_MAX_USES = 3
local camera_cooldowns = {}

local function trigger_flash_camera(itemstack, user, _pointed_thing)
	if not user or not user:is_player() then return itemstack end
	local name = user:get_player_name()
	local now = core.get_gametime()

	if camera_cooldowns[name] and now - camera_cooldowns[name] < CAMERA_COOLDOWN then
		local remain = CAMERA_COOLDOWN - (now - camera_cooldowns[name])
		core.chat_send_player(name, core.colorize(colors.recharge,
			S("Camera capacitor charging... (@1s)", string.format("%.1f", remain))))
		return itemstack
	end
	camera_cooldowns[name] = now

	local p_pos = user:get_pos()
	local look_dir = user:get_look_dir()
	local eye_pos = vector.add(p_pos, {x = 0, y = 1.625, z = 0})

	-- Full-screen white flash overlay for the user
	pale_watcher.fx.trigger_flash(user)

	-- Shutter click and bulb pop sound
	core.sound_play("pale_watcher_camera_flash", {pos = p_pos, gain = 1.0, max_hear_distance = 35}, true)

	-- Transient flash light burst at eye position to illuminate surrounding nodes
	local flash_node_pos = vector.round(vector.add(eye_pos, vector.multiply(look_dir, 1.2)))
	if core.get_node(flash_node_pos).name == "air" then
		core.set_node(flash_node_pos, {name = "pale_watcher:flash_light"})
	end

	-- Spark and smoke particles in front of the camera lens (using particle preset)
	pale_watcher.particles.camera_sparks(eye_pos, look_dir)

	-- Stun Pale Watcher if in line of sight (up to 25m, forward cone dot >= 0.40 or close range <= 5m)
	local objects = core.get_objects_inside_radius(p_pos, 25.0)
	for _, obj in ipairs(objects) do
		local luaent = obj:get_luaentity()
		if luaent and luaent.name == "pale_watcher:pale_watcher" then
			local mob_pos = obj:get_pos()
			if mob_pos then
				local dist_to_mob = vector.distance(p_pos, mob_pos)
				local sample_points = {
					vector.add(mob_pos, {x = 0, y = 2.6, z = 0}),
					vector.add(mob_pos, {x = 0, y = 1.6, z = 0}),
					vector.add(mob_pos, {x = 0, y = 0.8, z = 0}),
				}

				local hit = false
				for _, target_pt in ipairs(sample_points) do
					local to_mob = vector.direction(eye_pos, target_pt)
					local dot = vector.dot(look_dir, to_mob)

					if dot >= 0.40 or dist_to_mob <= 5.0 then
						if pale_watcher.has_visual_los(eye_pos, target_pt) then
							hit = true
							break
						end
					end
				end

				if hit and luaent.on_stunned then
					luaent:on_stunned(user, 0.6)
					core.chat_send_player(name, core.colorize(colors.warning,
						S("★ The blinding xenon flash repels the Pale Watcher!")))
					break
				end
			end
		end
	end

	-- Consume 1 charge of durability (3 uses total via add_wear_by_uses)
	local is_creative = core.is_creative_enabled(name)
	if not is_creative then
		itemstack:add_wear_by_uses(CAMERA_MAX_USES)
		if itemstack:is_empty() then
			core.sound_play("pale_watcher_paper_burn", {pos = p_pos, gain = 0.8, pitch = 1.2}, true)
			core.chat_send_player(name, core.colorize(colors.warning,
				S("★ The Vintage Flash Camera capacitor burned out and the bulb shattered!")))
		else
			local wear = itemstack:get_wear()
			local remaining_uses = math.max(0, math.ceil((65535 - wear) / (65535 / CAMERA_MAX_USES)))
			core.chat_send_player(name, core.colorize(colors.dimmed,
				S("Flash camera charges remaining: @1 / @2", remaining_uses, CAMERA_MAX_USES)))
		end
	end

	return itemstack
end

local function on_place_camera(itemstack, user, pointed_thing)
	local handled, new_stack = handle_target_rightclick(itemstack, user, pointed_thing)
	if handled then
		return new_stack
	end
	return trigger_flash_camera(itemstack, user, pointed_thing)
end

core.register_tool("pale_watcher:flash_camera", {
	description = S("Vintage Flash Camera") .. "\n" ..
		core.colorize(colors.system, S("Left-Click or Right-Click: Release high-intensity xenon flash.") .. "\n") ..
		core.colorize(colors.warning, S("• Blinds the Pale Watcher, forcing an evasive retreat.") .. "\n") ..
		core.colorize("#e0e0e0", S("• Illuminates deep darkness.") .. "\n") ..
		core.colorize(colors.dimmed, S("Durability: 3 flash charges.") .. "\n") ..
		core.colorize(colors.system, S("Cooldown: 10 seconds.")),
	short_description = S("Flash Camera"),
	inventory_image = "pale_watcher_flash_camera.png",
	wield_image = "pale_watcher_flash_camera.png",
	stack_max = 1,

	on_use = trigger_flash_camera,
	on_secondary_use = trigger_flash_camera,
	on_place = on_place_camera,
})

-- Dimensional Cloth Drop Item
core.register_craftitem("pale_watcher:dimensional_cloth", {
	description = S("Dimensional Cloth") .. "\n" ..
		core.colorize("#bbaaff",
			S("A torn scrap of void fabric with crimson thread.\nUsed to craft the Shroud of Stalking.")),
	short_description = S("Dimensional Cloth"),
	inventory_image = "pale_watcher_dimensional_cloth.png",
	wield_image = "pale_watcher_dimensional_cloth.png",
	stack_max = 16,
	groups = {rare = 1},
})

-- Shroud of Stalking (Blink Teleport Item)
local blink_cooldowns = {}

local function trigger_blink(itemstack, user, _pointed_thing)
	if not user or not user:is_player() then return itemstack end
	local controls = user:get_player_control()
	if not controls.sneak then
		core.chat_send_player(user:get_player_name(),
			core.colorize("#aaaaff", S("Hold Sneak and Click (LMB or RMB) to Blink.")))
		return itemstack
	end

	local name = user:get_player_name()
	local now = core.get_gametime()
	if blink_cooldowns[name] and now - blink_cooldowns[name] < 4.0 then
		local remain = 4.0 - (now - blink_cooldowns[name])
		core.chat_send_player(name, core.colorize(colors.recharge,
			S("Shroud shadow recharge... (@1s)", string.format("%.1f", remain))))
		return itemstack
	end
	blink_cooldowns[name] = now

	local p_pos = user:get_pos()
	local eye_pos = vector.add(p_pos, {x = 0, y = 1.625, z = 0})
	local look_dir = user:get_look_dir()
	local target_pos = vector.add(p_pos, vector.multiply(look_dir, 14.0))

	-- Raycast to find first obstructing node
	local ray = core.raycast(eye_pos, vector.add(eye_pos, vector.multiply(look_dir, 14.0)), false, false)
	for pt in ray do
		if pt.type == "node" then
			local def = core.registered_nodes[core.get_node(pt.under).name]
			if def and def.walkable then
				target_pos = vector.add(pt.above, {x = 0, y = 0, z = 0})
				break
			end
		end
	end

	-- Ensure ground support below target using shared spatial helper
	local ground = pale_watcher.find_ground_node(target_pos.x, target_pos.y - 1, target_pos.z, 1, 4, 2)
	if ground then
		target_pos = {x = ground.x, y = ground.y + 1, z = ground.z}
	end

	-- Departure particles (preset)
	pale_watcher.particles.void_mist(p_pos, 1.0, 30)
	core.sound_play("pale_watcher_static", {pos = p_pos, gain = 0.5, max_hear_distance = 15}, true)

	-- Execute Blink teleport
	user:set_pos(target_pos)

	-- Arrival particles (preset)
	pale_watcher.particles.void_mist(target_pos, 1.0, 30)
	core.sound_play("pale_watcher_static", {pos = target_pos, gain = 0.5, max_hear_distance = 15}, true)

	return itemstack
end

local function on_place_shroud(itemstack, user, pointed_thing)
	local handled, new_stack = handle_target_rightclick(itemstack, user, pointed_thing)
	if handled then
		return new_stack
	end
	return trigger_blink(itemstack, user, pointed_thing)
end

core.register_tool("pale_watcher:shroud_of_stalking", {
	description = S("Shroud of Stalking") .. "\n" ..
		core.colorize("#c0b0ff", S("Sneak + Click (LMB or RMB) to Blink forward into the shadows (14m).") .. "\n") ..
		core.colorize(colors.dimmed, S("Cooldown: 4 seconds.")),
	short_description = S("Shroud of Stalking"),
	inventory_image = "pale_watcher_shroud_of_stalking.png",
	wield_image = "pale_watcher_shroud_of_stalking.png",
	stack_max = 1,

	on_use = trigger_blink,
	on_secondary_use = trigger_blink,
	on_place = on_place_shroud,
})

-- Static Core drop item
local STATIC_CORE_COOLDOWN = 1.0
local static_core_cooldowns = {}
local static_core_sounds = {}
local static_core_sound_gen = {}

local function stop_player_static_sounds(name)
	local handles = static_core_sounds[name]
	if handles then
		for i = 1, #handles do
			core.sound_stop(handles[i])
		end
		static_core_sounds[name] = nil
	end
end

---Cleans up all item-related cooldowns and active sounds for a player.
---Guarantees no orphaned sounds or stale timers on disconnect, death, timeout, or reconnect.
---@param player_or_name ObjectRef|string
local function clear_player_item_state(player_or_name)
	local name = type(player_or_name) == "string" and player_or_name or
		(player_or_name and player_or_name.is_player and player_or_name:is_player() and player_or_name:get_player_name())
	if not name or name == "" then return end

	stop_player_static_sounds(name)
	static_core_cooldowns[name] = nil
	static_core_sound_gen[name] = nil
	camera_cooldowns[name] = nil
	blink_cooldowns[name] = nil
end

---Stops all active sounds and resets cooldowns across all players.
---Guarantees a clean state on server shutdown, restart, or full reset.
local function clear_all_item_states()
	for name in pairs(static_core_sounds) do
		stop_player_static_sounds(name)
	end
	static_core_sounds = {}
	static_core_sound_gen = {}
	static_core_cooldowns = {}
	camera_cooldowns = {}
	blink_cooldowns = {}
end

pale_watcher.items.clear_player = clear_player_item_state
pale_watcher.items.clear_all = clear_all_item_states

-- Lifecycle Hooks: Disconnect, Death, Reconnect, and Server Shutdown/Restart
core.register_on_leaveplayer(function(player)
	clear_player_item_state(player)
end)

core.register_on_dieplayer(function(player)
	clear_player_item_state(player)
end)

core.register_on_joinplayer(function(player)
	clear_player_item_state(player)
end)

core.register_on_shutdown(function()
	clear_all_item_states()
end)

local function trigger_static_core(itemstack, user, _pointed_thing)
	if not user or not user:is_player() then return itemstack end
	local name = user:get_player_name()
	local now = core.get_us_time() / 1000000

	-- Stop previous sounds immediately before starting a new one
	stop_player_static_sounds(name)

	-- Throttle repeated clicks to prevent sound and chat flood
	if static_core_cooldowns[name] and now - static_core_cooldowns[name] < STATIC_CORE_COOLDOWN then
		return itemstack
	end
	static_core_cooldowns[name] = now

	local gen = (static_core_sound_gen[name] or 0) + 1
	static_core_sound_gen[name] = gen

	local is_aiming = pale_watcher.ritual.is_aiming_at_page(user)
	local handles = {}
	if is_aiming then
		local s1 = core.sound_play("pale_watcher_static", {to_player = name, gain = 0.8, pitch = 1.4}, false)
		local s2 = core.sound_play("pale_watcher_page_whisper", {to_player = name, gain = 0.6}, false)
		if s1 then handles[#handles + 1] = s1 end
		if s2 then handles[#handles + 1] = s2 end
		core.chat_send_player(name, core.colorize(colors.warning,
			S("★ The Static Core crackles violently! A Cursed Page is directly in your line of sight!")))
	else
		local s1 = core.sound_play("pale_watcher_static", {to_player = name, gain = 0.2, pitch = 0.8}, false)
		if s1 then handles[#handles + 1] = s1 end
		core.chat_send_player(name, core.colorize(colors.dimmed,
			S("The Static Core hums softly... No cursed anomalies detected in this direction.")))
	end
	static_core_sounds[name] = handles

	-- Auto-cleanup timeout: Frees sound handles once the ~3.5s audio clip finishes
	core.after(3.5, function()
		if static_core_sound_gen[name] == gen then
			stop_player_static_sounds(name)
		end
	end)

	return itemstack
end

local function on_place_static_core(itemstack, user, pointed_thing)
	local handled, new_stack = handle_target_rightclick(itemstack, user, pointed_thing)
	if handled then
		return new_stack
	end
	return trigger_static_core(itemstack, user, pointed_thing)
end

core.register_craftitem("pale_watcher:static_core", {
	description = S("Static Core") .. "\n" ..
		core.colorize(colors.system, S("A condensed sphere of quantum radio noise.") .. "\n") ..
		core.colorize(colors.whisper, S("Click to detect lingering cursed anomalies in your line of sight.")),
	short_description = S("Static Core"),
	inventory_image = "pale_watcher_hud_static_1.png",
	stack_max = 16,
	groups = {rare = 1},

	on_use = trigger_static_core,
	on_secondary_use = trigger_static_core,
	on_place = on_place_static_core,
})

return pale_watcher.items
