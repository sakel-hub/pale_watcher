--[[
	pale_watcher - World Encounter Nodes
	Cursed Page, Ritual Pyre, Burning Cleansing Flame, and Flash Light.
]]

pale_watcher.nodes = pale_watcher.nodes or {}

local colors = pale_watcher.colors
local S = pale_watcher.S

-- Transient invisible light node created during camera flash
core.register_node("pale_watcher:flash_light", {
	description = S("Flash Light"),
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

-- Cursed Page (Wall-Mounted Node)
local function collect_page(pos, player)
	if not player or not player:is_player() then return end

	-- Burning paper particle effect (preset)
	pale_watcher.particles.page_pickup(pos)

	-- Sound of burning paper
	core.sound_play("pale_watcher_paper_burn", {pos = pos, max_hear_distance = 25}, true)

	-- Notify session manager (tracks progress in session & HUD only - zero inventory clutter)
	pale_watcher.ritual.on_page_collected(pos, player)

	-- Remove page node cleanly
	core.remove_node(pos)
end

core.register_node("pale_watcher:cursed_page", {
	description = S("Cursed Page"),
	short_description = S("Cursed Page"),
	drawtype = "signlike",
	tiles = {"pale_watcher_cursed_page.png"},
	inventory_image = "pale_watcher_cursed_page_item.png",
	wield_image = "pale_watcher_cursed_page_item.png",
	drop = "",
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
		-- Start ambient particle wisp & subtle ink whisper loop
		core.get_node_timer(pos):start(4.0)
	end,

	on_timer = function(pos, elapsed)
		local meta = core.get_meta(pos)
		local age = meta:get_int("age") + math.floor(elapsed)
		meta:set_int("age", age)

		-- Orphan check: if session ended or server rebooted without active session, purge immediately
		local sid = meta:get_string("session_id")
		if sid ~= "" and not pale_watcher.ritual.is_session_active(sid) then
			core.remove_node(pos)
			return false
		end

		-- Clean up inactive pages after 600s TTL strictly if not attached to an active session
		if age > 600 and (sid == "" or not pale_watcher.ritual.is_session_active(sid)) then
			core.remove_node(pos)
			return false
		end

		-- Proximity audio whisper and ambient particles if any player is within 24 nodes
		local players = core.get_connected_players()
		local has_nearby = false
		for i = 1, #players do
			local p_pos = players[i]:get_pos()
			if p_pos then
				local dx = pos.x - p_pos.x
				local dy = pos.y - p_pos.y
				local dz = pos.z - p_pos.z
				if (dx * dx + dy * dy + dz * dz) <= 576.0 then -- 24 blocks
					has_nearby = true
					break
				end
			end
		end

		if has_nearby then
			core.sound_play("pale_watcher_page_whisper", {
				pos = pos,
				gain = 0.55,
				max_hear_distance = 24,
			}, true)

			-- Subtle black ink wisp particle spawner (preset)
			pale_watcher.particles.page_ambient(pos)
		end

		return true -- Continue running timer
	end,

	on_rightclick = function(pos, _node, clicker, _itemstack, _pointed_thing)
		collect_page(pos, clicker)
	end,

	on_punch = function(pos, _node, puncher, _pointed_thing)
		collect_page(pos, puncher)
	end,

	on_dig = function(pos, _node, digger)
		collect_page(pos, digger)
		return true
	end,
})

-- Cursed Page Drop Craftitem (fallback if dug with tools)
core.register_craftitem("pale_watcher:cursed_page_item", {
	description = S("Cursed Page") .. "\n" ..
		core.colorize(colors.whisper, S("A torn parchment inscribed with eldritch scrawls.")),
	short_description = S("Cursed Page"),
	inventory_image = "pale_watcher_cursed_page_item.png",
	wield_image = "pale_watcher_cursed_page_item.png",
	stack_max = 16,
	groups = {not_in_creative_inventory = 1},

	on_use = function(itemstack, user, _pointed_thing)
		if not user or not user:is_player() then return itemstack end
		local name = user:get_player_name()
		local session = pale_watcher.ritual.get_player_session(name, user:get_pos())
		if session then
			pale_watcher.ritual.on_page_collected(user:get_pos(), user)
			itemstack:take_item(1)
			core.sound_play("pale_watcher_paper_burn", {to_player = name}, true)
			core.chat_send_player(name,
				core.colorize(colors.pyre, S("★ You burn the cursed page in your hands, adding its soul to the ritual!")))
		else
			core.chat_send_player(name,
				core.colorize(colors.dimmed, S("The cursed ink hums weakly... There is no active ritual session nearby.")))
		end
		return itemstack
	end,
})

-- Ritual Pyre (Unlit Altar)
-- Attuned directly to the active Pale Watcher encounter session: no page items in inventory required
core.register_node("pale_watcher:ritual_pyre", {
	description = S("Ritual Pyre") .. "\n" ..
		core.colorize(colors.pyre, S("Attuned to the Cursed Pages in the active encounter.") .. "\n") ..
		core.colorize(colors.warning, S("Right-Click when all cursed pages are found to ignite the Cleansing Flame.")),
	short_description = S("Ritual Pyre"),
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
		meta:set_string("infotext", S("Ritual Pyre (Requires all Cursed Pages found in active encounter)"))
	end,

	on_destruct = function(pos)
		pale_watcher.particles.remove_pyre_flames(pos)
	end,

	after_destruct = function(pos, _oldnode)
		pale_watcher.particles.remove_pyre_flames(pos)
	end,

	on_rightclick = function(pos, node, clicker, _itemstack)
		if not clicker or not clicker:is_player() then return end
		local name = clicker:get_player_name()

		-- Check active session for this player / location
		local session, sid = pale_watcher.ritual.get_player_session(name, pos)
		if not session then
			core.chat_send_player(name,
				core.colorize(colors.dimmed, S("The Pyre remains cold. No dark presence is tethered here.")))
			return
		end

		if session.pages_collected < session.pages_total then
			local msg = S("The Pyre refuses to ignite... All Cursed Pages must be found! (@1/@2 Collected)",
				session.pages_collected, session.pages_total)
			core.chat_send_player(name, core.colorize(colors.danger, msg))

			-- Emit cold dark ash rejection particles (preset)
			pale_watcher.particles.pyre_cold_rejection(pos)
			core.sound_play("pale_watcher_bell", {pos = pos, gain = 0.4, max_hear_distance = 15}, true)
			return
		end

		-- All required pages collected: Ignite the Cleansing Flame directly from session progress!
		core.swap_node(pos, {name = "pale_watcher:ritual_pyre_burning", param2 = node.param2})
		core.sound_play("pale_watcher_paper_burn", {pos = pos, gain = 1.0, max_hear_distance = 40})
		local ignite_msg = S(
			"★ The @1 bound curses ignite the Cleansing Flame! The Pale Watcher is forcibly drawn into the pyre!",
			session.pages_total)
		core.chat_send_all(core.colorize(colors.pyre, ignite_msg))

		-- Start the burning pyre timer and towering flame particles
		core.get_node_timer(pos):start(45)
		pale_watcher.particles.pyre_roaring_flames(pos, 45)

		-- Begin Cleansing Flame Banishment Sequence
		pale_watcher.ritual.trigger_pyre_banishment(pos, clicker, sid)
	end,
})

-- Ritual Pyre (Burning Cleansing Flame)
core.register_node("pale_watcher:ritual_pyre_burning", {
	description = S("Cleansing Flame Pyre"),
	short_description = S("Cleansing Flame Pyre"),
	drawtype = "nodebox",
	paramtype = "light",
	light_source = 14,
	drop = "",
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
	groups = {cracky = 2, oddly_breakable_by_hand = 1, not_in_creative_inventory = 1},
	damage_per_second = 6,

	on_timer = function(pos)
		pale_watcher.particles.remove_pyre_flames(pos)
		pale_watcher.particles.pyre_cold_rejection(pos)
		core.sound_play("pale_watcher_paper_burn", {pos = pos, gain = 0.5, max_hear_distance = 15}, true)
		core.remove_node(pos)
		return false
	end,

	on_construct = function(pos)
		core.get_node_timer(pos):start(45) -- Cleansing flame burns for 45s then burns out to ashes
		-- Continuous roaring flame particles (preset with 45s lifespan)
		pale_watcher.particles.pyre_roaring_flames(pos, 45)
	end,

	on_destruct = function(pos)
		pale_watcher.particles.remove_pyre_flames(pos)
	end,

	after_destruct = function(pos, _oldnode)
		pale_watcher.particles.remove_pyre_flames(pos)
	end,

	after_dig_node = function(pos, _oldnode, _oldmetadata, _digger)
		pale_watcher.particles.remove_pyre_flames(pos)
	end,

	on_flood = function(pos, _oldnode, _newnode)
		pale_watcher.particles.remove_pyre_flames(pos)
		pale_watcher.particles.pyre_cold_rejection(pos)
		core.sound_play("pale_watcher_paper_burn", {pos = pos, gain = 0.5, max_hear_distance = 15}, true)
		return false
	end,
})

return pale_watcher.nodes
