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
---@field ritual table Dynamically scaling cursed page ritual session manager
---@field colors table Semantic chat & HUD color palette
pale_watcher = pale_watcher or {}
pale_watcher.physics = pale_watcher.physics or {}
pale_watcher.fx = pale_watcher.fx or {}
pale_watcher.particles = pale_watcher.particles or {}
pale_watcher.nodes = pale_watcher.nodes or {}
pale_watcher.items = pale_watcher.items or {}
pale_watcher.ritual = pale_watcher.ritual or {}

---Semantic UI & chat feedback color palette for high legibility
pale_watcher.colors = {
	whisper  = "#ffddaa", -- Cursed page survival whispers
	warning  = "#ffff55", -- Flash stun / page count warnings
	danger   = "#ff3333", -- High dread / cursed collection
	pyre     = "#ffaa33", -- Ritual pyre messages
	victory  = "#55ff88", -- Pyre banishment / sanctuary holding / gauntlet escape
	void     = "#ff2222", -- Anti-bunker psychic choke
	system   = "#aaccff", -- Tool descriptions & camera status
	recharge = "#ff8888", -- Camera capacitor cooldown
	dimmed   = "#aaaaaa", -- Neutral / dormant status
}

---Curated, legally distinct horror color palettes (Body, Suit, Tie)
---Tuned with native Luanti `^[hsl:` texture modifiers for muted, desaturated horror tones.
pale_watcher.palettes = {
	abyssal_void = {
		name = "Abyssal Void (Obsidian Plum Suit & Withered Blood Wine Tie)",
		body = "pale_watcher_body.png^[hsl:-90:6:0",
		suit = "pale_watcher_suit.png^[hsl:-85:18:-25",
		tie  = "pale_watcher_tie.png^[hsl:-10:36:-15",
	},
	forest_wraith = {
		name = "Forest Wraith (Blackened Spruce Suit & Tarnished Brass Tie)",
		body = "pale_watcher_body.png^[hsl:120:5:0",
		suit = "pale_watcher_suit.png^[hsl:145:18:-25",
		tie  = "pale_watcher_tie.png^[hsl:42:32:-15",
	},
	quantum_slate = {
		name = "Quantum Slate (Cold Charcoal Steel Suit & Desaturated Amethyst Tie)",
		body = "pale_watcher_body.png^[hsl:-155:6:0",
		suit = "pale_watcher_suit.png^[hsl:-145:16:-22",
		tie  = "pale_watcher_tie.png^[hsl:-75:28:-15",
	},
	monochrome_noir = {
		name = "Monochrome Noir (Stark Noir Suit & Ash Charcoal Tie)",
		body = "pale_watcher_body.png",
		suit = "pale_watcher_suit.png^[hsl:0:0:-30",
		tie  = "pale_watcher_tie.png^[hsl:0:0:-10",
	},
}

---Ordered list of palette identifiers for deterministic or random selection.
pale_watcher.palette_keys = {
	"abyssal_void",
	"forest_wraith",
	"quantum_slate",
	"monochrome_noir",
}

-- Seed pseudo-random generator with high-resolution clock entropy to ensure varied palette selection
local random_seed = (core and core.get_us_time and core.get_us_time()) or os.time()
math.randomseed(tonumber(tostring(random_seed):reverse():sub(1, 9)) or random_seed)
for _ = 1, 3 do math.random() end

---Builds the 3-material texture array for the Pale Watcher model.
---Picks a curated palette at random if neither custom textures nor a palette key are provided.
---@param suit_mod? string Optional suit texture with modifier
---@param tie_mod? string Optional tie texture with modifier
---@param palette_key? string Optional specific palette name from pale_watcher.palettes
---@param body_mod? string Optional body texture with modifier
---@return string[] textures Array of 3 material textures: {body, suit, tie}
---@return string chosen_key Name of the chosen color palette
function pale_watcher.get_textures(suit_mod, tie_mod, palette_key, body_mod)
	local p_key = palette_key
	if not p_key or not pale_watcher.palettes[p_key] then
		p_key = pale_watcher.palette_keys[math.random(#pale_watcher.palette_keys)]
	end
	local p = pale_watcher.palettes[p_key] or pale_watcher.palettes.abyssal_void
	return {
		body_mod or p.body or "pale_watcher_body.png",
		suit_mod or p.suit,
		tie_mod or p.tie,
	}, p_key
end

---Spawns a Pale Watcher entity at the specified world coordinate.
---@param pos Vector World position
---@param palette_key? string Optional palette key from pale_watcher.palettes (random if omitted)
---@return ObjectRef|nil mob_obj Spawned ObjectRef or nil
function pale_watcher.spawn(pos, palette_key)
	local chosen_key = palette_key
	if not chosen_key or not pale_watcher.palettes[chosen_key] then
		chosen_key = pale_watcher.palette_keys[math.random(#pale_watcher.palette_keys)]
	end
	local staticdata = core.serialize({palette_name = chosen_key})
	return core.add_entity(pos, "pale_watcher:pale_watcher", staticdata)
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

