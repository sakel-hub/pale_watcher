--[[
	pale_watcher - The Pale Watcher Horror Mob
	Public API Namespace & Horror Subsystem Delegation
]]

---@class PaleWatcher
---@field physics table Universal multi-mod physics abstraction
---@field fx table HUD static interference, responsive vignette, and audio feedback
---@field nodes table Cursed Page, Ritual Pyre, Flash Camera, and Dimensional artifacts
---@field ritual table 8-page soul-burn ritual session manager
---@field distance_sq fun(p1: Vector, p2: Vector): number Calculates squared Euclidean distance
---@field distance fun(p1: Vector, p2: Vector): number Calculates Euclidean distance
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

---Calculates the squared Euclidean distance between two 3D positions.
---Optimized for performance to bypass expensive square root operations in hot loops and spatial checks.
---@param p1 Vector First position
---@param p2 Vector Second position
---@return number Squared distance, or math.huge if either vector is nil
function pale_watcher.distance_sq(p1, p2)
	if not p1 or not p2 then return math.huge end
	local dx = p1.x - p2.x
	local dy = p1.y - p2.y
	local dz = p1.z - p2.z
	return dx * dx + dy * dy + dz * dz
end

---Calculates the Euclidean distance between two 3D positions using standard Luanti API.
---@param p1 Vector First position
---@param p2 Vector Second position
---@return number Euclidean distance
function pale_watcher.distance(p1, p2)
	return vector.distance(p1, p2)
end

return pale_watcher

