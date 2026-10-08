--[[
	pale_watcher - The Pale Watcher Horror Mob Entity Definition
	Quantum Stalking, Blind-Spot Step Teleportation, Trajectory Intercepts,
	Anti-Bunker Curse, Light Extinguishing, Combat Dimensional Slip,
	Flash Stun Window, Day/Night Horror Stalking, and Cleansing Flame Implosion.
]]

local S = pale_watcher.S
local colors = pale_watcher.colors

local WATCHER_FOV_DOT = 0.55
local WATCHER_TETHER_MAX = pale_watcher.TETHER_MAX or
	(tonumber(core.settings:get("pale_watcher_tether_radius")) or 100.0)
local WATCHER_AMBUSH_DIST = pale_watcher.AMBUSH_DIST or math.max(20.0, WATCHER_TETHER_MAX - 15.0)
local MAX_OBSERVE_DIST_SQ = (WATCHER_TETHER_MAX + 15.0) * (WATCHER_TETHER_MAX + 15.0)

local OBSERVATION_POINTS = {
	{x = 0, y = 2.6, z = 0}, -- Head / Eyes
	{x = 0, y = 1.6, z = 0}, -- Chest / Center of mass (aligns with player eye level ~1.625)
	{x = 0, y = 0.8, z = 0}, -- Torso / Waist
}

local EXTINGUISH_LIGHT_NODES = {
	"group:torch",
	"group:torches",
	"group:candle",
	"group:candles",
	"group:lit_candles",
	"group:lantern",
	"group:lanterns",
	"group:campfire",
	"default:torch",
	"default:torch_wall",
	"default:torch_ceiling",
	"default:meselamp",
}

---Checks if a node is an extinguishable flame light (torch, candle, lantern, campfire).
---@param name string Node or item name
---@return boolean is_flame
local function is_extinguishable_light(name)
	return (core.get_item_group(name, "torch") > 0)
		or (core.get_item_group(name, "torches") > 0)
		or (core.get_item_group(name, "candle") > 0)
		or (core.get_item_group(name, "candles") > 0)
		or (core.get_item_group(name, "lit_candles") > 0)
		or (core.get_item_group(name, "lantern") > 0)
		or (core.get_item_group(name, "lanterns") > 0)
		or (core.get_item_group(name, "campfire") > 0)
end

local AIR_NODE_LIST = {"air"}
local scratch_minp = {x = 0, y = 0, z = 0}
local scratch_maxp = {x = 0, y = 0, z = 0}
local scratch_light_minp = {x = 0, y = 0, z = 0}
local scratch_light_maxp = {x = 0, y = 0, z = 0}

---Checks whether a target point is visually unobstructed by opaque solid terrain.
---Foliage (leaves, flora) and transparent blocks (glass) do not block line of sight for horror mob detection.
local has_visual_los = pale_watcher.has_visual_los

local scratch_eye = {x = 0, y = 0, z = 0}
local scratch_sample = {x = 0, y = 0, z = 0}

---Determines whether any connected living player is observing the mob within line of sight.
---Tests multiple points across the 3.2m tall entity (head, chest, torso) to ensure reliable
---quantum locking even in dense foliage, behind low obstacles, or at close proximity.
---Optimized for LuaJIT trace compilation with zero table allocations in the per-step loop.
---@param pos Vector Entity world position
---@param players ObjectRef[] Connected players list
---@return boolean is_seen True if observed by a player
---@return ObjectRef|nil observer First observer player ObjectRef
local function is_observed(pos, players)
	for i = 1, #players do
		local player = players[i]
		if x_mob_core.is_player_alive(player) then
			local p_pos = player:get_pos()
			if p_pos then
				local dx = pos.x - p_pos.x
				local dy = pos.y - p_pos.y
				local dz = pos.z - p_pos.z
				local dist_sq = dx * dx + dy * dy + dz * dz
				local max_dist_sq = MAX_OBSERVE_DIST_SQ
				local has_fog, fog_dist = pale_watcher.fx.get_fog_status(player)
				if has_fog then
					-- Cannot observe, zoom FOV, or quantum-lock through opaque fog beyond visible range
					max_dist_sq = fog_dist * fog_dist
				end
				if dist_sq <= max_dist_sq then
					scratch_eye.x = p_pos.x
					scratch_eye.y = p_pos.y + 1.625
					scratch_eye.z = p_pos.z

					local look_dir = player:get_look_dir()

					for pt_idx = 1, #OBSERVATION_POINTS do
						local opt = OBSERVATION_POINTS[pt_idx]
						local sx = pos.x + opt.x
						local sy = pos.y + opt.y
						local sz = pos.z + opt.z

						local tox = sx - scratch_eye.x
						local toy = sy - scratch_eye.y
						local toz = sz - scratch_eye.z
						local len_sq = tox * tox + toy * toy + toz * toz

						if len_sq > 0.001 then
							local inv_len = 1.0 / math.sqrt(len_sq)
							local dot = (look_dir.x * tox + look_dir.y * toy + look_dir.z * toz) * inv_len

							if dot >= WATCHER_FOV_DOT then
								scratch_sample.x = sx
								scratch_sample.y = sy
								scratch_sample.z = sz
								if has_visual_los(scratch_eye, scratch_sample) then
									return true, player
								end
							end
						end
					end
				end
			end
		end
	end
	return false, nil
end

---Finds a safe walkable node in the player's blind spots (outside FOV or behind tree/terrain occlusion).
---@param target_player ObjectRef
---@param _current_mob_pos Vector
---@param step_min_dist number Minimum step distance (e.g. 6m)
---@param step_max_dist number Maximum step distance (e.g. 16m)
---@return Vector|nil candidate_pos
local function find_blind_spot_node(target_player, _current_mob_pos, step_min_dist, step_max_dist)
	local p_pos = target_player:get_pos()
	if not p_pos then return nil end
	local p_eye = vector.add(p_pos, {x = 0, y = 1.625, z = 0})
	local look_dir = target_player:get_look_dir()

	-- Generate candidate angles biased towards the player's rear and flanks
	local p_yaw = core.dir_to_yaw(look_dir)
	local test_angles = {
		p_yaw + math.pi,                -- Directly behind
		p_yaw + math.pi * 0.80,         -- Deep rear left
		p_yaw - math.pi * 0.80,         -- Deep rear right
		p_yaw + math.pi * 0.65,         -- Rear left
		p_yaw - math.pi * 0.65,         -- Rear right
		p_yaw + math.pi * 0.50,         -- Flank left
		p_yaw - math.pi * 0.50,         -- Flank right
		p_yaw + (math.random() - 0.5) * math.pi * 1.6 -- Random variation
	}

	-- Shuffle candidate angles so the watcher appears at varying flank and rear positions
	-- rather than deterministically standing directly behind the player's back every time.
	for i = #test_angles, 2, -1 do
		local j = math.random(i)
		test_angles[i], test_angles[j] = test_angles[j], test_angles[i]
	end

	for i = 1, #test_angles do
		local angle = test_angles[i]
		local dist = math.random(step_min_dist, step_max_dist)
		local cand_x = p_pos.x - math.sin(angle) * dist
		local cand_z = p_pos.z + math.cos(angle) * dist

		-- Scan terrain near player elevation with clear headroom
		local ground = pale_watcher.find_ground_node(cand_x, p_pos.y, cand_z, 4, 10, 3)
		if ground then
			local dest = {x = ground.x, y = ground.y + 0.50, z = ground.z}
			local dest_eye = {x = dest.x, y = dest.y + 2.8, z = dest.z}
			local to_dest = vector.direction(p_eye, dest_eye)

			-- Verify blind spot: either outside player's forward view cone OR occluded by terrain
			local is_in_blind_spot = (vector.dot(look_dir, to_dest) < WATCHER_FOV_DOT) or
				not has_visual_los(p_eye, dest_eye)

			if is_in_blind_spot then
				return dest
			end
		end
	end
	return nil
end

---Finds a guaranteed safe, walkable retreat position in the distance away from the player.
---Prioritizes distant blind spots with line-of-sight occlusion, radial sweeps, and fallback ground offsets.
---@param target_player ObjectRef
---@param current_mob_pos Vector
---@return Vector escape_pos
local function find_guaranteed_retreat_pos(target_player, current_mob_pos)
	-- Tier 1 & 2: Prefer true blind spot with line-of-sight occlusion
	local cand = find_blind_spot_node(target_player, current_mob_pos, 26, 38)
	if cand then return cand end
	cand = find_blind_spot_node(target_player, current_mob_pos, 16, 24)
	if cand then return cand end

	local p_pos = target_player:get_pos()
	if not p_pos then return current_mob_pos end

	local look_dir = target_player:get_look_dir()
	local p_yaw = core.dir_to_yaw(look_dir)

	-- Tier 3: Scan 12 angles around player at varying distances (28m down to 16m)
	for dist = 28, 16, -6 do
		for step = 0, 11 do
			local angle = p_yaw + math.pi + ((step - 5.5) * (math.pi / 6.0))
			local cx = p_pos.x - math.sin(angle) * dist
			local cz = p_pos.z + math.cos(angle) * dist
			local ground = pale_watcher.find_ground_node(cx, p_pos.y, cz, 5, 12, 3)
			if ground then
				return {x = ground.x, y = ground.y + 0.50, z = ground.z}
			end
		end
	end

	-- Tier 4: Search straight behind the player
	local inv_dir = vector.multiply(vector.normalize({x = look_dir.x, y = 0, z = look_dir.z}), -1)
	for d = 24, 12, -4 do
		local cx = p_pos.x + inv_dir.x * d
		local cz = p_pos.z + inv_dir.z * d
		local ground = pale_watcher.find_ground_node(cx, p_pos.y, cz, 4, 10, 3)
		if ground then
			return {x = ground.x, y = ground.y + 0.50, z = ground.z}
		end
	end

	-- Tier 5: Absolute emergency fallback (offset horizontally from player)
	local ground = pale_watcher.find_ground_node(p_pos.x + inv_dir.x * 20, p_pos.y, p_pos.z + inv_dir.z * 20, 4, 8, 3)
	if ground then
		return {x = ground.x, y = ground.y + 0.50, z = ground.z}
	end
	return vector.add(p_pos, {x = inv_dir.x * 20, y = 0.0, z = inv_dir.z * 20})
end

---Finds a safe, walkable ground position directly in front of the player for the gauntlet intercept ambush.
---Guarantees solid footing and 4 blocks of clear vertical headroom so The Pale Watcher (3.2m tall)
---never spawns inside blocks, underground, or at player foot level.
---@param target_player ObjectRef
---@param preferred_dist? number Preferred forward distance (default 10)
---@return Vector|nil ambush_pos
local function find_intercept_ambush_pos(target_player, preferred_dist)
	local p_pos = target_player:get_pos()
	if not p_pos then return nil end
	local p_look = target_player:get_look_dir()
	local dists = {preferred_dist or 8.0, 6.0, 10.0, 5.0, 12.0}

	local fwd_x = p_look.x
	local fwd_z = p_look.z
	local len = math.sqrt(fwd_x * fwd_x + fwd_z * fwd_z)
	local base_yaw
	if len > 0.01 then
		fwd_x = fwd_x / len
		fwd_z = fwd_z / len
		base_yaw = core.dir_to_yaw({x = fwd_x, y = 0, z = fwd_z})
	else
		base_yaw = target_player:get_look_horizontal() or 0
	end

	-- Test angles centered on player's forward view
	local angle_offsets = {0, 0.25, -0.25, 0.5, -0.5}

	for d_idx = 1, #dists do
		local dist = dists[d_idx]
		for a_idx = 1, #angle_offsets do
			local angle = base_yaw + angle_offsets[a_idx]
			local cand_x = p_pos.x - math.sin(angle) * dist
			local cand_z = p_pos.z + math.cos(angle) * dist

			local ground = pale_watcher.find_ground_node(cand_x, p_pos.y, cand_z, 4, 7, 3)
			if ground then
				return {x = ground.x, y = ground.y + 0.50, z = ground.z}
			end
		end
	end

	return nil
end

---Counts nearby air blocks around a player to detect underground bunker exploits.
---Optimized using core.find_nodes_in_area to avoid 27 per-tick table allocations.
---@param player_pos Vector
---@return integer air_count
local function count_surrounding_air(player_pos)
	local px = math.floor(player_pos.x + 0.5)
	local py = math.floor(player_pos.y + 0.5)
	local pz = math.floor(player_pos.z + 0.5)
	scratch_minp.x, scratch_minp.y, scratch_minp.z = px - 1, py, pz - 1
	scratch_maxp.x, scratch_maxp.y, scratch_maxp.z = px + 1, py + 2, pz + 1
	return #core.find_nodes_in_area(scratch_minp, scratch_maxp, AIR_NODE_LIST)
end

---Calculates the effective fleshy punch damage taking target armor into account.
---Ensures high-tier armor (such as Mithril) cannot reduce damage to 0,
---while keeping low-tier or unarmored players from being unfairly one-shot.
---Uses the same inverse mitigation scaling pattern as x_bows.
---@param target ObjectRef Target player
---@param base_damage number Base fleshy damage
---@param min_mitigation_ratio? number Minimum damage ratio (default 0.25 = 25% minimum damage)
---@param min_damage? number Minimum absolute damage to deal (default 2 HP)
---@return number punch_fleshy Value to pass in damage_groups.fleshy for player:punch
---@return number desired_damage Actual HP damage the player will receive
local function calculate_armor_scaled_punch(target, base_damage, min_mitigation_ratio, min_damage)
	if not target or not target:is_player() then
		return base_damage, base_damage
	end

	local armor_groups = target:get_armor_groups() or {}
	if (armor_groups.immortal or 0) > 0 then
		return 0, 0
	end

	local fleshy_group = armor_groups.fleshy or 100
	if fleshy_group <= 0 then
		return 0, 0
	end

	local normal_damage = base_damage * (fleshy_group / 100.0)
	local min_ratio = min_mitigation_ratio or 0.25
	local min_dmg = min_damage or 2
	local min_allowed = math.max(min_dmg, base_damage * min_ratio)
	local desired_damage = math.max(normal_damage, min_allowed)

	local punch_fleshy = desired_damage
	if fleshy_group < 100 then
		punch_fleshy = math.ceil(desired_damage * (100.0 / fleshy_group))
	end

	return punch_fleshy, desired_damage
end

---@class WatcherAttackOpts
---@field multiplier? number
---@field knockback_vel? Vector
---@field flash? boolean
---@field terror? boolean
---@field scare_sound? boolean
---@field particles? boolean
---@field anim_speed? number
---@field armor_div? number

---Executes a melee strike against a target player with configurable multipliers, knockback, and visual effects.
---@param self table Entity table
---@param target ObjectRef Target player
---@param pos Vector Mob position
---@param opts? WatcherAttackOpts Configuration options
local function execute_watcher_attack(self, target, pos, opts)
	opts = opts or {}
	local multiplier = opts.multiplier or 1.0
	local anim_speed = opts.anim_speed or 1.0
	local armor_div = opts.armor_div or 2

	x_mob_core.play_animation(self.object, "attack", {speed = anim_speed, loop = false, force = true})
	local punch_fleshy = calculate_armor_scaled_punch(target, self.damage * multiplier, 0.25, armor_div)
	target:punch(self.object, 1.0, {
		full_punch_interval = 1.0,
		damage_groups = {fleshy = punch_fleshy}
	})

	if opts.knockback_vel then
		target:add_velocity(opts.knockback_vel)
	end
	if opts.flash then
		pale_watcher.fx.trigger_flash(target)
	end
	if opts.terror then
		pale_watcher.physics.apply_terror(target)
	end
	if opts.scare_sound then
		core.sound_play("pale_watcher_scare", {pos = pos, gain = 1.0, max_hear_distance = 35}, true)
	end
	if opts.particles then
		pale_watcher.particles.void_mist(pos, 2.0, 20)
	end

	x_mob_core.play_sound(self, "attack", {to_player = target:get_player_name()})
end

---Centralized session cleanup for mob removal, death, or deactivation.
---@param self table Entity table
---@param removal? boolean True if permanently removed, false if mapblock unloaded
local function cleanup_entity_session(self, removal)
	if removal == false then
		-- Mapblock unloaded; preserve session for when player approaches again
		return
	end
	if self.session_id then
		pale_watcher.ritual.end_session(self.session_id, false)
		self.session_id = nil
	end
end

---Stun Window: Handles Flash Camera blinding stagger.
---@param self table
---@param dtime number
---@param players ObjectRef[]
---@param pos Vector
---@return boolean is_handling_stun
local function step_stun_window(self, dtime, players, pos)
	if self.stun_timer <= 0 then
		return false
	end

	self.stun_timer = self.stun_timer - dtime
	x_mob_core.halt_horizontal_velocity(self)

	if self.stun_timer <= 0 then
		-- Stun expired: Immediate guaranteed evasive phase retreat into distance
		local target = self.target_player or players[1]
		local escape_pos = find_guaranteed_retreat_pos(target, pos)

		-- Dramatic departure visual & audio at current position BEFORE teleporting
		pale_watcher.particles.teleport_rift(pos)
		core.sound_play("pale_watcher_scare", {pos = pos, gain = 0.8, max_hear_distance = 35}, true)

		self.object:set_velocity({x = 0, y = 0, z = 0})
		self.object:set_acceleration({x = 0, y = -9.81, z = 0})
		self.object:set_pos(escape_pos)
		local tpos = target and target:get_pos()
		if tpos then
			self.object:set_yaw(core.dir_to_yaw(vector.direction(escape_pos, tpos)))
		end

		-- Arrival puff & distant audio
		pale_watcher.particles.void_mist(escape_pos, 2.5, 25)
		core.sound_play("pale_watcher_static", {pos = escape_pos, gain = 0.6, max_hear_distance = 25}, true)
		x_mob_core.emit("pale_watcher:teleport_escaped", self, pos, escape_pos)

		self.state = "stalking"
	end

	return true
end

---Synchronizes ritual session HUD with nearby players.
---@param self table
---@param pos Vector
---@param dtime number
local function step_sync_hud(self, pos, dtime)
	self._hud_timer = (self._hud_timer or 0) + dtime
	if self._hud_timer >= 0.5 then
		self._hud_timer = 0
		if self.session_id and pale_watcher.ritual.is_session_active(self.session_id) then
			pale_watcher.ritual.update_session_players(self.session_id, pos)
		elseif not self.session_id or not pale_watcher.ritual.is_session_active(self.session_id) then
			-- Re-establish active encounter if Pale Watcher is alive in world near players
			local players = core.get_connected_players()
			for _, p in ipairs(players) do
				local p_pos = p:get_pos()
				if p_pos and vector.distance(p_pos, pos) <= 85.0 then
					self.session_id = pale_watcher.ritual.start_session(self.object, pos)
					self.origin_pos = pos
					self.saved_data.session_id = self.session_id
					break
				end
			end
		end
	end
end

---Target Acquisition using pre-filtered distance squared.
---@param self table
---@param pos Vector
---@param players ObjectRef[]
---@return ObjectRef|nil target
---@return Vector|nil target_pos
---@return number|nil distance
local function step_acquire_target(self, pos, players)
	local current_target = self.target or self.target_player
	if not current_target or not x_mob_core.is_player_alive(current_target) then
		local closest = nil
		local min_d_sq = WATCHER_TETHER_MAX * WATCHER_TETHER_MAX
		for i = 1, #players do
			local p = players[i]
			if x_mob_core.is_player_alive(p) then
				local p_pos = p:get_pos()
				if p_pos then
					local dx = pos.x - p_pos.x
					local dy = pos.y - p_pos.y
					local dz = pos.z - p_pos.z
					local d_sq = dx * dx + dy * dy + dz * dz
					local p_name = p:get_player_name()
					local is_enrolled = self.session_id and pale_watcher.ritual.is_player_enrolled(self.session_id, p_name)
					local max_sq = is_enrolled and (WATCHER_TETHER_MAX * WATCHER_TETHER_MAX) or (self.aggro_radius * self.aggro_radius)
					if d_sq <= max_sq and d_sq < min_d_sq then
						min_d_sq = d_sq
						closest = p
					end
				end
			end
		end
		self.target_player = closest
		x_mob_core.set_target(self, closest)
		current_target = closest
	end

	if not current_target or not x_mob_core.is_player_alive(current_target) then
		self.target_player = nil
		x_mob_core.set_target(self, nil)
		x_mob_core.halt_horizontal_velocity(self)
		x_mob_core.play_animation(self.object, "stand", {speed = 1.0, loop = true})
		return nil, nil, nil
	end

	local t_pos = current_target:get_pos()
	local dist = vector.distance(pos, t_pos)
	return current_target, t_pos, dist
end

---Tether Gauntlet Escapes and Intercept Ambush.
---When escaping the domain boundary, the Pale Watcher intercepts:
---he teleports directly ahead, charges the player, and retaliates with heavy damage and knockback.
---This intercept repeats on every escape attempt until the player breaks through or stuns the entity.
---@param self table
---@param pos Vector
---@param t_pos Vector
---@param dtime number
---@return boolean is_escaped_or_ambushing
local function step_tether_gauntlet(self, pos, t_pos, dtime)
	if not self.origin_pos and self.session_id then
		self.origin_pos = pale_watcher.ritual.get_session_center(self.session_id)
	end
	if not self.origin_pos then return false end
	local dist_from_origin = vector.distance(t_pos, self.origin_pos)

	-- Crossing the domain perimeter: Escaped the domain gauntlet!
	if dist_from_origin >= WATCHER_TETHER_MAX then
		local p_name = self.target_player and self.target_player:is_player() and self.target_player:get_player_name()
		local is_enrolled = p_name and self.session_id and pale_watcher.ritual.is_player_enrolled(self.session_id, p_name)

		if is_enrolled and p_name then
			core.sound_play("pale_watcher_drone", {pos = t_pos, max_hear_distance = 50})
			local escape_msg = S(
				"★ You have broken through the @1-node domain tether and escaped the nightmare!",
				math.floor(WATCHER_TETHER_MAX + 0.5)
			)
			core.chat_send_player(p_name, core.colorize(colors.victory, escape_msg))
		end

		local active_count = self.session_id and pale_watcher.ritual.get_active_player_count(self.session_id) or 0
		if active_count > 1 then
			self.target_player = nil
			x_mob_core.set_target(self, nil)
			self.ambush_charging = false
			return false
		end

		if self.session_id then
			pale_watcher.ritual.end_session(self.session_id, false)
			self.session_id = nil
		end
		self.object:remove()
		return true
	end

	-- Ambush cooldown progression
	if self.ambush_cooldown and self.ambush_cooldown > 0 then
		self.ambush_cooldown = math.max(0, self.ambush_cooldown - dtime)
	end

	-- When player falls back inside the domain, immediately re-prime ambush readiness
	if dist_from_origin < (WATCHER_AMBUSH_DIST - 3.0) then
		self.ambush_cooldown = 0
	end

	-- Intercept Ambush: Repeated on every attempt to cross the domain perimeter.
	-- The Pale Watcher intercepts directly in front of the escaping player,
	-- charging forward to deliver a vicious retaliatory strike and kinetic knockback.
	if dist_from_origin >= WATCHER_AMBUSH_DIST and
	   (self.ambush_cooldown or 0) <= 0 and
	   not self.ambush_charging then
		local ambush_pos = find_intercept_ambush_pos(self.target_player, 8.0)
		if not ambush_pos then
			ambush_pos = find_blind_spot_node(self.target_player, t_pos, 7, 11)
		end
		if ambush_pos then
			self.ambush_charging = true
			self.ambush_timer = 2.0
			self.ambush_cooldown = 5.0
			self.quantum_locked = false
			self.object:set_velocity({x = 0, y = 0, z = 0})
			self.object:set_acceleration({x = 0, y = -9.81, z = 0})
			self.object:set_pos(ambush_pos)
			local to_player = vector.direction(ambush_pos, t_pos)
			self.object:set_yaw(core.dir_to_yaw(to_player))
			x_mob_core.play_animation(self.object, "stalk_glide", {speed = 1.8, loop = true})
			pale_watcher.particles.teleport_rift(ambush_pos)
			core.sound_play("pale_watcher_scare", {pos = ambush_pos, max_hear_distance = 30}, true)
			return true
		end
	end

	-- Active Ambush Charge: surge forward and retaliate with attack animation, damage, and knockback
	if self.ambush_charging then
		self.ambush_timer = (self.ambush_timer or 2.0) - dtime
		local cur_dist = vector.distance(pos, t_pos)

		if cur_dist <= (self.attack_range or 2.8) then
			-- Connect with attack!
			self.ambush_charging = false
			self.ambush_cooldown = 2.5
			x_mob_core.halt_horizontal_velocity(self)
			local to_player = vector.direction(pos, t_pos)
			self.object:set_yaw(core.dir_to_yaw(to_player))

			local origin = self.origin_pos or (self.session_id and pale_watcher.ritual.get_session_center(self.session_id))
			local knockback_dir = origin and vector.direction(t_pos, origin) or vector.direction(pos, t_pos)
			knockback_dir.y = 0.45
			local kb_vel = vector.multiply(vector.normalize(knockback_dir), 24.0)

			execute_watcher_attack(self, self.target_player, pos, {
				multiplier = 2.0,
				anim_speed = 1.3,
				armor_div = 4,
				knockback_vel = kb_vel,
				flash = true,
				terror = true,
				scare_sound = true,
				particles = true,
			})
			return true
		elseif self.ambush_timer > 0 then
			-- Rapid charge towards escaping player
			local to_p = vector.direction(pos, t_pos)
			to_p.y = 0
			local charge_yaw = core.dir_to_yaw(to_p)
			self.object:set_yaw(charge_yaw)
			local charge_speed = math.max(6.5, (self.pursuit_speed or 4.2) * 1.6)
			x_mob_core.set_horizontal_velocity(self, charge_speed, charge_yaw)
			x_mob_core.play_animation(self.object, "stalk_glide", {speed = 1.8, loop = true})
			return true
		else
			-- Charge duration expired without contact (e.g. player successfully juked or bypassed)
			self.ambush_charging = false
			self.ambush_cooldown = 3.0
			x_mob_core.halt_horizontal_velocity(self)
		end
	end

	return false
end

---Light Source Extinguishing and Item Dropping.
---@param self table
---@param pos Vector
---@param t_pos Vector
---@param dist number
---@param dtime number
local function step_extinguish_lights(self, pos, t_pos, dist, dtime)
	self.light_check_timer = self.light_check_timer + dtime
	if self.light_check_timer < 1.5 then return end
	self.light_check_timer = 0

	local mob_eye = vector.add(pos, {x = 0, y = 2.6, z = 0})
	local mob_chest = vector.add(pos, {x = 0, y = 1.5, z = 0})
	local reach = 6.0
	local reach_sq = reach * reach

	-- Extinguish world light nodes strictly within reach and unobstructed line of sight (not through walls).
	scratch_light_minp.x, scratch_light_minp.y, scratch_light_minp.z = pos.x - reach, pos.y - 2, pos.z - reach
	scratch_light_maxp.x, scratch_light_maxp.y, scratch_light_maxp.z = pos.x + reach, pos.y + 4, pos.z + reach
	local light_nodes = core.find_nodes_in_area(scratch_light_minp, scratch_light_maxp, EXTINGUISH_LIGHT_NODES)
	for i = 1, #light_nodes do
		local lpos = light_nodes[i]
		local ldx = pos.x - lpos.x
		local ldz = pos.z - lpos.z
		local horiz_sq = ldx * ldx + ldz * ldz
		local dy = math.abs((pos.y + 1.5) - lpos.y)

		if horiz_sq <= reach_sq and dy <= 3.5 and not core.is_protected(lpos, "") then
			local lnode = core.get_node(lpos)
			local def = core.registered_nodes[lnode.name]

			if def and def.light_source and def.light_source > 0 then
				-- Only true sanctuary structures (e.g. burning ritual pyre, or nodes with group:sanctuary)
				-- or non-flame high-tier illumination structures (e.g. beacons, meselamps) are immune.
				-- Portable flame lights (torches, lanterns, candles) are extinguishable regardless of engine light value.
				local is_flame = is_extinguishable_light(lnode.name)
				local is_sanctuary = (core.get_item_group(lnode.name, "sanctuary") > 0)
					or (lnode.name == "pale_watcher:ritual_pyre_burning")
					or (lnode.name == "pale_watcher:ritual_pyre")
					or ((def.light_source >= 14) and not is_flame)

				if not is_sanctuary then
					local has_los = has_visual_los(mob_eye, lpos) or has_visual_los(mob_chest, lpos)
					if has_los then
						local drops = core.get_node_drops(lnode, "")
						if not drops or #drops == 0 then
							drops = (def.drop and type(def.drop) == "string") and {def.drop} or {lnode.name}
						end
						core.remove_node(lpos)
						for j = 1, #drops do
							local stack = ItemStack(drops[j])
							if not stack:is_empty() then
								x_mob_core.drop_item(lpos, stack, nil, {
									spread_min = 0.5,
									spread_max = 1.2,
									up_vel_min = 1.8,
									up_vel_max = 3.2,
									particles = true,
									trails = true,
								})
							end
						end
						pale_watcher.particles.void_mist(lpos, 0.8, 12)
						core.sound_play("pale_watcher_paper_burn", {pos = lpos, gain = 0.5, max_hear_distance = 18}, true)
						break -- 1 per pulse to create flickering dread
					end
				end
			end
		end
	end

	-- Frightened player drops wielded light source only within reach & line of sight (not through walls).
	if dist <= reach then
		local p_eye = vector.add(t_pos, {x = 0, y = 1.5, z = 0})
		local has_los = has_visual_los(mob_eye, p_eye) or has_visual_los(mob_chest, p_eye)
		if has_los then
			local wield = self.target_player:get_wielded_item()
			local wname = wield:get_name()
			local wdef = core.registered_items[wname]
			local is_flame_wield = is_extinguishable_light(wname)
				or string.find(wname, "torch")
				or string.find(wname, "lantern")
				or string.find(wname, "candle")
			local is_light_item = (wdef and wdef.light_source and wdef.light_source > 0)
				or is_flame_wield
				or string.find(wname, "lamp")
			local item_is_sanctuary = (core.get_item_group(wname, "sanctuary") > 0)
				or (wdef and wdef.light_source and wdef.light_source >= 14 and not is_flame_wield)

			if is_light_item and not item_is_sanctuary and not wield:is_empty() then
				x_mob_core.drop_item(t_pos, wield, nil, {
					spread_min = 0.5,
					spread_max = 1.2,
					up_vel_min = 1.8,
					up_vel_max = 3.0,
					particles = true,
					trails = true,
				})
				self.target_player:set_wielded_item(ItemStack(""))
				core.sound_play("pale_watcher_static", {to_player = self.target_player:get_player_name(), gain = 0.8}, true)
				core.chat_send_player(self.target_player:get_player_name(),
					core.colorize(colors.danger, S("Your trembling hands drop your light source into the darkness!")))
			end
		end
	end
end

---Anti-Bunker Curse (Prevents cramped underground or dirt hole exploits).
---Throttled to 1.0s interval to prevent multi-hit tick spam and instant player death.
---@param self table
---@param t_pos Vector
---@param dist number
---@param dtime number
---@return boolean is_choking_bunker
local function step_anti_bunker(self, t_pos, dist, dtime)
	if dist > 25.0 then return false end
	self.bunker_check_timer = (self.bunker_check_timer or 0) + dtime
	if self.bunker_check_timer < 1.0 then return false end
	self.bunker_check_timer = 0

	local air_around_player = count_surrounding_air(t_pos)
	if air_around_player <= 3 then
		-- Player has sealed themselves in a cramped bunker!
		local choke_pos = vector.add(t_pos, {x = 0.5, y = 0.05, z = 0.5})
		self.object:set_velocity({x = 0, y = 0, z = 0})
		self.object:set_pos(choke_pos)
		pale_watcher.particles.psychic_choke(t_pos)
		core.sound_play("pale_watcher_scare", {to_player = self.target_player:get_player_name()}, true)
		local punch_fleshy = calculate_armor_scaled_punch(self.target_player, 6, 0.33, 2)
		self.target_player:punch(self.object, 1.0, {
			full_punch_interval = 1.0,
			damage_groups = {fleshy = punch_fleshy}
		})
		core.chat_send_player(self.target_player:get_player_name(),
			core.colorize(colors.void, S("You cannot hide from the void...")))
		x_mob_core.emit("pale_watcher:bunker_choked", self, self.target_player, t_pos)
		return true
	end
	return false
end

---Sanctuary Check (Artificial light level >= 14).
---Checks artificial node light (timeofday = 0) so daylight does not block daytime stalking,
---while constructed sanctuaries (bonfires, beacons, burning pyres) continue to protect players.
---@param self table
---@param pos Vector
---@param t_pos Vector
---@param dist number
---@param dtime number
---@return boolean is_stopped_at_sanctuary
local function step_sanctuary(self, pos, t_pos, dist, dtime)
	local t_light = core.get_node_light(t_pos, 0)
	local in_sanctuary = t_light and t_light >= 14

	if in_sanctuary and dist <= 10.0 then
		-- Stopped at the border of sanctuary light
		x_mob_core.halt_horizontal_velocity(self)
		local to_t = vector.direction(pos, t_pos)
		self.object:set_yaw(core.dir_to_yaw(to_t))
		x_mob_core.play_animation(self.object, "stand", {speed = 1.0, loop = true})

		self.sanctuary_stare_timer = self.sanctuary_stare_timer + dtime
		if self.sanctuary_stare_timer >= 5.0 then
			self.sanctuary_stare_timer = 0
			-- Dissolves into mist after staring silently for 5 seconds and retreats into the tree line
			core.sound_play("pale_watcher_static", {pos = pos, max_hear_distance = 25}, true)
			pale_watcher.particles.sanctuary_dissolve(pos)
			core.chat_send_player(self.target_player:get_player_name(),
				core.colorize(colors.victory,
					S("The sanctuary light holds... The Pale Watcher dissolves into the dark tree line.")))

			local escape_pos = find_guaranteed_retreat_pos(self.target_player, pos)
			self.object:set_velocity({x = 0, y = 0, z = 0})
			self.object:set_acceleration({x = 0, y = -9.81, z = 0})
			self.object:set_pos(escape_pos)
			local to_player = vector.direction(escape_pos, t_pos)
			self.object:set_yaw(core.dir_to_yaw(to_player))
			pale_watcher.particles.void_mist(escape_pos, 2.5, 20)
			x_mob_core.emit("pale_watcher:sanctuary_retreat", self, pos, escape_pos)
			return true
		end
		return true
	else
		self.sanctuary_stare_timer = 0
		return false
	end
end

---Stalking, Quantum Locking, Glide Movement, and Melee Combat.
---@param self table
---@param pos Vector
---@param t_pos Vector
---@param dist number
---@param players ObjectRef[]
---@param dtime number
---@param tier integer
local function step_stalking_and_combat(self, pos, t_pos, dist, players, dtime, tier)
	local observed, observer = is_observed(pos, players)

	if observed then
		if not self.quantum_locked then
			self.quantum_locked = true
			self.object:set_velocity({x = 0, y = 0, z = 0})
			self.object:set_acceleration({x = 0, y = 0, z = 0})
		else
			self.object:set_velocity({x = 0, y = 0, z = 0})
		end
		-- Quantum Freeze: Motionless stare
		local to_obs = vector.direction(pos, observer:get_pos())
		self.object:set_yaw(core.dir_to_yaw(to_obs))
		x_mob_core.play_animation(self.object, "stand", {speed = 1.0, loop = true})

		-- Gaze dilemma: drain sanity, slow speed, narrow FOV
		if observer and x_mob_core.is_player_alive(observer) then
			local obs_dist = vector.distance(pos, observer:get_pos())
			pale_watcher.fx.update_player(observer, obs_dist, true, dtime, tier)

			-- Close-Range Retaliation: If player approaches in melee range (<= 2.6m),
			-- the Watcher does not flee; he delivers a vicious strike with heavy knockback!
			local o_pos = observer:get_pos()
			local o_light = core.get_node_light(o_pos, 0)
			local in_sanctuary = o_light and o_light >= 14
			if obs_dist <= (self.attack_range or 2.6) and not in_sanctuary then
				local attack_cd = (self.cooldowns and self.cooldowns.attack) or self.attack_cooldown or 0
				if attack_cd <= 0 then
					if self.cooldowns then
						self.cooldowns.attack = self.attack_interval or 1.0
					end
					self.attack_cooldown = self.attack_interval or 1.0
					local knockback_dir = vector.direction(pos, o_pos)
					knockback_dir.y = 0.45
					local kb_vel = vector.multiply(vector.normalize(knockback_dir), 24.0)

					execute_watcher_attack(self, observer, pos, {
						multiplier = 2.0,
						anim_speed = 1.2,
						armor_div = 4,
						knockback_vel = kb_vel,
						flash = true,
						scare_sound = true,
					})
				end
			end
		end
		return
	end

	if self.quantum_locked then
		self.quantum_locked = false
		self.object:set_acceleration({x = 0, y = -9.81, z = 0})
	end

	-- Unobserved: Blind-Spot Step Teleportation
	local teleport_cooldown = math.max(1.8, 9.0 - (tier * 1.6))
	self.stalk_timer = self.stalk_timer + dtime

	if self.stalk_timer >= teleport_cooldown and dist > self.attack_range then
		self.stalk_timer = 0
		local step_min = math.max(8.0, 14.0 - tier * 1.4)
		local step_max = math.max(14.0, 22.0 - tier * 1.8)
		local next_spot = find_blind_spot_node(self.target_player, pos, step_min, step_max)

		if next_spot then
			self.object:set_velocity({x = 0, y = 0, z = 0})
			self.object:set_acceleration({x = 0, y = -9.81, z = 0})
			self.object:set_pos(next_spot)
			local new_yaw = core.dir_to_yaw(vector.direction(next_spot, t_pos))
			self.object:set_yaw(new_yaw)
			core.sound_play("pale_watcher_static", {pos = next_spot, gain = 0.45, max_hear_distance = 25}, true)
			return
		end
	end

	-- Obstacle 1: Intercept Teleport on Sprinting Away
	local controls = self.target_player:get_player_control()
	if controls.up and controls.aux1 and dist > 10.0 then
		pale_watcher.physics.apply_terror(self.target_player)
		local p_look = self.target_player:get_look_dir()
		local to_watcher = vector.direction(t_pos, pos)

		-- Player's back is turned while sprinting
		if vector.dot(p_look, to_watcher) < -0.2 then
			local intercept_chance = 0.35 + (tier * 0.15)
			if math.random() < intercept_chance * dtime * 0.4 then
				local intercept_dist = math.random(13, 18)
				local ground_dest = find_intercept_ambush_pos(self.target_player, intercept_dist)
				if not ground_dest then
					ground_dest = find_blind_spot_node(self.target_player, pos, 12, 18)
				end
				if ground_dest then
					self.object:set_velocity({x = 0, y = 0, z = 0})
					self.object:set_acceleration({x = 0, y = -9.81, z = 0})
					self.object:set_pos(ground_dest)
					self.object:set_yaw(core.dir_to_yaw(vector.direction(ground_dest, t_pos)))
					core.sound_play("pale_watcher_scare", {pos = ground_dest, max_hear_distance = 25}, true)
					return
				end
			end
		end
	end

	-- Normal Stalk Glide Movement & Attack
	pale_watcher.fx.update_player(self.target_player, dist, false, dtime, tier)

	local hx = pos.x - t_pos.x
	local hz = pos.z - t_pos.z
	local horiz_dist_sq = hx * hx + hz * hz
	local vert_dist = math.abs(pos.y - t_pos.y)
	local in_attack_proximity = (dist <= self.attack_range) or (horiz_dist_sq <= 4.84 and vert_dist <= 2.5)

	local t_light = core.get_node_light(t_pos, 0)
	local in_sanctuary = t_light and t_light >= 14

	if in_attack_proximity and not in_sanctuary then
		x_mob_core.halt_horizontal_velocity(self)
		local to_t = vector.direction(pos, t_pos)
		self.object:set_yaw(core.dir_to_yaw(to_t))

		local attack_cd = (self.cooldowns and self.cooldowns.attack) or self.attack_cooldown or 0
		if attack_cd <= 0 then
			if self.cooldowns then
				self.cooldowns.attack = self.attack_interval or 1.0
			end
			self.attack_cooldown = self.attack_interval or 1.0
			execute_watcher_attack(self, self.target_player, pos, {
				multiplier = 1.0,
				anim_speed = 1.0,
				armor_div = 2,
			})
		else
			x_mob_core.play_animation(self.object, "stand", {speed = 1.0, loop = true})
		end
	else
		-- Stalk glide horizontally towards target
		local to_target = vector.direction(pos, t_pos)
		local yaw = core.dir_to_yaw(to_target)
		self.object:set_yaw(yaw)
		x_mob_core.set_horizontal_velocity(self, self.walk_speed, yaw)
		x_mob_core.play_animation(self.object, "stalk_glide", {speed = 1.0, loop = true})
	end
end

---Cinematic step routine for Cleansing Flame Pyre banishment.
---Locks the Pale Watcher in holy fire, facing the summoner, plays stagger into death_implode,
---levitates him upward into the vortex, detonates in a supernova burst, and awards rare dimensional loot.
---@param self table Entity table
---@param dtime number Delta time in seconds
local function step_pyre_banishment(self, dtime)
	self.banish_timer = (self.banish_timer or 0) + dtime
	local t = self.banish_timer
	local pyre_pos = self.banish_pyre_pos
	if not pyre_pos then return end

	local summoner = self.banish_summoner
	local cur_pos = self.object:get_pos() or pyre_pos

	-- Keep velocity and acceleration firmly locked at 0
	self.object:set_velocity({x = 0, y = 0, z = 0})
	self.object:set_acceleration({x = 0, y = 0, z = 0})

	-- Always keep mob facing summoner
	if summoner and summoner:is_valid() then
		local s_pos = summoner:get_pos()
		if s_pos then
			local dir = vector.direction(cur_pos, s_pos)
			dir.y = 0
			self.object:set_yaw(core.dir_to_yaw(dir))
		end
	end

	-- Periodic particle licking and sizzle
	self.banish_fx_timer = (self.banish_fx_timer or 0) + dtime
	if self.banish_fx_timer >= 0.25 then
		self.banish_fx_timer = 0
		pale_watcher.particles.void_mist(cur_pos, 1.5, 15)
	end

	-- Cleansing fire implosion transition
	if t >= 1.2 and not self._implode_started then
		self._implode_started = true
		x_mob_core.play_animation(self.object, "death_implode", {
			speed = 0.8,
			loop = false,
			force = true,
			priority = 35,
		})

		core.sound_play("pale_watcher_paper_burn", {pos = cur_pos, gain = 1.0, max_hear_distance = 50})
		core.sound_play("pale_watcher_death", {pos = cur_pos, gain = 1.0, max_hear_distance = 50})
		pale_watcher.particles.pyre_implosion(cur_pos, 2.4)
	end

	-- Levitation and cosmic convulsion
	if t >= 1.2 and t < 3.4 then
		local progress = (t - 1.2) / 2.2
		-- Slowly levitate upwards into the fire column
		local base_y = pyre_pos.y + 0.45 + (progress * 0.55)
		-- Cosmic jitter shake
		local jitter_x = (math.random() - 0.5) * (0.05 + 0.10 * progress)
		local jitter_z = (math.random() - 0.5) * (0.05 + 0.10 * progress)
		self.object:set_pos({x = pyre_pos.x + jitter_x, y = base_y, z = pyre_pos.z + jitter_z})
	end

	-- Supernova detonation shockwave and victory awards
	if t >= 3.4 then
		self.state = "dead"
		self.is_dead = true

		-- Supernova explosion particles
		pale_watcher.particles.pyre_supernova(cur_pos)
		core.sound_play("pale_watcher_bell", {pos = cur_pos, gain = 1.0, max_hear_distance = 50})
		core.sound_play("pale_watcher_death", {pos = cur_pos, gain = 1.0, max_hear_distance = 50})

		-- Screen flash on summoner and nearby players
		local players = core.get_connected_players()
		for _, p in ipairs(players) do
			local p_pos = p:get_pos()
			if p_pos and vector.distance(p_pos, cur_pos) <= 45 then
				pale_watcher.fx.trigger_flash(p, 0.9)
			end
		end

		-- Guaranteed rare dimensional drops launching in a radial holy fountain
		local drop_pos = {x = pyre_pos.x, y = pyre_pos.y + 0.8, z = pyre_pos.z}
		x_mob_core.drop_items(drop_pos, {
			{ name = "pale_watcher:dimensional_cloth", min = 3, max = 3, chance = 1.0 },
			{ name = "pale_watcher:static_core", min = 1, max = 1, chance = 1.0 },
		}, {
			particle_color = "ffaa33",
		})

		x_mob_core.emit("pale_watcher:pyre_banished", cur_pos, self.session_id, self.banish_summoner)

		-- End ritual session with victory
		if self.session_id then
			pale_watcher.ritual.end_session(self.session_id, true)
			self.session_id = nil
		end

		-- Cleanly remove mob
		self.object:remove()
	end
end

x_mob_core.register_mob("pale_watcher:pale_watcher", {
	mesh = "pale_watcher_mob.glb",
	textures = pale_watcher.get_textures(),
	hp_max = 500,
	glow = 3,
	collisionbox = {-0.4, 0.0, -0.4, 0.4, 3.2, 0.4},
	selectionbox = {-0.45, 0.0, -0.45, 0.45, 3.25, 0.45},
	visual = "mesh",
	visual_size = {x = 10, y = 10},
	makes_footstep_sound = false,
	backface_culling = false,
	use_texture_alpha = false,

	initial_properties = {
		hp_max = 500,
		mesh = "pale_watcher_mob.glb",
		visual = "mesh",
		visual_size = {x = 10, y = 10},
		collisionbox = {-0.4, 0.0, -0.4, 0.4, 3.2, 0.4},
		selectionbox = {-0.45, 0.0, -0.45, 0.45, 3.25, 0.45},
		makes_footstep_sound = false,
		backface_culling = false,
		use_texture_alpha = false,
		glow = 3,
	},

	mob_height = 3.2,
	eye_offset = 2.8,
	armor_groups = { fleshy = 100 },
	walk_speed = 2.5,
	pursuit_speed = 4.2,
	wander_speed = 1.0,
	aggro_radius = WATCHER_AMBUSH_DIST,
	attack_range = 2.6,
	damage = 8,
	attack_interval = 1.0,
	death_duration = 2.5,
	is_floating = false,
	can_swim = true,
	can_climb = false,
	can_open_doors = false,
	health_bar = false,
	melee = false,
	auto_scan = false,
	can_breathe_water = true,
	knockback_mult = 0.0,
	can_flinch = false,
	friendly_fire = false,
	immunities = {
		drown = true,
		suffocation = true,
	},
	factions = {
		void = true,
		eldritch = true,
	},

	cooldowns = {
		attack = 0.0,
	},

	damage_effect = {
		type = "spectral",
		colors = {"#4A148C", "#20162e", "#7B1FA2"},
		scale = 1.3,
	},

	drop_options = {
		particle_color = "ffaa33",
	},

	sounds = {
		distance = 40.0,
		gain = 1.0,
		pitch_jitter = 0.08,
		hurt = "pale_watcher_static",
		death = "pale_watcher_death",
		attack = "pale_watcher_scare",
		random = {
			name = "pale_watcher_drone",
			distance = 35.0,
			gain = 0.8,
			min_interval = 14.0,
			max_interval = 32.0,
		},
	},

	animations = {
		idle = {track = "idle", x = 1, y = 40, speed = 15, loop = true},
		stand = {track = "stand", x = 1, y = 40, speed = 15, loop = true},
		walk = {track = "walk", x = 1, y = 40, speed = 20, loop = true},
		stalk_glide = {track = "stalk_glide", x = 1, y = 40, speed = 20, loop = true},
		attack = {track = "attack", x = 1, y = 30, speed = 25, loop = false},
		punch = {track = "punch", x = 1, y = 30, speed = 25, loop = false},
		stun = {track = "stun", x = 1, y = 55, speed = 20, loop = false},
		stagger = {track = "stagger", x = 1, y = 55, speed = 20, loop = false},
		death = {track = "death", x = 1, y = 40, speed = 15, loop = false},
		death_implode = {track = "death_implode", x = 1, y = 40, speed = 15, loop = false},
	},

	drops = {
		{ name = "pale_watcher:dimensional_cloth", min = 2, max = 4, chance = 1.0 },
		{ name = "pale_watcher:static_core", min = 1, max = 1, chance = 1.0 },
	},

	on_activate = function(self, data_or_str, _dtime_s, raw_staticdata)
		self.stun_timer = 0
		self.attack_cooldown = 0

		local is_pyre = (type(data_or_str) == "table" and data_or_str.pyre_banish)
			or (raw_staticdata == "pyre_banish")
			or (data_or_str == "pyre_banish")
		if is_pyre then
			return
		end

		local data = {}
		if type(data_or_str) == "table" then
			data = data_or_str
		elseif type(data_or_str) == "string" and data_or_str ~= "" then
			data = core.deserialize(data_or_str) or {}
		end

		local saved_palette = data.palette_name or self.palette_name
		local textures, chosen_palette = pale_watcher.get_textures(nil, nil, saved_palette)
		self.palette_name = chosen_palette
		self.saved_data = self.saved_data or {}
		self.saved_data.palette_name = chosen_palette

		if self.object then
			self.object:set_properties({
				glow = 3,
				mesh = "pale_watcher_mob.glb",
				textures = textures,
			})
		end
		self.state = "stalking"
		self.quantum_locked = false
		self.target_player = nil
		self.stalk_timer = 0
		self.light_check_timer = 0
		self.ambush_cooldown = 0
		self.ambush_charging = false
		self.ambush_timer = 0
		self.sanctuary_stare_timer = 0
		self._hud_timer = 0.5
		self.aggro_radius = WATCHER_AMBUSH_DIST

		local pos = self.object and self.object:get_pos()
		if pos then
			local saved_sid = data.session_id or self.session_id
			if saved_sid and pale_watcher.ritual.is_session_active(saved_sid) then
				self.session_id = saved_sid
				self.origin_pos = pale_watcher.ritual.rebind_mob(saved_sid, self.object) or pos
			else
				local existing_session, existing_sid = pale_watcher.ritual.get_player_session(nil, pos)
				if existing_session and existing_sid then
					local cur_mob = existing_session.mob_ref
					if cur_mob and cur_mob:is_valid() and cur_mob ~= self.object then
						-- Redundant duplicate Pale Watcher entity in an already active encounter
						self.object:remove()
						return
					end
					self.session_id = existing_sid
					self.origin_pos = pale_watcher.ritual.rebind_mob(existing_sid, self.object) or pos
				else
					self.session_id = pale_watcher.ritual.start_session(self.object, pos)
					self.origin_pos = pos
					core.sound_play("pale_watcher_bell", {pos = pos, max_hear_distance = math.max(60, WATCHER_AMBUSH_DIST)}, true)
				end
			end
			self.saved_data.session_id = self.session_id
		end
	end,

	on_despawn = cleanup_entity_session,
	on_death = cleanup_entity_session,
	on_deactivate = cleanup_entity_session,

	on_step = function(self, dtime, _moveresult)
		if self.state == "banishing" then
			step_pyre_banishment(self, dtime)
			return
		end
		if self.is_dead or self.state == "dead" or self.state == "dying" then return end

		local pos = self.object:get_pos()
		if not pos then return end

		local players = core.get_connected_players()
		if #players == 0 then return end

		-- Stun Window: Flash Camera blinding stagger
		if step_stun_window(self, dtime, players, pos) then return end

		-- Synchronize ritual session HUD with nearby players
		step_sync_hud(self, pos, dtime)

		-- Target Acquisition
		local target, t_pos, dist = step_acquire_target(self, pos, players)
		if not target then return end

		-- Tether Gauntlet Checks and Intercept Ambush
		if step_tether_gauntlet(self, pos, t_pos, dtime) then return end

		-- Light Source Extinguishing and Item Dropping
		step_extinguish_lights(self, pos, t_pos, dist, dtime)

		-- Anti-Bunker Detection and Psychic Choke
		if step_anti_bunker(self, t_pos, dist, dtime) then return end

		-- Sanctuary Border Check
		if step_sanctuary(self, pos, t_pos, dist, dtime) then return end

		-- True Quantum Stalking, Glide Movement, and Melee Attack
		local tier = self.session_id and pale_watcher.ritual.get_stalker_tier(self.session_id) or 0
		step_stalking_and_combat(self, pos, t_pos, dist, players, dtime, tier)
	end,

	on_punch = function(self, puncher, _tflp, _tool_capabilities, _dir, _damage)
		if self.state == "banishing" or self.is_dead then
			return true
		end

		-- Combat Resilience: Immune to physical weapons
		-- Triggers immediate violent Psychic Backlash & dimensional slip retreat
		if puncher and puncher:is_player() then
			x_mob_core.indicate_damage(self.object)
			local cur_pos = self.object:get_pos()
			local p_pos = puncher:get_pos()
			local name = puncher:get_player_name()

			-- Scare sting
			core.sound_play("pale_watcher_scare", {pos = cur_pos, gain = 1.0, max_hear_distance = 40}, true)

			-- Kinetic Shockwave: Blast attacker violently backward away from the entity (doubled knockback)
			if p_pos then
				local blast_dir = vector.direction(cur_pos, p_pos)
				blast_dir.y = 0.45
				local blast_vel = vector.multiply(vector.normalize(blast_dir), 22.0)
				puncher:add_velocity(blast_vel)
			end

			-- Psychic Backlash Damage: Direct HP damage bypassing armor mitigation (doubled)
			local cur_hp = puncher:get_hp()
			local backlash_dmg = 8
			if cur_hp > backlash_dmg then
				puncher:set_hp(cur_hp - backlash_dmg, "pale_watcher:psychic_backlash")
			else
				puncher:set_hp(1, "pale_watcher:psychic_backlash")
			end

			-- Disorienting static shock on attacker's HUD
			pale_watcher.fx.trigger_flash(puncher)

			-- Chat warning explaining why physical combat failed
			core.chat_send_player(name, core.colorize(colors.void,
				S("★ An eldritch shockwave repels your strike! Physical weapons cannot harm the void!")))
		end
		return true -- Immune to standard weapon damage
	end,

	get_staticdata = function(self)
		self.saved_data = self.saved_data or {}
		self.saved_data.session_id = self.session_id
		self.saved_data.palette_name = self.palette_name
		return core.serialize(self.saved_data)
	end,

	---Called when hit by high-intensity Flash Camera.
	---@param user ObjectRef
	---@param duration number Stun duration in seconds (0.6s)
	on_stunned = function(self, user, duration)
		if self.state == "banishing" or self.is_dead then return end

		-- If already retreating from a flash, do not reset countdown
		if self.state == "stunned" and (self.stun_timer or 0) > 0 then
			return
		end

		self.state = "stunned"
		self.stun_timer = duration or 0.6
		self.ambush_charging = false
		self.ambush_cooldown = math.max(self.ambush_cooldown or 0, 5.0)
		x_mob_core.halt_horizontal_velocity(self)

		x_mob_core.emit("pale_watcher:stunned", self, user, self.stun_timer)

		-- Face the player while staggering back
		local to_user = vector.direction(self.object:get_pos(), user:get_pos())
		self.object:set_yaw(core.dir_to_yaw(to_user))

		x_mob_core.play_animation(self.object, "stun", {
			speed = 1.0,
			loop = false,
			force = true,
			priority = 10,
		})

		local pos = self.object:get_pos()
		core.sound_play("pale_watcher_stun", {pos = pos, max_hear_distance = 35}, true)

		-- Glitch/spark particles on Pale Watcher's face
		pale_watcher.particles.spawn({
			amount = 35,
			time = 0.6,
			pos = {
				min = vector.add(pos, {x = -0.3, y = 2.5, z = -0.3}),
				max = vector.add(pos, {x = 0.3, y = 3.2, z = 0.3}),
			},
			vel = {min = {x = -1, y = -0.5, z = -1}, max = {x = 1, y = 1.5, z = 1}},
			acc = {min = {x = 0, y = -1, z = 0}, max = {x = 0, y = 0, z = 0}},
			exptime = {min = 0.3, max = 0.8},
			size = {min = 1.0, max = 2.5},
			texpool = {
				{name = "pale_watcher_hud_flash.png", blend = "add"},
				{name = "pale_watcher_particles.png^[verticalframe:8:7", blend = "add"},
				{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
			},
			scale_tween = {start = 1.0, finish = 0.2},
			alpha_tween = {start = 1.0, finish = 0.0},
			glow = 12,
		})
	end,

	---Called when a player collects a Cursed Page.
	---Immediately prioritizes that player and snaps behind them.
	---@param collector ObjectRef
	on_page_collected = function(self, collector)
		if self.state == "banishing" or self.is_dead then return end
		if not collector or not collector:is_player() then return end
		self.target_player = collector
		x_mob_core.set_target(self, collector)

		local p_pos = collector:get_pos()
		if not p_pos then return end
		local p_look = collector:get_look_dir()
		-- Teleport behind the collector into a valid spot with 3 blocks of headroom
		local look_flat = vector.normalize({x = p_look.x, y = 0, z = p_look.z})
		local behind_pos = vector.add(p_pos, vector.multiply(look_flat, -14.0))
		local candidate = find_blind_spot_node(collector, p_pos, 11, 17)
		if candidate then
			behind_pos = candidate
		else
			local ground = pale_watcher.find_ground_node(behind_pos.x, p_pos.y, behind_pos.z, 4, 8, 3)
			if ground then
				behind_pos = {x = ground.x, y = ground.y + 0.50, z = ground.z}
			else
				behind_pos.y = p_pos.y
			end
		end

		self.object:set_velocity({x = 0, y = 0, z = 0})
		self.object:set_acceleration({x = 0, y = -9.81, z = 0})
		self.object:set_pos(behind_pos)
		self.object:set_yaw(core.dir_to_yaw(vector.direction(behind_pos, p_pos)))
		core.sound_play("pale_watcher_scare", {to_player = collector:get_player_name()}, true)
	end,

	---The Cleansing Flame Banishment Sequence.
	---The Pale Watcher is forcibly teleported into the pyre flames, paralyzed, implodes, and drops rare loot.
	---@param pyre_pos Vector
	---@param summoner? ObjectRef
	on_pyre_banished = function(self, pyre_pos, summoner)
		self.state = "banishing"
		self.is_dead = false
		self.banish_timer = 0.0
		self.banish_pyre_pos = vector.new(pyre_pos)
		self.banish_summoner = summoner
		self._implode_started = false

		local snap_pos = {x = pyre_pos.x, y = pyre_pos.y + 0.45, z = pyre_pos.z}

		-- Departure rift at entity's previous world location
		local old_pos = self.object:get_pos()
		if old_pos and vector.distance(old_pos, snap_pos) > 2.0 then
			pale_watcher.particles.teleport_rift(old_pos)
			core.sound_play("pale_watcher_scare", {pos = old_pos, gain = 1.0, max_hear_distance = 40})
		end

		-- Snap directly into the pyre flames and lock physics
		self.object:set_pos(snap_pos)
		self.object:set_velocity({x = 0, y = 0, z = 0})
		self.object:set_acceleration({x = 0, y = 0, z = 0})
		self.object:set_properties({
			physical = false,
			collide_with_objects = false,
			pointable = false,
			glow = 14,
		})

		-- Face the summoner
		if summoner and summoner:is_valid() then
			local s_pos = summoner:get_pos()
			if s_pos then
				local dir = vector.direction(snap_pos, s_pos)
				dir.y = 0
				self.object:set_yaw(core.dir_to_yaw(dir))
			end
		end

		-- Stagger in sacred fire
		x_mob_core.play_animation(self.object, "stagger", {
			speed = 1.0,
			loop = true,
			force = true,
			priority = 30,
		})

		-- Arrival dimensional burst & sound
		pale_watcher.particles.teleport_rift(snap_pos)
		pale_watcher.particles.pyre_roaring_flames(pyre_pos)
		core.sound_play("pale_watcher_bell", {pos = snap_pos, gain = 1.0, max_hear_distance = 50})
		core.sound_play("pale_watcher_scare", {pos = snap_pos, gain = 1.0, max_hear_distance = 50})

		-- Screen static flash on summoner
		if summoner and summoner:is_valid() then
			pale_watcher.fx.trigger_flash(summoner)
		end
	end,
})

-- Natural Spawning: Spawns rarely in deep dark forests or beneath thick canopies
x_mob_core.register_spawn("pale_watcher:pale_watcher", {
	nodes = {
		-- Default / Luanti Game
		"group:soil",
		"default:dirt_with_grass",
		"default:dirt_with_coniferous_litter",
		"default:dirt_with_rainforest_litter",
		"default:dirt",
		"default:dry_dirt_with_dry_grass",
		"default:dirt_with_snow",
		"default:permafrost_with_moss",

		-- Mineclonia / Voxelibre
		"group:dirt",
		"group:grass_block",
		"group:grass_block_snow",
		"mcl_core:dirt_with_grass",
		"mcl_core:dirt_with_grass_snow",
		"mcl_core:dirt",
		"mcl_core:coarse_dirt",
		"mcl_core:podzol",
		"mcl_core:podzol_snow",
		"mcl_core:mycelium",
		"mcl_mud:mud",

		-- Everness
		"everness:dirt_with_cursed_grass",
		"everness:cursed_dirt",
		"everness:dirt_with_coral_grass",
		"everness:dirt_with_crystal_grass",
		"everness:forsaken_tundra_dirt_with_grass",
		"everness:dirt_with_grass_1",
		"everness:crystal_cave_dirt_with_moss",
		"everness:dry_dirt_with_dry_grass",

		-- Ethereal
		"ethereal:green_dirt",
		"ethereal:grove_dirt",
		"ethereal:bamboo_dirt",
		"ethereal:jungle_dirt",
		"ethereal:prairie_dirt",
		"ethereal:cold_dirt",
		"ethereal:crystal_dirt",
		"ethereal:mushroom_dirt",
		"ethereal:gray_dirt",
		"ethereal:dry_dirt",
	},
	chance = 15000,
	min_light = 0,
	max_light = 15,
	min_elevation = -31000,
	max_elevation = 31000,
	active_object_count = 1,
})

return true
