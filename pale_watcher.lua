--[[
	pale_watcher - The Pale Watcher Horror Mob Entity Definition
	Quantum Stalking, Blind-Spot Step Teleportation, Trajectory Intercepts,
	Anti-Bunker Curse, Light Extinguishing, Combat Dimensional Slip,
	Flash Stun Window, Sunlight Banishment, and Cleansing Flame Implosion.
]]

local colors = pale_watcher.colors

local WATCHER_FOV_DOT = 0.55
local WATCHER_TETHER_MAX = tonumber(core.settings:get("pale_watcher_tether_radius")) or 100.0
local WATCHER_AMBUSH_DIST = math.max(20.0, WATCHER_TETHER_MAX - 15.0)
local MAX_OBSERVE_DIST_SQ = (WATCHER_TETHER_MAX + 15.0) * (WATCHER_TETHER_MAX + 15.0)

local OBSERVATION_POINTS = {
	{x = 0, y = 2.6, z = 0}, -- Head / Eyes
	{x = 0, y = 1.6, z = 0}, -- Chest / Center of mass (aligns with player eye level ~1.625)
	{x = 0, y = 0.8, z = 0}, -- Torso / Waist
}

---Checks whether a target point is visually unobstructed by opaque solid terrain.
---Foliage (leaves, flora) and transparent blocks (glass) do not block line of sight for horror mob detection.
local has_visual_los = pale_watcher.has_visual_los

---Determines whether any connected living player is observing the mob within line of sight.
---Tests multiple points across the 3.2m tall entity (head, chest, torso) to ensure reliable
---quantum locking even in dense foliage, behind low obstacles, or at close proximity.
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
				if (dx * dx + dy * dy + dz * dz) <= MAX_OBSERVE_DIST_SQ then
					local p_eye = vector.add(p_pos, {x = 0, y = 1.625, z = 0})
					local look_dir = player:get_look_dir()

					for pt_idx = 1, #OBSERVATION_POINTS do
						local sample_pt = vector.add(pos, OBSERVATION_POINTS[pt_idx])
						local to_pt = vector.direction(p_eye, sample_pt)
						local dot = vector.dot(look_dir, to_pt)

						if dot >= WATCHER_FOV_DOT then
							if has_visual_los(p_eye, sample_pt) then
								return true, player
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
		p_yaw + math.pi * 0.85,         -- Deep rear left
		p_yaw - math.pi * 0.85,         -- Deep rear right
		p_yaw + math.pi * 0.70,         -- Rear left
		p_yaw - math.pi * 0.70,         -- Rear right
		p_yaw + math.pi * 0.50,         -- Flank left
		p_yaw - math.pi * 0.50,         -- Flank right
		p_yaw + math.random() * math.pi -- Random variation
	}

	for i = 1, #test_angles do
		local angle = test_angles[i]
		local dist = math.random(step_min_dist, step_max_dist)
		local cand_x = p_pos.x - math.sin(angle) * dist
		local cand_z = p_pos.z + math.cos(angle) * dist

		-- Generous 8 up / 12 down scan to find ground across uneven hills and forested terrain
		local ground = pale_watcher.find_ground_node(cand_x, p_pos.y, cand_z, 8, 12, 3)
		if ground then
			local dest = {x = ground.x, y = ground.y + 1, z = ground.z}
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
	local dists = {preferred_dist or 10.0, 8.0, 12.0, 6.0, 14.0}

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

			local ground = pale_watcher.find_ground_node(cand_x, p_pos.y, cand_z, 5, 7, 4)
			if ground then
				return {x = ground.x, y = ground.y + 0.55, z = ground.z}
			end
		end
	end

	return nil
end

---Counts nearby air blocks around a player to detect underground bunker exploits.
---@param player_pos Vector
---@return integer air_count
local function count_surrounding_air(player_pos)
	local p_round = vector.round(player_pos)
	local air_count = 0
	for x = -1, 1 do
		for y = 0, 2 do
			for z = -1, 1 do
				local n = core.get_node({x = p_round.x + x, y = p_round.y + y, z = p_round.z + z}).name
				if n == "air" then
					air_count = air_count + 1
				end
			end
		end
	end
	return air_count
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

---Centralized session cleanup for mob removal, death, or deactivation.
---@param self table Entity table
local function cleanup_entity_session(self)
	if self.session_id then
		pale_watcher.ritual.end_session(self.session_id, false)
		self.session_id = nil
	end
	pale_watcher.fx.clear_all()
end

---Step 1: Stun Window (Flash Camera blinding stagger).
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
	self.object:set_velocity({x = 0, y = 0, z = 0})

	if self.stun_timer <= 0 then
		-- Stun expired: Immediate evasive phase retreat into distance
		local target = self.target_player or players[1]
		local escape_pos = target and find_blind_spot_node(target, pos, 28, 42)
		if not escape_pos and target then
			escape_pos = find_blind_spot_node(target, pos, 16, 26)
		end
		if not escape_pos and target then
			-- Guaranteed fallback: safe ground behind player
			local p_pos = target:get_pos()
			if p_pos then
				local p_yaw = core.dir_to_yaw(target:get_look_dir())
				local rear_x = p_pos.x + math.sin(p_yaw) * 25
				local rear_z = p_pos.z - math.cos(p_yaw) * 25
				local ground = pale_watcher.find_ground_node(rear_x, p_pos.y, rear_z, 10, 15, 3)
				if ground then
					escape_pos = {x = ground.x, y = ground.y + 1, z = ground.z}
				end
			end
		end

		-- Dramatic departure visual & audio at current position BEFORE teleporting
		pale_watcher.particles.teleport_rift(pos)
		core.sound_play("pale_watcher_scare", {pos = pos, gain = 0.8, max_hear_distance = 35}, true)

		if escape_pos then
			self.object:set_pos(escape_pos)
			-- Arrival puff & distant audio
			pale_watcher.particles.void_mist(escape_pos, 2.5, 25)
			core.sound_play("pale_watcher_static", {pos = escape_pos, gain = 0.6, max_hear_distance = 25}, true)
		end
		self.state = "stalking"
	end

	return true
end

---Step 2: Sunlight / Dawn Banishment.
---@param self table
---@param pos Vector
---@return boolean is_banished
local function step_dawn_banishment(self, pos)
	local tod = core.get_timeofday()
	if tod >= 0.23 and tod <= 0.75 then -- Sunrise through daytime
		local nat_light = core.get_natural_light(pos)
		if nat_light and nat_light >= 14 then
			-- Catches fire and dissolves into static ash
			self.is_dead = true
			self.state = "dead"
			core.sound_play("pale_watcher_death", {pos = pos, max_hear_distance = 45})
			pale_watcher.particles.dawn_banish_burn(pos)

			core.chat_send_all(core.colorize(colors.victory,
				"★ The morning dawn breaks the nightmare... The Pale Watcher dissolves into static ash."))
			if self.session_id then
				pale_watcher.ritual.end_session(self.session_id, true)
				self.session_id = nil
			end
			self.object:remove()
			return true
		end
	end
	return false
end

---Step 3: Synchronize ritual session HUD with nearby players.
---@param self table
---@param pos Vector
---@param dtime number
local function step_sync_hud(self, pos, dtime)
	self._hud_timer = (self._hud_timer or 0) + dtime
	if self._hud_timer >= 0.5 then
		self._hud_timer = 0
		if self.session_id then
			pale_watcher.ritual.update_session_players(self.session_id, pos)
		end
	end
end

---Step 4: Target Acquisition using pre-filtered distance squared.
---@param self table
---@param pos Vector
---@param players ObjectRef[]
---@return ObjectRef|nil target
---@return Vector|nil target_pos
---@return number|nil distance
local function step_acquire_target(self, pos, players)
	if not self.target_player or not x_mob_core.is_player_alive(self.target_player) then
		local closest = nil
		local min_d_sq = self.aggro_radius * self.aggro_radius
		for i = 1, #players do
			local p = players[i]
			if x_mob_core.is_player_alive(p) then
				local p_pos = p:get_pos()
				if p_pos then
					local dx = pos.x - p_pos.x
					local dy = pos.y - p_pos.y
					local dz = pos.z - p_pos.z
					local d_sq = dx * dx + dy * dy + dz * dz
					if d_sq < min_d_sq then
						min_d_sq = d_sq
						closest = p
					end
				end
			end
		end
		self.target_player = closest
		if closest then
			x_mob_core.set_target(self, closest)
		end
	end

	if not self.target_player or not x_mob_core.is_player_alive(self.target_player) then
		self.object:set_velocity({x = 0, y = 0, z = 0})
		x_mob_core.play_animation(self.object, "stand", {speed = 1.0, loop = true})
		return nil, nil, nil
	end

	local t_pos = self.target_player:get_pos()
	local dist = vector.distance(pos, t_pos)
	return self.target_player, t_pos, dist
end

---Step 5: Tether Gauntlet Escapes & Intercept Ambush.
---@param self table
---@param t_pos Vector
---@return boolean is_escaped_or_ambushing
local function step_tether_gauntlet(self, t_pos)
	if not self.origin_pos then return false end
	local dist_from_origin = vector.distance(t_pos, self.origin_pos)

	-- Ambush: One final desperate intercept teleport in front of the escaping player
	if dist_from_origin >= WATCHER_AMBUSH_DIST and
	   dist_from_origin < WATCHER_TETHER_MAX and
	   not self.ambush_triggered then
		local ambush_pos = find_intercept_ambush_pos(self.target_player, 10.0)
		if not ambush_pos then
			ambush_pos = find_blind_spot_node(self.target_player, t_pos, 8, 12)
		end
		if ambush_pos then
			self.ambush_triggered = true
			self.object:set_pos(ambush_pos)
			local to_player = vector.direction(ambush_pos, t_pos)
			self.object:set_yaw(core.dir_to_yaw(to_player))
			self.object:set_velocity({x = 0, y = 0, z = 0})
			x_mob_core.play_animation(self.object, "stand", {speed = 1.0, loop = true})
			core.sound_play("pale_watcher_scare", {pos = ambush_pos, max_hear_distance = 30}, true)
			return true
		end
	end

	-- Crossing the domain perimeter: Escaped the domain gauntlet!
	if dist_from_origin >= WATCHER_TETHER_MAX then
		core.sound_play("pale_watcher_drone", {pos = t_pos, max_hear_distance = 50})
		local escape_msg = string.format(
			"★ You have broken through the %d-node domain tether and escaped into the night!",
			math.floor(WATCHER_TETHER_MAX + 0.5)
		)
		core.chat_send_player(self.target_player:get_player_name(), core.colorize(colors.victory, escape_msg))
		if self.session_id then
			pale_watcher.ritual.end_session(self.session_id, false)
			self.session_id = nil
		end
		self.object:remove()
		return true
	end

	return false
end

---Step 6: Light Source Extinguishing & Item Dropping.
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
	local light_nodes = core.find_nodes_in_area(
		vector.subtract(pos, {x = reach, y = 2, z = reach}),
		vector.add(pos, {x = reach, y = 4, z = reach}),
		{
			"group:torch",
			"group:candle",
			"group:lantern",
			"default:torch",
			"default:torch_wall",
			"default:torch_ceiling",
			"default:meselamp",
		}
	)
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
				-- Only true sanctuary structures (e.g. burning ritual pyre, or nodes with light_source >= 14) are immune
				local is_sanctuary = (core.get_item_group(lnode.name, "sanctuary") > 0) or
					(lnode.name == "pale_watcher:ritual_pyre_burning") or
					(lnode.name == "pale_watcher:ritual_pyre") or
					(def.light_source >= 14)

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
								core.item_drop(stack, nil, lpos)
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
			local is_light_item = (wdef and wdef.light_source and wdef.light_source > 0) or
				string.find(wname, "torch") or string.find(wname, "lantern") or
				string.find(wname, "lamp") or string.find(wname, "candle")
			local item_is_sanctuary = wdef and wdef.light_source and wdef.light_source >= 14

			if is_light_item and not item_is_sanctuary and not wield:is_empty() then
				core.item_drop(wield, self.target_player, t_pos)
				self.target_player:set_wielded_item(ItemStack(""))
				core.sound_play("pale_watcher_static", {to_player = self.target_player:get_player_name(), gain = 0.8}, true)
				core.chat_send_player(self.target_player:get_player_name(),
					core.colorize(colors.danger, "Your trembling hands drop your light source into the darkness!"))
			end
		end
	end
end

---Step 7: Anti-Bunker Curse (Prevent 3-block dirt hole cheese).
---@param self table
---@param t_pos Vector
---@param dist number
---@return boolean is_choking_bunker
local function step_anti_bunker(self, t_pos, dist)
	if dist > 25.0 then return false end
	local air_around_player = count_surrounding_air(t_pos)
	if air_around_player <= 3 then
		-- Player has sealed themselves in a cramped bunker!
		local choke_pos = vector.add(t_pos, {x = 0.5, y = 0, z = 0.5})
		self.object:set_pos(choke_pos)
		pale_watcher.particles.psychic_choke(t_pos)
		core.sound_play("pale_watcher_scare", {to_player = self.target_player:get_player_name()}, true)
		local punch_fleshy = calculate_armor_scaled_punch(self.target_player, 6, 0.33, 2)
		self.target_player:punch(self.object, 1.0, {
			full_punch_interval = 1.0,
			damage_groups = {fleshy = punch_fleshy}
		})
		core.chat_send_player(self.target_player:get_player_name(),
			core.colorize(colors.void, "You cannot hide from the void..."))
		return true
	end
	return false
end

---Step 8: Sanctuary Check (Light level >= 14).
---@param self table
---@param pos Vector
---@param t_pos Vector
---@param dist number
---@param dtime number
---@return boolean is_stopped_at_sanctuary
local function step_sanctuary(self, pos, t_pos, dist, dtime)
	local t_light = core.get_node_light(t_pos)
	local in_sanctuary = t_light and t_light >= 14

	if in_sanctuary and dist <= 10.0 then
		-- Stopped at the border of sanctuary light
		self.object:set_velocity({x = 0, y = 0, z = 0})
		local to_t = vector.direction(pos, t_pos)
		self.object:set_yaw(core.dir_to_yaw(to_t))
		x_mob_core.play_animation(self.object, "stand", {speed = 1.0, loop = true})

		self.sanctuary_stare_timer = self.sanctuary_stare_timer + dtime
		if self.sanctuary_stare_timer >= 5.0 then
			-- Dissolves into mist after staring silently for 5 seconds
			core.sound_play("pale_watcher_static", {pos = pos, max_hear_distance = 25})
			pale_watcher.particles.sanctuary_dissolve(pos)
			core.chat_send_player(self.target_player:get_player_name(),
				core.colorize(colors.victory, "The sanctuary light holds... The Pale Watcher dissolves into the dark tree line."))
			if self.session_id then
				pale_watcher.ritual.end_session(self.session_id, false)
				self.session_id = nil
			end
			self.object:remove()
			return true
		end
		return true
	else
		self.sanctuary_stare_timer = 0
		return false
	end
end

---Step 9: Stalking, Quantum Locking, Glide Movement & Melee Combat.
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
		self.quantum_locked = true
		-- Quantum Freeze: Motionless stare
		self.object:set_velocity({x = 0, y = 0, z = 0})
		local to_obs = vector.direction(pos, observer:get_pos())
		self.object:set_yaw(core.dir_to_yaw(to_obs))
		x_mob_core.play_animation(self.object, "stand", {speed = 1.0, loop = true})

		-- Gaze dilemma: drain sanity, slow speed, narrow FOV
		if observer and x_mob_core.is_player_alive(observer) then
			local obs_dist = vector.distance(pos, observer:get_pos())
			pale_watcher.fx.update_player(observer, obs_dist, true, dtime, tier)

			-- Proximity Slip: If player approaches within <= 3.5m while staring,
			-- the Watcher refuses to be an easy melee target and slips into the void!
			if obs_dist <= 3.5 then
				pale_watcher.particles.teleport_rift(pos)
				core.sound_play("pale_watcher_scare", {pos = pos, gain = 0.8, max_hear_distance = 35}, true)
				local slip_pos = find_blind_spot_node(observer, pos, 18, 28)
				if not slip_pos then
					slip_pos = find_blind_spot_node(observer, pos, 10, 18)
				end
				if slip_pos then
					self.object:set_pos(slip_pos)
					pale_watcher.particles.void_mist(slip_pos, 2.5, 20)
					core.sound_play("pale_watcher_static", {pos = slip_pos, gain = 0.6, max_hear_distance = 25}, true)
				end
				return
			end
		end
		return
	end

	self.quantum_locked = false

	-- Unobserved: Blind-Spot Step Teleportation
	local teleport_cooldown = math.max(1.8, 9.0 - (tier * 1.6))
	self.stalk_timer = self.stalk_timer + dtime

	if self.stalk_timer >= teleport_cooldown and dist > self.attack_range then
		self.stalk_timer = 0
		local step_min = math.max(4, 12 - tier * 2)
		local step_max = math.max(8, 22 - tier * 2)
		local next_spot = find_blind_spot_node(self.target_player, pos, step_min, step_max)

		if next_spot then
			self.object:set_pos(next_spot)
			local new_yaw = core.dir_to_yaw(vector.direction(next_spot, t_pos))
			self.object:set_yaw(new_yaw)
			core.sound_play("pale_watcher_static", {pos = next_spot, gain = 0.35, max_hear_distance = 15}, true)
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
				local intercept_dist = math.random(14, 18)
				local forward_target = vector.add(t_pos, vector.multiply(p_look, intercept_dist))
				local ground_dest = find_blind_spot_node(self.target_player, forward_target, 12, 18)
				if ground_dest then
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

	local t_light = core.get_node_light(t_pos)
	local in_sanctuary = t_light and t_light >= 14

	if in_attack_proximity and not in_sanctuary then
		self.object:set_velocity({x = 0, y = 0, z = 0})
		local to_t = vector.direction(pos, t_pos)
		self.object:set_yaw(core.dir_to_yaw(to_t))

		self.attack_cooldown = (self.attack_cooldown or 0) + dtime
		if self.attack_cooldown >= self.attack_interval then
			self.attack_cooldown = 0
			x_mob_core.play_animation(self.object, "attack", {speed = 1.0, loop = false, force = true})
			local punch_fleshy = calculate_armor_scaled_punch(self.target_player, self.damage, 0.25, 2)
			self.target_player:punch(self.object, 1.0, {
				full_punch_interval = 1.0,
				damage_groups = {fleshy = punch_fleshy}
			})
			core.sound_play("pale_watcher_scare", {to_player = self.target_player:get_player_name()}, true)
		else
			x_mob_core.play_animation(self.object, "stand", {speed = 1.0, loop = true})
		end
	else
		-- Stalk glide towards target
		local to_target = vector.direction(pos, t_pos)
		local yaw = core.dir_to_yaw(to_target)
		self.object:set_yaw(yaw)
		self.object:set_velocity(vector.multiply(to_target, self.walk_speed))
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
		self.object:set_animation({x = 1, y = 40}, 16, 0.1, false)

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

		-- Guaranteed rare dimensional drops right into the pyre
		local drop_pos = {x = pyre_pos.x, y = pyre_pos.y + 0.8, z = pyre_pos.z}
		core.item_drop(ItemStack("pale_watcher:dimensional_cloth 3"), nil, drop_pos)
		core.item_drop(ItemStack("pale_watcher:static_core 1"), nil, drop_pos)

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
	initial_properties = {
		hp_max = 500,
		mesh = "pale_watcher_mob.glb",
		textures = pale_watcher.get_textures(),
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
	aggro_radius = math.max(100.0, WATCHER_TETHER_MAX),
	attack_range = 2.6,
	damage = 8,
	attack_interval = 1.0,
	death_duration = 2.5,
	is_floating = false,
	can_swim = true,
	can_climb = false,
	can_open_doors = false,

	sounds = {
		hurt = "pale_watcher_static",
		death = "pale_watcher_death",
		attack = "pale_watcher_scare",
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

	on_activate = function(self, staticdata, _dtime_s)
		if self.object then
			self.object:set_properties({
				glow = 3,
				mesh = "pale_watcher_mob.glb",
				textures = pale_watcher.get_textures(),
			})
		end
		self.state = "stalking"
		self.quantum_locked = false
		self.target_player = nil
		self.stalk_timer = 0
		self.light_check_timer = 0
		self.ambush_triggered = false
		self.sanctuary_stare_timer = 0
		self.stun_timer = 0
		self.attack_cooldown = 0

		if staticdata == "pyre_banish" then
			return
		end

		local pos = self.object and self.object:get_pos()
		if pos then
			self.session_id = pale_watcher.ritual.start_session(self.object, pos)
			self.origin_pos = pos
			core.sound_play("pale_watcher_bell", {pos = pos, max_hear_distance = 45}, true)
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

		-- 1. Stun Window: Flash Camera blinding stagger
		if step_stun_window(self, dtime, players, pos) then return end

		-- 2. Sunlight / Dawn Banishment Check
		if step_dawn_banishment(self, pos) then return end

		-- 3. Synchronize ritual session HUD with nearby players
		step_sync_hud(self, pos, dtime)

		-- 4. Target Acquisition
		local target, t_pos, dist = step_acquire_target(self, pos, players)
		if not target then return end

		-- 5. Tether Gauntlet Checks & Intercept Ambush
		if step_tether_gauntlet(self, t_pos) then return end

		-- 6. Light Source Extinguishing & Item Dropping
		step_extinguish_lights(self, pos, t_pos, dist, dtime)

		-- 7. Anti-Bunker Detection & Psychic Choke
		if step_anti_bunker(self, t_pos, dist) then return end

		-- 8. Sanctuary Border Check
		if step_sanctuary(self, pos, t_pos, dist, dtime) then return end

		-- 9. True Quantum Stalking, Glide Movement & Melee Attack
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

			-- 1. Departure dimensional rift particles & scare sting
			pale_watcher.particles.teleport_rift(cur_pos)
			core.sound_play("pale_watcher_scare", {pos = cur_pos, gain = 1.0, max_hear_distance = 40}, true)

			-- 2. Kinetic Shockwave: Blast attacker violently backward away from the entity
			if p_pos then
				local blast_dir = vector.direction(cur_pos, p_pos)
				blast_dir.y = 0.35
				local blast_vel = vector.multiply(vector.normalize(blast_dir), 11.0)
				puncher:add_velocity(blast_vel)
			end

			-- 3. Psychic Backlash Damage: Deals 4 direct HP damage (bypassing armor mitigation)
			local cur_hp = puncher:get_hp()
			local backlash_dmg = 4
			if cur_hp > backlash_dmg then
				puncher:set_hp(cur_hp - backlash_dmg, "pale_watcher:psychic_backlash")
			else
				puncher:set_hp(1, "pale_watcher:psychic_backlash")
			end

			-- 4. Disorienting static shock on attacker's HUD
			pale_watcher.fx.trigger_flash(puncher)

			-- 5. Chat warning explaining why physical combat failed
			core.chat_send_player(name, core.colorize(colors.void,
				"★ An eldritch shockwave repels your strike! Physical weapons cannot harm the void!"))

			-- 6. Dimensional phase retreat into distant tree cover
			local escape_pos = find_blind_spot_node(puncher, cur_pos, 22, 34)
			if not escape_pos then
				escape_pos = find_blind_spot_node(puncher, cur_pos, 12, 20)
			end
			if escape_pos then
				self.object:set_pos(escape_pos)
				pale_watcher.particles.void_mist(escape_pos, 2.5, 20)
				core.sound_play("pale_watcher_static", {pos = escape_pos, gain = 0.6, max_hear_distance = 25}, true)
			end
		end
		return true -- Immune to standard weapon damage
	end,

	---Called when hit by high-intensity Flash Camera.
	---@param user ObjectRef
	---@param duration number Stun duration in seconds (3-5s)
	on_stunned = function(self, user, duration)
		self.state = "stunned"
		self.stun_timer = duration or 3.8
		self.object:set_velocity({x = 0, y = 0, z = 0})

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
		local behind_pos = vector.add(p_pos, vector.multiply(p_look, -6.0))
		local candidate = find_blind_spot_node(collector, p_pos, 5, 8)
		if candidate then
			behind_pos = candidate
		else
			local ground = pale_watcher.find_ground_node(behind_pos.x, behind_pos.y, behind_pos.z, 2, 3, 3)
			if ground then
				behind_pos = {x = ground.x, y = ground.y + 1, z = ground.z}
			end
		end

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
		self.object:set_animation({x = 1, y = 55}, 20, 0.1, true)

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

-- Natural Spawning: Spawns rarely in deep dark forests at night
x_mob_core.register_spawn("pale_watcher:pale_watcher", {
	nodes = {
		"group:soil",
		"group:tree",
		"group:leaves",
		"default:dirt_with_grass",
		"default:dirt_with_coniferous_litter",
	},
	chance = 15000,
	min_light = 0,
	max_light = 6,
	min_elevation = -100,
	max_elevation = 200,
	active_object_count = 1,
})

return true
