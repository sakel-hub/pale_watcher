--[[
	pale_watcher - The Pale Watcher Horror Mob
	Public API Namespace & Horror Subsystem Delegation
]]

---@class PaleWatcher
---@field physics table Universal multi-mod physics abstraction
---@field fx table HUD static interference, responsive vignette, and audio feedback
---@field particles table Universal particle factory & visual presets
---@field nodes table Cursed Page and Ritual Pyre world structures
---@field items table Wieldable tools and artifact materials
---@field ritual table 8-page soul-burn ritual session manager
---@field colors table Semantic chat & HUD color palette
pale_watcher = {
	physics = {},
	fx = {},
	particles = {},
	nodes = {},
	items = {},
	ritual = {},
}

---Semantic UI & chat feedback color palette for high legibility
pale_watcher.colors = {
	whisper  = "#ffddaa", -- Cursed page survival whispers
	warning  = "#ffff55", -- Flash stun / page count warnings
	danger   = "#ff3333", -- High dread / cursed collection
	pyre     = "#ffaa33", -- Ritual pyre messages
	victory  = "#55ff88", -- Dawn banishment / sanctuary holding / gauntlet escape
	void     = "#ff2222", -- Anti-bunker psychic choke
	system   = "#aaccff", -- Tool descriptions & camera status
	recharge = "#ff8888", -- Camera capacitor cooldown
	dimmed   = "#aaaaaa", -- Neutral / dormant status
}

---Curated, legally distinct horror color palettes (Body, Suit, Tie)
pale_watcher.palettes = {
	abyssal_void = {
		name = "Abyssal Void (Obsidian Plum Suit & Withered Blood Wine Tie)",
		suit = "pale_watcher_suit.png^[colorize:#161324:200",
		tie = "pale_watcher_tie.png^[colorize:#4f0d1b:220",
	},
	forest_wraith = {
		name = "Forest Wraith (Blackened Spruce Suit & Tarnished Brass Tie)",
		suit = "pale_watcher_suit.png^[colorize:#0f1714:210",
		tie = "pale_watcher_tie.png^[colorize:#56451e:220",
	},
	quantum_slate = {
		name = "Quantum Slate (Cold Charcoal Steel Suit & Desaturated Amethyst Tie)",
		suit = "pale_watcher_suit.png^[colorize:#161920:200",
		tie = "pale_watcher_tie.png^[colorize:#382042:220",
	},
	monochrome_noir = {
		name = "Monochrome Noir (Pure Greyscale Contrast)",
		suit = "pale_watcher_suit.png^[colorize:#1c1c1c:180",
		tie = "pale_watcher_tie.png^[colorize:#333333:180",
	},
}

---Builds the 3-material texture array for the Pale Watcher model.
---@param suit_mod? string Optional suit texture with modifier
---@param tie_mod? string Optional tie texture with modifier
---@return string[]
function pale_watcher.get_textures(suit_mod, tie_mod)
	local p = pale_watcher.palettes.abyssal_void
	return {
		"pale_watcher_body.png",
		suit_mod or p.suit,
		tie_mod or p.tie,
	}
end

---Spawns a Pale Watcher entity at the specified world coordinate.
---@param pos Vector World position
---@return ObjectRef|nil mob_obj Spawned ObjectRef or nil
function pale_watcher.spawn(pos)
	return core.add_entity(pos, "pale_watcher:pale_watcher")
end

---Checks whether a target point is visually unobstructed by opaque solid terrain.
---Foliage (leaves, flora) and transparent blocks (glass) do not block line of sight for horror mob detection.
---@param p1 Vector Observer eye position
---@param p2 Vector Target mob sample position
---@return boolean is_visible
function pale_watcher.has_visual_los(p1, p2)
	if core.line_of_sight(p1, p2) then
		return true
	end

	for pt in core.raycast(p1, p2, false, false) do
		if pt.type == "node" then
			local node = core.get_node(pt.under)
			local def = core.registered_nodes[node.name]
			if def and def.walkable then
				local is_semi_transparent = (core.get_item_group(node.name, "leaves") > 0) or
					(core.get_item_group(node.name, "flora") > 0) or
					def.sunlight_propagates or
					(def.drawtype == "allfaces" or def.drawtype == "allfaces_optional" or
					 def.drawtype == "glasslike" or def.drawtype == "glasslike_framed")
				if not is_semi_transparent then
					return false
				end
			end
		end
	end
	return true
end

---Tests if a node is solid walkable ground and not a liquid.
---@param node_name string
---@return boolean
function pale_watcher.is_walkable_ground(node_name)
	local def = core.registered_nodes[node_name]
	return (def and def.walkable and def.liquidtype == "none") and true or false
end

---Tests if a node is passable (air or non-walkable non-liquid like flora, torches).
---@param node_name string
---@return boolean
function pale_watcher.is_passable_node(node_name)
	if node_name == "air" then
		return true
	end
	local def = core.registered_nodes[node_name]
	if not def then
		return true
	end
	return (not def.walkable) and (def.liquidtype == "none")
end

---Checks if an area above ground has clear vertical headroom.
---@param pos Vector Base ground position
---@param height integer Headroom height in blocks to verify (e.g. 3 or 4)
---@return boolean
function pale_watcher.has_clear_headroom(pos, height)
	for y_off = 1, height do
		local check_pos = {x = pos.x, y = pos.y + y_off, z = pos.z}
		if not pale_watcher.is_passable_node(core.get_node(check_pos).name) then
			return false
		end
	end
	return true
end

---Scans vertically at (x, z) around y_center to find a solid walkable ground node with clear headroom.
---@param x number X coordinate
---@param y_center number Center Y elevation
---@param z number Z coordinate
---@param search_up integer How many blocks above y_center to search (e.g. 4)
---@param search_down integer How many blocks below y_center to search (e.g. 6)
---@param required_headroom? integer Blocks of headroom needed (default 3)
---@return Vector|nil ground_pos Vector of solid ground node, or nil if none found
function pale_watcher.find_ground_node(x, y_center, z, search_up, search_down, required_headroom)
	local cx = math.floor(x + 0.5)
	local cz = math.floor(z + 0.5)
	local headroom = required_headroom or 3

	for dy = search_up, -search_down, -1 do
		local gy = math.floor(y_center + dy + 0.5)
		local g_pos = {x = cx, y = gy, z = cz}
		if pale_watcher.is_walkable_ground(core.get_node(g_pos).name) then
			if pale_watcher.has_clear_headroom(g_pos, headroom) then
				return g_pos
			end
		end
	end
	return nil
end

return pale_watcher

