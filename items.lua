--[[
	pale_watcher - Wieldable Tools & Dimensional Artifacts
	Vintage Flash Camera, Shroud of Stalking, Dimensional Cloth, Static Core.
]]

---@class PaleWatcherItems
pale_watcher.items = {}

local colors = pale_watcher.colors

-- 1. Vintage Flash Camera Tool
local camera_cooldowns = {}

local function trigger_flash_camera(itemstack, user, _pointed_thing)
	if not user or not user:is_player() then return itemstack end
	local name = user:get_player_name()
	local now = core.get_gametime()

	if camera_cooldowns[name] and now - camera_cooldowns[name] < 7.0 then
		local remain = 7.0 - (now - camera_cooldowns[name])
		core.chat_send_player(name, core.colorize(colors.recharge,
			string.format("Camera capacitor charging... (%.1fs)", remain)))
		return itemstack
	end
	camera_cooldowns[name] = now

	local p_pos = user:get_pos()
	local look_dir = user:get_look_dir()
	local eye_pos = vector.add(p_pos, {x = 0, y = 1.625, z = 0})

	-- 1. Full-screen white flash overlay for the user
	pale_watcher.fx.trigger_flash(user)

	-- 2. Shutter click and bulb pop sound
	core.sound_play("pale_watcher_camera_flash", {pos = p_pos, gain = 1.0, max_hear_distance = 35}, true)

	-- 3. Transient flash light burst at eye position to illuminate surrounding nodes
	local flash_node_pos = vector.round(vector.add(eye_pos, vector.multiply(look_dir, 1.2)))
	if core.get_node(flash_node_pos).name == "air" then
		core.set_node(flash_node_pos, {name = "pale_watcher:flash_light"})
	end

	-- 4. Spark and smoke particles in front of the camera lens (using particle preset)
	pale_watcher.particles.camera_sparks(eye_pos, look_dir)

	-- 5. Stun Pale Watcher if in line of sight (up to 25m, forward cone dot >= 0.40 or close range <= 5m)
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
						if (pale_watcher.has_visual_los and pale_watcher.has_visual_los(eye_pos, target_pt))
							or core.line_of_sight(eye_pos, target_pt) then
							hit = true
							break
						end
					end
				end

				if hit and luaent.on_stunned then
					luaent:on_stunned(user, 0.6)
					core.chat_send_player(name, core.colorize(colors.warning,
						"★ The blinding xenon flash repels the Pale Watcher!"))
					break
				end
			end
		end
	end

	return itemstack
end

core.register_tool("pale_watcher:flash_camera", {
	description = "Vintage Flash Camera\n" ..
		core.colorize(colors.system, "Left-Click: Release high-intensity xenon flash.\n") ..
		core.colorize(colors.warning, "• Blinds the Pale Watcher, forcing an evasive retreat.\n") ..
		core.colorize("#e0e0e0", "• Illuminates deep darkness.\n") ..
		core.colorize(colors.system, "Cooldown: 7 seconds."),
	short_description = "Flash Camera",
	inventory_image = "pale_watcher_flash_camera.png",
	wield_image = "pale_watcher_flash_camera.png",
	stack_max = 1,

	on_use = trigger_flash_camera,
})

-- 2. Dimensional Cloth Drop Item
core.register_craftitem("pale_watcher:dimensional_cloth", {
	description = "Dimensional Cloth\n" ..
		core.colorize("#bbaaff", "A torn scrap of void fabric with crimson thread.\nUsed to craft the Shroud of Stalking."),
	short_description = "Dimensional Cloth",
	inventory_image = "pale_watcher_dimensional_cloth.png",
	wield_image = "pale_watcher_dimensional_cloth.png",
	stack_max = 16,
	groups = {rare = 1},
})

-- 3. Shroud of Stalking (Blink Teleport Item)
local blink_cooldowns = {}

core.register_tool("pale_watcher:shroud_of_stalking", {
	description = "Shroud of Stalking\n" ..
		core.colorize("#c0b0ff", "Sneak + Right-Click to Blink forward into the shadows (14m).\n") ..
		core.colorize(colors.dimmed, "Cooldown: 4 seconds."),
	short_description = "Shroud of Stalking",
	inventory_image = "pale_watcher_shroud_of_stalking.png",
	wield_image = "pale_watcher_shroud_of_stalking.png",
	stack_max = 1,

	on_use = function(itemstack, user, _pointed_thing)
		if not user or not user:is_player() then return itemstack end
		local controls = user:get_player_control()
		if not controls.sneak then
			core.chat_send_player(user:get_player_name(),
				core.colorize("#aaaaff", "Hold Sneak and Right-Click to Blink."))
			return itemstack
		end

		local name = user:get_player_name()
		local now = core.get_gametime()
		if blink_cooldowns[name] and now - blink_cooldowns[name] < 4.0 then
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
	end,
})

-- 4. Static Core drop item
core.register_craftitem("pale_watcher:static_core", {
	description = "Static Core\n" .. core.colorize(colors.system, "A condensed sphere of quantum radio noise."),
	short_description = "Static Core",
	inventory_image = "pale_watcher_hud_static_1.png",
	stack_max = 16,
	groups = {rare = 1},
})

return pale_watcher.items
