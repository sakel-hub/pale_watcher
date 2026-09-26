--[[
	pale_watcher - Nodes, Items & Crafting Recipes
	Cursed Page, Ritual Pyre, Flash Camera, Dimensional Cloth, Shroud of Stalking.
]]

---@class PaleWatcherNodes
pale_watcher.nodes = {}

-- Transient invisible light node created during camera flash
core.register_node("pale_watcher:flash_light", {
	drawtype = "airlike",
	paramtype = "light",
	light_source = 14,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	sunlight_propagates = true,
	groups = {not_in_creative_inventory = 1},
	on_timer = function(pos)
		core.remove_node(pos)
		return false
	end,
	on_construct = function(pos)
		core.get_node_timer(pos):start(0.4)
	end,
})

-- 1. Cursed Page (Wall-Mounted Node)
core.register_node("pale_watcher:cursed_page", {
	description = "Cursed Page",
	short_description = "Cursed Page",
	drawtype = "signlike",
	tiles = {"pale_watcher_cursed_page.png"},
	inventory_image = "pale_watcher_cursed_page_item.png",
	wield_image = "pale_watcher_cursed_page_item.png",
	drop = "pale_watcher:cursed_page_item",
	paramtype = "light",
	paramtype2 = "wallmounted",
	sunlight_propagates = true,
	walkable = false,
	selection_box = {
		type = "wallmounted",
	},
	groups = {dig_immediate = 3, attached_node = 1, not_in_creative_inventory = 1},

	on_construct = function(pos)
		local meta = core.get_meta(pos)
		meta:set_int("age", 0)
		-- Start ambient particle wisp & subtle ink whisper loop (and periodic orphan/TTL check)
		core.get_node_timer(pos):start(4.0)
	end,

	on_timer = function(pos, elapsed)
		local meta = core.get_meta(pos)
		local age = meta:get_int("age") + math.floor(elapsed)
		meta:set_int("age", age)

		-- Orphan check: if session ended or server rebooted without active session, purge immediately
		local sid = meta:get_string("session_id")
		local session_active = sid ~= "" and pale_watcher.ritual.is_session_active(sid)
		if sid ~= "" and not session_active then
			core.remove_node(pos)
			return false
		end

		-- TTL expired: only remove if orphaned without an active encounter session
		if not session_active and age >= 600 then
			core.remove_node(pos)
			return false
		end

		-- Play subtle positional ink whisper if a player is within 15m
		local players = core.get_connected_players()
		local has_nearby = false
		for _, p in ipairs(players) do
			if vector.distance(pos, p:get_pos()) <= 15.0 then
				has_nearby = true
				break
			end
		end

		if has_nearby then
			core.sound_play("pale_watcher_page_whisper", {
				pos = pos,
				gain = 0.25,
				max_hear_distance = 12,
			}, true)

			-- Subtle black ink wisp particle spawner
			core.add_particlespawner({
				amount = 6,
				time = 1.0,
				pos = {
					min = vector.subtract(pos, 0.1),
					max = vector.add(pos, 0.1),
				},
				vel = {
					min = {x = -0.05, y = 0.1, z = -0.05},
					max = {x = 0.05, y = 0.35, z = 0.05},
				},
				acc = {
					min = {x = -0.02, y = 0.05, z = -0.02},
					max = {x = 0.02, y = 0.1, z = 0.02},
				},
				exptime = {min = 1.0, max = 2.0},
				size = {min = 0.5, max = 1.5},
				jitter = {min = {x = -0.05, y = -0.05, z = -0.05}, max = {x = 0.05, y = 0.05, z = 0.05}},
				drag = {min = {x = 0.05, y = 0.05, z = 0.05}, max = {x = 0.1, y = 0.1, z = 0.1}},
				texpool = {
					{name = "pale_watcher_particles.png^[verticalframe:8:2", blend = "alpha"},
					{name = "pale_watcher_particles.png^[verticalframe:8:3", blend = "alpha"},
				},
				scale_tween = {start = 1.0, finish = 0.2},
				alpha_tween = {start = 0.6, finish = 0.0},
				minpos = vector.subtract(pos, 0.1),
				maxpos = vector.add(pos, 0.1),
				minvel = {x = -0.05, y = 0.1, z = -0.05},
				maxvel = {x = 0.05, y = 0.35, z = 0.05},
				minacc = {x = -0.02, y = 0.05, z = -0.02},
				maxacc = {x = 0.02, y = 0.1, z = 0.02},
				minexptime = 1.0,
				maxexptime = 2.0,
				minsize = 0.5,
				maxsize = 1.5,
				texture = "pale_watcher_particles.png^[verticalframe:8:3",
			})
		end

		return true -- Continue running timer
	end,

	on_rightclick = function(pos, _node, clicker, _itemstack, _pointed_thing)
		if not clicker or not clicker:is_player() then return end

		-- Burning paper particle effect (realistic fire + ash)
		core.add_particlespawner({
			amount = 45,
			time = 0.8,
			pos = {
				min = vector.subtract(pos, 0.25),
				max = vector.add(pos, 0.25),
			},
			vel = {
				min = {x = -0.8, y = 0.8, z = -0.8},
				max = {x = 0.8, y = 2.2, z = 0.8},
			},
			acc = {
				min = {x = -0.1, y = 0.5, z = -0.1},
				max = {x = 0.1, y = 1.5, z = 0.1},
			},
			exptime = {min = 0.8, max = 1.8},
			size = {min = 1.2, max = 3.5},
			jitter = {min = {x = -0.4, y = -0.4, z = -0.4}, max = {x = 0.4, y = 0.4, z = 0.4}},
			drag = {min = {x = 0.1, y = 0.1, z = 0.1}, max = {x = 0.25, y = 0.25, z = 0.25}},
			texpool = {
				{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:1", blend = "add"},
				{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:3", blend = "add"},
				{name = "pale_watcher_cursed_page_item.png^[multiply:#302020", blend = "alpha"},
			},
			scale_tween = {start = 1.2, finish = 0.3},
			alpha_tween = {start = 1.0, finish = 0.0},
			minpos = vector.subtract(pos, 0.25),
			maxpos = vector.add(pos, 0.25),
			minvel = {x = -0.8, y = 0.8, z = -0.8},
			maxvel = {x = 0.8, y = 2.2, z = 0.8},
			minacc = {x = -0.1, y = 0.5, z = -0.1},
			maxacc = {x = 0.1, y = 1.5, z = 0.1},
			minexptime = 0.8,
			maxexptime = 1.8,
			minsize = 1.2,
			maxsize = 3.5,
			texture = "pale_watcher_cursed_page_item.png^[multiply:#302020",
			glow = 8,
		})

		-- Sound of burning paper
		core.sound_play("pale_watcher_paper_burn", {pos = pos, max_hear_distance = 25}, true)

		-- Notify session manager (tracks progress in session & HUD only - zero inventory clutter)
		pale_watcher.ritual.on_page_collected(pos, clicker)

		-- Remove page node cleanly
		core.remove_node(pos)
	end,
})

-- 2. Ritual Pyre (Unlit Altar)
-- Attuned directly to the active Pale Watcher encounter session: no page items in inventory required
core.register_node("pale_watcher:ritual_pyre", {
	description = "Ritual Pyre\n" ..
		core.colorize("#ffaa55", "Attuned to the Cursed Pages in the active encounter.\n") ..
		core.colorize("#ffff88", "Right-Click when all 8 pages are found to ignite the Cleansing Flame."),
	short_description = "Ritual Pyre",
	drawtype = "nodebox",
	paramtype = "light",
	tiles = {
		"pale_watcher_ritual_pyre_top.png",
		"pale_watcher_ritual_pyre_top.png^[multiply:#222222",
		"pale_watcher_ritual_pyre_side.png",
	},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 0.5, -0.2, 0.5},   -- Stone hearth base
			{-0.35, -0.2, -0.35, 0.35, 0.0, 0.35}, -- Crossed logs & charcoal bed
			{-0.2, 0.0, -0.2, 0.2, 0.2, 0.2},     -- Kindling heap
		},
	},
	groups = {cracky = 2, oddly_breakable_by_hand = 1},

	on_construct = function(pos)
		local meta = core.get_meta(pos)
		meta:set_string("infotext", "Ritual Pyre (Requires all 8 Cursed Pages found in active encounter)")
	end,

	on_rightclick = function(pos, node, clicker, _itemstack)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()

		-- Check active session for this player / location
		local session = pale_watcher.ritual.get_player_session(name, pos)
		if not session then
			core.chat_send_player(name,
				core.colorize("#aaaaaa", "The Pyre remains cold. No dark presence is tethered here."))
			return
		end

		if session.pages_collected < session.pages_total then
			local msg = string.format("The Pyre refuses to ignite... All 8 Cursed Pages must be found! (%d/%d Collected)",
				session.pages_collected, session.pages_total)
			core.chat_send_player(name, core.colorize("#ff4444", msg))

			-- Emit cold dark ash rejection particles
			core.add_particlespawner({
				amount = 15,
				time = 0.5,
				pos = {min = vector.subtract(pos, 0.2), max = vector.add(pos, {x = 0.2, y = 0.4, z = 0.2})},
				vel = {min = {x = -0.2, y = 0.1, z = -0.2}, max = {x = 0.2, y = 0.6, z = 0.2}},
				texpool = {
					{name = "pale_watcher_particles.png^[verticalframe:8:4", blend = "alpha"},
					{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
				},
				minpos = vector.subtract(pos, 0.2),
				maxpos = vector.add(pos, {x = 0.2, y = 0.4, z = 0.2}),
				minvel = {x = -0.2, y = 0.1, z = -0.2},
				maxvel = {x = 0.2, y = 0.6, z = 0.2},
				minacc = {x = 0, y = 0, z = 0},
				maxacc = {x = 0, y = 0.1, z = 0},
				minexptime = 0.5,
				maxexptime = 1.0,
				minsize = 1.0,
				maxsize = 2.0,
				texture = "pale_watcher_particles.png^[verticalframe:8:4",
			})
			core.sound_play("pale_watcher_bell", {pos = pos, gain = 0.4, max_hear_distance = 15}, true)
			return
		end

		-- All 8 pages collected: Ignite the Cleansing Flame directly from session progress!
		core.swap_node(pos, {name = "pale_watcher:ritual_pyre_burning", param2 = node.param2})
		core.sound_play("pale_watcher_paper_burn", {pos = pos, gain = 1.0, max_hear_distance = 40})
		core.chat_send_all(core.colorize("#ffaa33",
			"★ The 8 bound curses ignite the Cleansing Flame! The Pale Watcher is forcibly drawn into the pyre!"))

		-- Begin Cleansing Flame Banishment Sequence
		pale_watcher.ritual.trigger_pyre_banishment(pos, clicker)
	end,
})

-- 4. Ritual Pyre (Burning Cleansing Flame)
core.register_node("pale_watcher:ritual_pyre_burning", {
	description = "Cleansing Flame Pyre",
	short_description = "Cleansing Flame Pyre",
	drawtype = "nodebox",
	paramtype = "light",
	light_source = 14,
	tiles = {
		{
			name = "pale_watcher_ritual_pyre_flame.png",
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 1.0,
			},
		},
		"pale_watcher_ritual_pyre_top.png^[multiply:#222222",
		"pale_watcher_ritual_pyre_side.png",
	},
	node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.5, 0.5, -0.2, 0.5},
			{-0.35, -0.2, -0.35, 0.35, 0.0, 0.35},
			{-0.25, 0.0, -0.25, 0.25, 0.6, 0.25}, -- Tower of flame
		},
	},
	groups = {cracky = 2, not_in_creative_inventory = 1},
	damage_per_second = 6,

	on_timer = function(pos)
		local node = core.get_node(pos)
		core.swap_node(pos, {name = "pale_watcher:ritual_pyre", param2 = node.param2})
		return false
	end,

	on_construct = function(pos)
		core.get_node_timer(pos):start(45) -- Cleansing flame burns for 45s then returns to dormant stone pyre
		-- Continuous roaring flame particles
		core.add_particlespawner({
			amount = 40,
			time = 0, -- infinite until node removed
			pos = {
				min = {x = pos.x - 0.3, y = pos.y, z = pos.z - 0.3},
				max = {x = pos.x + 0.3, y = pos.y + 0.5, z = pos.z + 0.3},
			},
			vel = {
				min = {x = -0.3, y = 1.0, z = -0.3},
				max = {x = 0.3, y = 2.5, z = 0.3},
			},
			acc = {
				min = {x = -0.1, y = 0.2, z = -0.1},
				max = {x = 0.1, y = 0.8, z = 0.1},
			},
			exptime = {min = 0.8, max = 1.6},
			size = {min = 1.5, max = 4.0},
			jitter = {min = {x = -0.2, y = -0.2, z = -0.2}, max = {x = 0.2, y = 0.2, z = 0.2}},
			texpool = {
				{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:1", blend = "add"},
				{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:4", blend = "add"},
			},
			scale_tween = {start = 1.5, finish = 0.2},
			alpha_tween = {start = 1.0, finish = 0.0},
			minpos = {x = pos.x - 0.3, y = pos.y, z = pos.z - 0.3},
			maxpos = {x = pos.x + 0.3, y = pos.y + 0.5, z = pos.z + 0.3},
			minvel = {x = -0.3, y = 1.0, z = -0.3},
			maxvel = {x = 0.3, y = 2.5, z = 0.3},
			minacc = {x = -0.1, y = 0.2, z = -0.1},
			maxacc = {x = 0.1, y = 0.8, z = 0.1},
			minexptime = 0.8,
			maxexptime = 1.6,
			minsize = 1.5,
			maxsize = 4.0,
			texture = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:1",
			glow = 14,
		})
	end,
})

-- 5. Vintage Flash Camera Tool
local camera_cooldowns = {}

local function trigger_flash_camera(itemstack, user, _pointed_thing)
	if not user or not user:is_player() then return itemstack end
	local name = user:get_player_name()
	local now = core.get_gametime()

	if camera_cooldowns[name] and now - camera_cooldowns[name] < 7.0 then
		local remain = 7.0 - (now - camera_cooldowns[name])
		core.chat_send_player(name, core.colorize("#ff8888",
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

	-- 4. Spark and smoke particles in front of the camera lens
	core.add_particlespawner({
		amount = 25,
		time = 0.2,
		pos = {
			min = vector.add(eye_pos, vector.multiply(look_dir, 0.5)),
			max = vector.add(eye_pos, vector.multiply(look_dir, 0.8)),
		},
		vel = {
			min = vector.multiply(look_dir, 2.0),
			max = vector.multiply(look_dir, 6.0),
		},
		acc = {min = {x = -1, y = -1, z = -1}, max = {x = 1, y = 1, z = 1}},
		exptime = {min = 0.2, max = 0.6},
		size = {min = 1.0, max = 3.0},
		jitter = {min = {x = -0.5, y = -0.5, z = -0.5}, max = {x = 0.5, y = 0.5, z = 0.5}},
		texpool = {
			{name = "pale_watcher_hud_flash.png", blend = "add"},
		},
		minpos = vector.add(eye_pos, vector.multiply(look_dir, 0.5)),
		maxpos = vector.add(eye_pos, vector.multiply(look_dir, 0.8)),
		minvel = vector.multiply(look_dir, 2.0),
		maxvel = vector.multiply(look_dir, 6.0),
		minacc = {x = -1, y = -1, z = -1},
		maxacc = {x = 1, y = 1, z = 1},
		minexptime = 0.2,
		maxexptime = 0.6,
		minsize = 1.0,
		maxsize = 3.0,
		texture = "pale_watcher_hud_flash.png",
		glow = 14,
	})

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
					luaent:on_stunned(user, 4.0)
					core.chat_send_player(name, core.colorize("#ffff55",
						"★ The blinding xenon flash stuns the Pale Watcher!"))
					break
				end
			end
		end
	end

	return itemstack
end

core.register_tool("pale_watcher:flash_camera", {
	description = "Vintage Flash Camera\n" ..
		core.colorize("#aaccff", "Right-Click: Release high-intensity xenon flash.\n") ..
		core.colorize("#ffff88", "• Stuns the Pale Watcher for 3-5s if in line of sight.\n") ..
		core.colorize("#e0e0e0", "• Illuminates deep darkness.\n") ..
		core.colorize("#88aaff", "Cooldown: 7 seconds."),
	short_description = "Flash Camera",
	inventory_image = "pale_watcher_flash_camera.png",
	wield_image = "pale_watcher_flash_camera.png",
	stack_max = 1,

	on_secondary_use = trigger_flash_camera,
	on_place = trigger_flash_camera,
})

-- 6. Dimensional Cloth Drop Item
core.register_craftitem("pale_watcher:dimensional_cloth", {
	description = "Dimensional Cloth\n" ..
		core.colorize("#bbaaff", "A torn scrap of void fabric with crimson thread.\nUsed to craft the Shroud of Stalking."),
	short_description = "Dimensional Cloth",
	inventory_image = "pale_watcher_dimensional_cloth.png",
	wield_image = "pale_watcher_dimensional_cloth.png",
	stack_max = 16,
	groups = {rare = 1},
})

-- 7. Shroud of Stalking (Blink Teleport Item)
local blink_cooldowns = {}
core.register_tool("pale_watcher:shroud_of_stalking", {
	description = "Shroud of Stalking\n" ..
		core.colorize("#c0b0ff", "Sneak + Right-Click to Blink forward into the shadows (14m).\n") ..
		core.colorize("#888888", "Cooldown: 4 seconds."),
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

		-- Ensure ground support below target
		local under = vector.round(vector.subtract(target_pos, {x = 0, y = 1, z = 0}))
		local under_def = core.registered_nodes[core.get_node(under).name]
		if not under_def or not under_def.walkable then
			-- Try snapping downward
			for y_off = 1, 3 do
				local test_under = vector.subtract(under, {x = 0, y = y_off, z = 0})
				local t_def = core.registered_nodes[core.get_node(test_under).name]
				if t_def and t_def.walkable then
					target_pos = vector.add(test_under, {x = 0, y = 1, z = 0})
					break
				end
			end
		end

		-- Departure particles
		core.add_particlespawner({
			amount = 30,
			time = 0.3,
			pos = {min = vector.subtract(p_pos, 0.5), max = vector.add(p_pos, 0.5)},
			vel = {min = {x = -1, y = 0.5, z = -1}, max = {x = 1, y = 2, z = 1}},
			texpool = {
				{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
				{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
				{name = "pale_watcher_particles.png^[verticalframe:8:7", blend = "add"},
			},
			minpos = vector.subtract(p_pos, 0.5),
			maxpos = vector.add(p_pos, 0.5),
			minvel = {x = -1, y = 0.5, z = -1},
			maxvel = {x = 1, y = 2, z = 1},
			minacc = {x = 0, y = -1, z = 0},
			maxacc = {x = 0, y = -0.5, z = 0},
			minexptime = 0.5,
			maxexptime = 1.0,
			minsize = 1.0,
			maxsize = 2.5,
			texture = "pale_watcher_particles.png^[verticalframe:8:0",
		})
		core.sound_play("pale_watcher_static", {pos = p_pos, gain = 0.5, max_hear_distance = 15}, true)

		-- Execute Blink teleport
		user:set_pos(target_pos)

		-- Arrival particles
		core.add_particlespawner({
			amount = 30,
			time = 0.3,
			pos = {min = vector.subtract(target_pos, 0.5), max = vector.add(target_pos, 0.5)},
			vel = {min = {x = -1, y = 0.5, z = -1}, max = {x = 1, y = 2, z = 1}},
			texpool = {
				{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
				{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
				{name = "pale_watcher_particles.png^[verticalframe:8:7", blend = "add"},
			},
			minpos = vector.subtract(target_pos, 0.5),
			maxpos = vector.add(target_pos, 0.5),
			minvel = {x = -1, y = 0.5, z = -1},
			maxvel = {x = 1, y = 2, z = 1},
			minacc = {x = 0, y = -1, z = 0},
			maxacc = {x = 0, y = -0.5, z = 0},
			minexptime = 0.5,
			maxexptime = 1.0,
			minsize = 1.0,
			maxsize = 2.5,
			texture = "pale_watcher_particles.png^[verticalframe:8:0",
		})
		core.sound_play("pale_watcher_static", {pos = target_pos, gain = 0.5, max_hear_distance = 15}, true)

		return itemstack
	end,
})

-- Static Core drop item
core.register_craftitem("pale_watcher:static_core", {
	description = "Static Core\n" .. core.colorize("#aaccff", "A condensed sphere of quantum radio noise."),
	short_description = "Static Core",
	inventory_image = "pale_watcher_hud_static_1.png",
	stack_max = 16,
	groups = {rare = 1},
})

-- Crafting Recipes
-- 1. Ritual Pyre Recipe (Stone + Wood + Torch/Coal)
core.register_craft({
	output = "pale_watcher:ritual_pyre",
	recipe = {
		{"group:stone", "group:wood", "group:stone"},
		{"group:wood",  "group:torch", "group:wood"},
		{"group:stone", "group:wood", "group:stone"},
	},
})
-- Fallback with coal if torch group not present
core.register_craft({
	output = "pale_watcher:ritual_pyre",
	recipe = {
		{"group:stone", "group:wood", "group:stone"},
		{"group:wood",  "group:coal", "group:wood"},
		{"group:stone", "group:wood", "group:stone"},
	},
})

-- 2. Flash Camera Recipe
core.register_craft({
	output = "pale_watcher:flash_camera",
	recipe = {
		{"", "group:torch", ""},
		{"group:steel_ingot", "group:glass", "group:steel_ingot"},
		{"group:steel_ingot", "group:steel_ingot", "group:steel_ingot"},
	},
})
-- Fallback for default steel/glass
core.register_craft({
	output = "pale_watcher:flash_camera",
	recipe = {
		{"", "default:torch", ""},
		{"default:steel_ingot", "default:glass", "default:steel_ingot"},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
	},
})

-- 3. Shroud of Stalking Recipe (4x Dimensional Cloth + Static Core)
core.register_craft({
	output = "pale_watcher:shroud_of_stalking",
	recipe = {
		{"pale_watcher:dimensional_cloth", "pale_watcher:static_core", "pale_watcher:dimensional_cloth"},
		{"pale_watcher:dimensional_cloth", "", "pale_watcher:dimensional_cloth"},
		{"", "", ""},
	},
})

-- LBM to purge any transient flash light nodes on mapblock load / server reboot
core.register_lbm({
	name = "pale_watcher:purge_transient_lights",
	nodenames = {"pale_watcher:flash_light"},
	run_at_every_load = true,
	action = function(pos)
		core.remove_node(pos)
	end,
})

return pale_watcher.nodes
