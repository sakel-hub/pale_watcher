--[[
	pale_watcher - The Pale Watcher Horror Mob Entity Definition
	Quantum Stalking, Blind-Spot Step Teleportation, Trajectory Intercepts,
	Anti-Bunker Curse, Light Extinguishing, Combat Dimensional Slip,
	Flash Stun Window, Sunlight Banishment, and Cleansing Flame Implosion.
]]

local WATCHER_FOV_DOT = 0.55
local WATCHER_TETHER_MAX = 70.0
local WATCHER_AMBUSH_DIST = 60.0

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
	for _, player in ipairs(players) do
		if x_mob_core.is_player_alive(player) then
			local p_pos = player:get_pos()
			if p_pos then
				local p_eye = vector.add(p_pos, {x = 0, y = 1.625, z = 0})
				local look_dir = player:get_look_dir()

				for _, offset in ipairs(OBSERVATION_POINTS) do
					local target_pt = vector.add(pos, offset)
					local to_pt = vector.direction(p_eye, target_pt)

					if vector.dot(look_dir, to_pt) >= WATCHER_FOV_DOT then
						if has_visual_los(p_eye, target_pt) then
							return true, player
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
		p_yaw + math.pi * 0.75,         -- Rear left
		p_yaw - math.pi * 0.75,         -- Rear right
		p_yaw + math.pi * 0.5,          -- Flank left
		p_yaw - math.pi * 0.5,          -- Flank right
		p_yaw + math.random() * math.pi -- Random variation
	}

	for _, angle in ipairs(test_angles) do
		local dist = math.random(step_min_dist, step_max_dist)
		local offset = {
			x = -math.sin(angle) * dist,
			y = 0,
			z = math.cos(angle) * dist,
		}
		local test_pos = vector.add(p_pos, offset)

		-- Find solid ground level at this coordinate
		for dy = 3, -3, -1 do
			local cx = math.floor(test_pos.x + 0.5)
			local cy = math.floor(test_pos.y + dy + 0.5)
			local cz = math.floor(test_pos.z + 0.5)
			local check_pos = {x = cx, y = cy, z = cz}
			local node = core.get_node(check_pos)
			local def = core.registered_nodes[node.name]

			if def and def.walkable and def.liquidtype == "none" then
				local above1 = {x = check_pos.x, y = check_pos.y + 1, z = check_pos.z}
				local above2 = {x = check_pos.x, y = check_pos.y + 2, z = check_pos.z}
				local above3 = {x = check_pos.x, y = check_pos.y + 3, z = check_pos.z}

				local a1 = core.get_node(above1).name
				local a2 = core.get_node(above2).name
				local a3 = core.get_node(above3).name

				-- Must have 3 blocks of clear headroom for The Pale Watcher's 3.2m height
				if (a1 == "air" or not core.registered_nodes[a1].walkable) and
				   (a2 == "air" or not core.registered_nodes[a2].walkable) and
				   (a3 == "air" or not core.registered_nodes[a3].walkable) then

					local dest = {x = check_pos.x, y = check_pos.y + 1, z = check_pos.z}
					local dest_eye = {x = dest.x, y = dest.y + 2.8, z = dest.z}
					local to_dest = vector.direction(p_eye, dest_eye)

					-- Verify blind spot: either outside player's forward view cone OR occluded by terrain
					local is_in_blind_spot = (vector.dot(look_dir, to_dest) < WATCHER_FOV_DOT) or
						not x_mob_core.line_of_sight(p_eye, dest_eye)

					if is_in_blind_spot then
						return dest
					end
				end
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

	local min_ratio = min_mitigation_ratio or 0.25
	local min_dmg = min_damage or 2

	local mitigation = math.max(min_ratio, math.min(1.0, fleshy_group / 100.0))
	local desired_damage = math.max(min_dmg, math.floor(base_damage * mitigation + 0.5))
	desired_damage = math.min(base_damage, desired_damage)

	local punch_fleshy = desired_damage
	if fleshy_group < 100 then
		punch_fleshy = math.ceil(desired_damage * (100.0 / fleshy_group))
	end

	return punch_fleshy, desired_damage
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
	aggro_radius = 70.0,
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

	on_activate = function(self, _data, _dtime_s)
		if self.object then
			self.object:set_properties({
				glow = 3,
				mesh = "pale_watcher_mob.glb",
				textures = pale_watcher.get_textures(),
			})
		end
		local pos = self.object and self.object:get_pos()
		if pos then
			self.session_id = pale_watcher.ritual.start_session(self.object, pos)
			self.origin_pos = pos
			core.sound_play("pale_watcher_bell", {pos = pos, max_hear_distance = 45}, true)
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
	end,

	on_despawn = function(self)
		if self.session_id then
			pale_watcher.ritual.end_session(self.session_id, false)
			self.session_id = nil
		end
		pale_watcher.fx.clear_all()
	end,

	on_death = function(self, _killer)
		if self.session_id then
			pale_watcher.ritual.end_session(self.session_id, false)
			self.session_id = nil
		end
		pale_watcher.fx.clear_all()
	end,

	on_deactivate = function(self, _removal)
		if self.session_id then
			pale_watcher.ritual.end_session(self.session_id, false)
			self.session_id = nil
		end
		pale_watcher.fx.clear_all()
	end,

	on_step = function(self, dtime, _moveresult)
		if self.is_dead or self.state == "dead" or self.state == "dying" or self.state == "banishing" then return end

		local pos = self.object:get_pos()
		if not pos then return end

		local players = core.get_connected_players()
		if #players == 0 then return end

		local tier = self.session_id and pale_watcher.ritual.get_stalker_tier(self.session_id) or 0

		-- 1. Stun Window: Flash Camera blinding stagger
		if self.stun_timer > 0 then
			self.stun_timer = self.stun_timer - dtime
			self.object:set_velocity({x = 0, y = 0, z = 0})
			if self.stun_timer <= 0 then
				-- Stun expired: Immediate evasive phase retreat into distance
				local escape_pos = find_blind_spot_node(self.target_player or players[1], pos, 30, 45)
				if escape_pos then
					self.object:set_pos(escape_pos)
				end
				self.state = "stalking"
				core.sound_play("pale_watcher_static", {pos = self.object:get_pos(), max_hear_distance = 25}, true)
			end
			return
		end

		-- 2. Sunlight / Dawn Banishment Check
		local tod = core.get_timeofday()
		if tod >= 0.23 and tod <= 0.75 then -- Sunrise through daytime
			local nat_light = core.get_natural_light(pos)
			if nat_light and nat_light >= 14 then
				-- Catches fire and dissolves into static ash
				self.is_dead = true
				self.state = "dead"
				core.sound_play("pale_watcher_death", {pos = pos, max_hear_distance = 45})

				core.add_particlespawner({
					amount = 80,
					time = 1.5,
					pos = {min = vector.subtract(pos, 0.8), max = vector.add(pos, {x = 0.8, y = 3.0, z = 0.8})},
					vel = {min = {x = -1, y = 1, z = -1}, max = {x = 1, y = 4, z = 1}},
					texpool = {
						{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:2", blend = "add"},
						{name = "pale_watcher_particles.png^[verticalframe:8:4", blend = "add"},
						{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
					},
					minpos = vector.subtract(pos, 0.8),
					maxpos = vector.add(pos, {x = 0.8, y = 3.0, z = 0.8}),
					minvel = {x = -1, y = 1, z = -1},
					maxvel = {x = 1, y = 4, z = 1},
					minacc = {x = 0, y = 0, z = 0},
					maxacc = {x = 0, y = 1, z = 0},
					minexptime = 1.0,
					maxexptime = 2.0,
					minsize = 1.5,
					maxsize = 4.0,
					texture = "pale_watcher_particles.png^[verticalframe:8:4",
					glow = 12,
				})

				core.chat_send_all(core.colorize("#55ff88",
					"★ The morning dawn breaks the nightmare... The Pale Watcher dissolves into static ash."))
				if self.session_id then
					pale_watcher.ritual.end_session(self.session_id, true)
					self.session_id = nil
				end
				self.object:remove()
				return
			end
		end

		-- 3. Synchronize ritual session HUD with nearby players
		self._hud_timer = (self._hud_timer or 0) + dtime
		if self._hud_timer >= 0.5 then
			self._hud_timer = 0
			if self.session_id then
				pale_watcher.ritual.update_session_players(self.session_id, pos)
			end
		end

		-- 4. Target Acquisition & Tether Gauntlet Checks
		if not self.target_player or not x_mob_core.is_player_alive(self.target_player) then
			local closest = nil
			local min_d = math.huge
			for _, p in ipairs(players) do
				if x_mob_core.is_player_alive(p) then
					local d = vector.distance(pos, p:get_pos())
					if d < min_d and d < self.aggro_radius then
						min_d = d
						closest = p
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
			return
		end

		local t_pos = self.target_player:get_pos()
		local dist = vector.distance(pos, t_pos)

		-- Tether Gauntlet Escapes (Condition B: 70-Node Gauntlet)
		if self.origin_pos then
			local dist_from_origin = vector.distance(t_pos, self.origin_pos)

			-- Ambush at node 60: One final desperate intercept teleport
			if dist_from_origin >= WATCHER_AMBUSH_DIST and
			   dist_from_origin < WATCHER_TETHER_MAX and
			   not self.ambush_triggered then
				self.ambush_triggered = true
				local p_look = self.target_player:get_look_dir()
				local ambush_pos = vector.add(t_pos, vector.multiply(p_look, 10.0))
				self.object:set_pos(ambush_pos)
				core.sound_play("pale_watcher_scare", {pos = ambush_pos, max_hear_distance = 30}, true)
			end

			-- Crossing node 70: Escaped the domain gauntlet!
			if dist_from_origin >= WATCHER_TETHER_MAX then
				core.sound_play("pale_watcher_drone", {pos = t_pos, max_hear_distance = 50})
				core.chat_send_player(self.target_player:get_player_name(),
					core.colorize("#55ff88", "★ You have broken through the 70-node domain tether and escaped into the night!"))
				if self.session_id then
					pale_watcher.ritual.end_session(self.session_id, false)
					self.session_id = nil
				end
				self.object:remove()
				return
			end
		end

		-- 5. Light Source Extinguishing & Item Dropping
		self.light_check_timer = self.light_check_timer + dtime
		if self.light_check_timer >= 1.5 then
			self.light_check_timer = 0

			local mob_eye = vector.add(pos, {x = 0, y = 2.6, z = 0})
			local mob_chest = vector.add(pos, {x = 0, y = 1.5, z = 0})
			local reach = 5.5

			-- Extinguish world light nodes strictly within reach and unobstructed line of sight (not through walls).
			-- Exception: Sanctuary light (light level >= 14 or light_source >= 14) is immune to being dropped.
			local light_nodes = core.find_nodes_in_area(
				vector.subtract(pos, reach),
				vector.add(pos, reach),
				{"group:torch", "group:light", "default:torch", "default:torch_wall", "default:torch_ceiling"}
			)
			for _, lpos in ipairs(light_nodes) do
				if vector.distance(mob_eye, lpos) <= reach and not core.is_protected(lpos, "") then
					local lnode = core.get_node(lpos)
					local def = core.registered_nodes[lnode.name]
					local node_light = core.get_node_light(lpos) or 0
					local is_sanctuary = (node_light >= 14) or (def and def.light_source and def.light_source >= 14)

					-- Extinguish only if not sanctuary light and mob has clear line of sight
					if def and def.light_source and def.light_source > 0 and not is_sanctuary then
						local has_los = x_mob_core.line_of_sight(mob_eye, lpos) or x_mob_core.line_of_sight(mob_chest, lpos)
						if has_los then
							local drops = core.get_node_drops(lnode, "")
							core.remove_node(lpos)
							if drops then
								for i = 1, #drops do
									local stack = ItemStack(drops[i])
									if not stack:is_empty() then
										core.item_drop(stack, nil, lpos)
									end
								end
							end
							core.sound_play("pale_watcher_paper_burn", {pos = lpos, gain = 0.4, max_hear_distance = 15}, true)
							break -- 1 per pulse to create flickering dread
						end
					end
				end
			end

			-- Frightened player drops wielded light source only within reach & line of sight (not through walls).
			-- Exception: Never drop if player or light source is in sanctuary light (>= 14).
			if dist <= reach then
				local p_eye = vector.add(t_pos, {x = 0, y = 1.5, z = 0})
				local p_light = core.get_node_light(t_pos) or 0
				local player_in_sanctuary = p_light >= 14

				if not player_in_sanctuary then
					local has_los = x_mob_core.line_of_sight(mob_eye, p_eye) or x_mob_core.line_of_sight(mob_chest, p_eye)
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
								core.colorize("#ff5555", "Your trembling hands drop your light source into the darkness!"))
						end
					end
				end
			end
		end

		-- 6. Anti-Bunker Curse (Prevent 3-block dirt hole cheese)
		if dist <= 25.0 then
			local air_around_player = count_surrounding_air(t_pos)
			if air_around_player <= 3 then
				-- Player has sealed themselves in a cramped bunker!
				-- Phase-teleport directly adjacent / inside with psychic choke
				local choke_pos = vector.add(t_pos, {x = 0.5, y = 0, z = 0.5})
				self.object:set_pos(choke_pos)
				core.sound_play("pale_watcher_scare", {to_player = self.target_player:get_player_name()}, true)
				local punch_fleshy = calculate_armor_scaled_punch(self.target_player, 6, 0.33, 2)
				self.target_player:punch(self.object, 1.0, {
					full_punch_interval = 1.0,
					damage_groups = {fleshy = punch_fleshy}
				})
				core.chat_send_player(self.target_player:get_player_name(),
					core.colorize("#ff2222", "You cannot hide from the void..."))
				return
			end
		end

		-- 7. Condition A: Sanctuary Check (Light level >= 14)
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
				core.add_particlespawner({
					amount = 50,
					time = 1.0,
					pos = {min = vector.subtract(pos, 0.5), max = vector.add(pos, {x = 0.5, y = 3.0, z = 0.5})},
					vel = {min = {x = -0.5, y = 0.2, z = -0.5}, max = {x = 0.5, y = 1.5, z = 0.5}},
					texpool = {
						{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
						{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
					},
					minpos = vector.subtract(pos, 0.5),
					maxpos = vector.add(pos, {x = 0.5, y = 3.0, z = 0.5}),
					minvel = {x = -0.5, y = 0.2, z = -0.5},
					maxvel = {x = 0.5, y = 1.5, z = 0.5},
					minacc = {x = 0, y = 0, z = 0},
					maxacc = {x = 0, y = 0.2, z = 0},
					minexptime = 1.0,
					maxexptime = 2.0,
					minsize = 1.0,
					maxsize = 3.0,
					texture = "pale_watcher_particles.png^[verticalframe:8:0",
				})
				core.chat_send_player(self.target_player:get_player_name(),
					core.colorize("#55ff88", "The sanctuary light holds... The Pale Watcher dissolves into the dark tree line."))
				if self.session_id then
					pale_watcher.ritual.end_session(self.session_id, false)
					self.session_id = nil
				end
				self.object:remove()
				return
			end
			return
		else
			self.sanctuary_stare_timer = 0
		end

		-- 8. True Quantum Stalking & FOV Raycast
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
			end
		else
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
						-- Ensure ground node
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

			local horiz_dist = vector.distance({x = pos.x, y = 0, z = pos.z}, {x = t_pos.x, y = 0, z = t_pos.z})
			local vert_dist = math.abs(pos.y - t_pos.y)
			local in_attack_proximity = (dist <= self.attack_range) or (horiz_dist <= 2.2 and vert_dist <= 2.5)

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
	end,

	on_punch = function(self, puncher, _tflp, _tool_capabilities, _dir, _damage)
		-- Combat Resilience: Cannot be damaged by normal weapons
		-- Triggers immediate dimensional slip retreat into tree cover
		if puncher and puncher:is_player() then
			x_mob_core.indicate_damage(self.object)
			local cur_pos = self.object:get_pos()

			-- Departure dimensional slip particles
			core.add_particlespawner({
				amount = 40,
				time = 0.4,
				pos = {min = vector.subtract(cur_pos, 0.5), max = vector.add(cur_pos, {x = 0.5, y = 3.0, z = 0.5})},
				vel = {min = {x = -2, y = 0.5, z = -2}, max = {x = 2, y = 3.0, z = 2}},
				acc = {min = {x = -0.5, y = -2, z = -0.5}, max = {x = 0.5, y = 0, z = 0.5}},
				texpool = {
					{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
					{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
					{name = "pale_watcher_particles.png^[verticalframe:8:7", blend = "add"},
				},
				scale_tween = {start = 1.5, finish = 0.2},
				alpha_tween = {start = 1.0, finish = 0.0},
				minpos = vector.subtract(cur_pos, 0.5),
				maxpos = vector.add(cur_pos, {x = 0.5, y = 3.0, z = 0.5}),
				minvel = {x = -2, y = 0.5, z = -2},
				maxvel = {x = 2, y = 3.0, z = 2},
				minacc = {x = -0.5, y = -2, z = -0.5},
				maxacc = {x = 0.5, y = 0, z = 0.5},
				minexptime = 0.5,
				maxexptime = 1.2,
				minsize = 1.5,
				maxsize = 3.5,
				texture = "pale_watcher_particles.png^[verticalframe:8:0",
			})

			local escape_pos = find_blind_spot_node(puncher, cur_pos, 18, 28)
			if escape_pos then
				self.object:set_pos(escape_pos)
			end
			core.sound_play("pale_watcher_static", {pos = self.object:get_pos(), gain = 0.8, max_hear_distance = 25}, true)
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
		core.add_particlespawner({
			amount = 35,
			time = 0.6,
			pos = {
				min = vector.add(pos, {x = -0.3, y = 2.5, z = -0.3}),
				max = vector.add(pos, {x = 0.3, y = 3.2, z = 0.3}),
			},
			vel = {min = {x = -1, y = -0.5, z = -1}, max = {x = 1, y = 1.5, z = 1}},
			texpool = {
				{name = "pale_watcher_hud_flash.png", blend = "add"},
				{name = "pale_watcher_particles.png^[verticalframe:8:7", blend = "add"},
				{name = "pale_watcher_particles.png^[verticalframe:8:1", blend = "add"},
			},
			scale_tween = {start = 1.0, finish = 0.2},
			alpha_tween = {start = 1.0, finish = 0.0},
			minpos = vector.add(pos, {x = -0.3, y = 2.5, z = -0.3}),
			maxpos = vector.add(pos, {x = 0.3, y = 3.2, z = 0.3}),
			minvel = {x = -1, y = -0.5, z = -1},
			maxvel = {x = 1, y = 1.5, z = 1},
			minacc = {x = 0, y = -1, z = 0},
			maxacc = {x = 0, y = 0, z = 0},
			minexptime = 0.3,
			maxexptime = 0.8,
			minsize = 1.0,
			maxsize = 2.5,
			texture = "pale_watcher_hud_flash.png",
			glow = 12,
		})
	end,

	---Called when a player collects a Cursed Page.
	---Immediately prioritizes that player and snaps behind them.
	---@param collector ObjectRef
	on_page_collected = function(self, collector)
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
			local check_ground = vector.round(behind_pos)
			for dy = 2, -3, -1 do
				local test_ground = {x = check_ground.x, y = check_ground.y + dy, z = check_ground.z}
				local def = core.registered_nodes[core.get_node(test_ground).name]
				if def and def.walkable and def.liquidtype == "none" then
					local a1 = core.get_node({x = test_ground.x, y = test_ground.y + 1, z = test_ground.z}).name
					local a2 = core.get_node({x = test_ground.x, y = test_ground.y + 2, z = test_ground.z}).name
					local a3 = core.get_node({x = test_ground.x, y = test_ground.y + 3, z = test_ground.z}).name
					local def1 = core.registered_nodes[a1]
					local def2 = core.registered_nodes[a2]
					local def3 = core.registered_nodes[a3]
					if (a1 == "air" or (def1 and not def1.walkable)) and
					   (a2 == "air" or (def2 and not def2.walkable)) and
					   (a3 == "air" or (def3 and not def3.walkable)) then
						behind_pos = {x = test_ground.x, y = test_ground.y + 1, z = test_ground.z}
						break
					end
				end
			end
		end

		self.object:set_pos(behind_pos)
		self.object:set_yaw(core.dir_to_yaw(vector.direction(behind_pos, p_pos)))
		core.sound_play("pale_watcher_scare", {to_player = collector:get_player_name()}, true)
	end,

	---The Cleansing Flame Banishment Sequence.
	---The Pale Watcher is forcibly teleported into the pyre flames, paralyzed, implodes, and drops rare loot.
	---@param pyre_pos Vector
	---@param _summoner ObjectRef
	on_pyre_banished = function(self, pyre_pos, _summoner)
		self.state = "banishing"
		self.is_dead = true

		-- Forcibly snap directly into the pyre flames
		local snap_pos = {x = pyre_pos.x, y = pyre_pos.y + 0.2, z = pyre_pos.z}
		self.object:set_pos(snap_pos)
		self.object:set_velocity({x = 0, y = 0, z = 0})

		-- Paralyze in death_implode animation
		x_mob_core.play_animation(self.object, "death_implode", {
			speed = 1.0,
			loop = false,
			force = true,
			priority = 20,
		})

		core.sound_play("pale_watcher_paper_burn", {pos = snap_pos, gain = 1.0, max_hear_distance = 50})
		core.sound_play("pale_watcher_death", {pos = snap_pos, gain = 1.0, max_hear_distance = 50})

		-- Violent swirling implosion particles
		core.add_particlespawner({
			amount = 120,
			time = 2.0,
			pos = {min = vector.subtract(snap_pos, 1.2), max = vector.add(snap_pos, {x = 1.2, y = 3.2, z = 1.2})},
			vel = {min = {x = -2, y = 1, z = -2}, max = {x = 2, y = 5, z = 2}},
			acc = {min = {x = -1, y = -4, z = -1}, max = {x = 1, y = -1, z = 1}},
			texpool = {
				{name = "pale_watcher_ritual_pyre_flame.png^[verticalframe:8:1", blend = "add"},
				{name = "pale_watcher_particles.png^[verticalframe:8:0", blend = "alpha"},
				{name = "pale_watcher_particles.png^[verticalframe:8:4", blend = "add"},
				{name = "pale_watcher_particles.png^[verticalframe:8:7", blend = "add"},
			},
			scale_tween = {start = 2.5, finish = 0.2},
			alpha_tween = {start = 1.0, finish = 0.0},
			minpos = vector.subtract(snap_pos, 1.2),
			maxpos = vector.add(snap_pos, {x = 1.2, y = 3.2, z = 1.2}),
			minvel = {x = -2, y = 1, z = -2},
			maxvel = {x = 2, y = 5, z = 2},
			minacc = {x = -1, y = -4, z = -1},
			maxacc = {x = 1, y = -1, z = 1},
			minexptime = 1.0,
			maxexptime = 2.5,
			minsize = 2.0,
			maxsize = 5.0,
			texture = "pale_watcher_particles.png^[verticalframe:8:0",
			glow = 14,
		})

		-- Drop dimensional loot at pyre position
		x_mob_core.schedule(self, 2.0, "pyre_loot_drop", function(mob_self)
			local cur = mob_self.object and mob_self.object:get_pos()
			if cur then
				core.item_drop(ItemStack("pale_watcher:dimensional_cloth 3"), nil, cur)
				core.item_drop(ItemStack("pale_watcher:static_core 1"), nil, cur)
			end

			if mob_self.session_id then
				pale_watcher.ritual.end_session(mob_self.session_id, true)
				mob_self.session_id = nil
			end

			if mob_self.object and mob_self.object:is_valid() then
				mob_self.object:remove()
			end
		end)
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
