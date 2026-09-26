--[[
	pale_watcher - The Pale Watcher Horror Mob
	Public API Namespace & Horror Subsystem Delegation
]]

---@class PaleWatcher
---@field physics table Universal multi-mod physics abstraction
---@field fx table HUD static interference, responsive vignette, and audio feedback
---@field nodes table Cursed Page, Ritual Pyre, Flash Camera, and Dimensional artifacts
---@field ritual table 8-page soul-burn ritual session manager
pale_watcher = {
	physics = {},
	fx = {},
	nodes = {},
	ritual = {},
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

	local ray = core.raycast(p1, p2, false, false)
	if not ray then return false end

	for pt in ray do
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

return pale_watcher

