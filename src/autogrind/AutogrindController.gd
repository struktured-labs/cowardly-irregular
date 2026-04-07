extends Node

## AutogrindController - Orchestrates battle chaining between GameLoop and AutogrindSystem
## State machine: IDLE -> PRE_BATTLE -> BATTLE_RUNNING -> POST_BATTLE -> BETWEEN_BATTLES -> loop

signal grind_battle_requested(enemies: Array, terrain: String)
signal grind_complete(reason: String)
signal tier_changed(new_tier: int)
signal region_advanced(from_region: String, to_region: String, world_num: int)

enum State {
	IDLE,
	PRE_BATTLE,
	BATTLE_RUNNING,
	POST_BATTLE,
	BETWEEN_BATTLES
}

enum GrindTier {
	ACCELERATED,  # Full battles, high speed, turbo mode
	DASHBOARD,    # Mini battle + analytics dashboard
	# SIMULATION reserved for future
}

var _state: State = State.IDLE
var _party: Array = []
var _config: Dictionary = {}
var _saved_autobattle_states: Dictionary = {}
var _terrain: String = "plains"
var _between_battle_timer: float = 0.0
var _skip_next_battle: bool = false
var _current_tier: GrindTier = GrindTier.ACCELERATED
var _pending_tier_switch: int = -1  # -1 = no pending switch
var headless_mode: bool = false

## Tracks whether the current running battle is a meta-boss or collapse-boss fight
var _current_battle_is_meta_boss: bool = false
var _current_battle_is_collapse_boss: bool = false
var _current_meta_boss_data: Dictionary = {}

var _auto_advance_regions: bool = true  # Auto-advance to next world when region cracked
var _next_battle_enemy_boost: float = 0.0
var _next_battle_exp_bonus: float = 0.0

func _get_between_battle_delay() -> float:
	if headless_mode:
		return 0.0  # Ludicrous speed: no delay between battles
	match _current_tier:
		GrindTier.ACCELERATED:
			return 0.1
		GrindTier.DASHBOARD:
			return 0.1
		_:
			return 0.5


func _process(delta: float) -> void:
	if _state == State.BETWEEN_BATTLES:
		_between_battle_timer -= delta
		if _between_battle_timer <= 0:
			if _party.is_empty() or _party.all(func(m): return m is Combatant and not m.is_alive):
				stop_grind("No party available")
				return
			if _pending_tier_switch >= 0:
				_current_tier = _pending_tier_switch as GrindTier
				_pending_tier_switch = -1
				tier_changed.emit(_current_tier)
				print("[AUTOGRIND] Applied queued tier switch: %s" % GrindTier.keys()[_current_tier])
			_evaluate_and_apply_rules()
			_state = State.PRE_BATTLE
			_request_next_battle()


## Start a grinding session
func start_grind(party: Array, config: Dictionary, terrain: String = "plains") -> void:
	if _state != State.IDLE:
		print("[AUTOGRIND] Already grinding!")
		return

	# Filter out permadead characters
	_party = []
	for member in party:
		if member is Combatant:
			if AutogrindSystem.is_character_permadead(member.combatant_name):
				print("[AUTOGRIND] Skipping permadead character: %s" % member.combatant_name)
				continue
			if not member.is_alive:
				print("[AUTOGRIND] Skipping dead character: %s" % member.combatant_name)
				continue
		_party.append(member)

	if _party.is_empty():
		print("[AUTOGRIND] No alive party members available!")
		return

	_config = config
	_terrain = terrain
	var tier_val = config.get("tier", 0)
	_current_tier = tier_val as GrindTier
	headless_mode = config.get("ludicrous_speed", false)

	# Save and force autobattle states
	_save_autobattle_states()
	_force_autobattle_on()

	# Initialize AutogrindSystem
	var typed_party: Array[Combatant] = []
	for member in _party:
		if member is Combatant:
			typed_party.append(member)

	AutogrindSystem.start_autogrind(typed_party, {}, config)

	# Set region
	var region = config.get("region", "")
	if region != "":
		AutogrindSystem.set_current_region(region)

	# Read auto-advance setting (defaults to true)
	_auto_advance_regions = config.get("auto_advance", true)

	# Connect region_cracked signal for world progression
	if not AutogrindSystem.region_cracked.is_connected(_on_region_cracked):
		AutogrindSystem.region_cracked.connect(_on_region_cracked)

	# Apply current battle speed setting (persisted across battles in BattleScene)
	# Headless mode doesn't need engine time scaling since battles are pure math
	if not headless_mode:
		var BattleSceneScript = load("res://src/battle/BattleScene.gd")
		var speed_idx = BattleSceneScript._battle_speed_index
		if speed_idx < BattleSceneScript.BATTLE_SPEEDS.size():
			Engine.time_scale = BattleSceneScript.BATTLE_SPEEDS[speed_idx]
		else:
			Engine.time_scale = 2.0

	print("[AUTOGRIND] Controller started, requesting first battle")
	_state = State.PRE_BATTLE
	_request_next_battle()


## Evaluate autogrind rules between battles and apply any triggered actions
func _evaluate_and_apply_rules() -> void:
	var matched_rule = AutogrindSystem.evaluate_autogrind_rules(_party)
	if matched_rule.is_empty():
		return

	var actions = matched_rule.get("actions", [])
	if actions.is_empty():
		return

	# Intercept flee_battle before passing to AutogrindSystem so the controller
	# can set its own skip flag, then remove it from the list to avoid confusion.
	var filtered_actions: Array = []
	for action in actions:
		if action.get("type", "") == "flee_battle":
			_skip_next_battle = true
			print("[AUTOGRIND] Rule triggered: flee_battle -- next battle will be skipped")
		else:
			filtered_actions.append(action)

	if not filtered_actions.is_empty():
		AutogrindSystem.apply_autogrind_actions(filtered_actions)

	# Log which rule fired (for UI rule-trigger display)
	var rule_conditions = matched_rule.get("conditions", [])
	if not rule_conditions.is_empty():
		var desc = "Rule fired: "
		for cond in rule_conditions:
			desc += "%s %s %s " % [cond.get("type", "?"), cond.get("op", ""), str(cond.get("value", ""))]
		print("[AUTOGRIND] %s" % desc.strip_edges())


## Request the next battle in the chain
func _request_next_battle() -> void:
	if _state != State.PRE_BATTLE:
		return

	# If a flee_battle rule fired, skip one battle
	if _skip_next_battle:
		_skip_next_battle = false
		print("[AUTOGRIND] Skipping battle due to flee_battle rule")
		_state = State.BETWEEN_BATTLES
		_between_battle_timer = _get_between_battle_delay()
		return

	# Check for system fatigue events
	var fatigue = AutogrindSystem.check_fatigue_event()
	if not fatigue.is_empty():
		match fatigue["type"]:
			"enemy_boost":
				_next_battle_enemy_boost = 0.2
			"party_debuff":
				var alive_members = _party.filter(func(m): return m is Combatant and m.is_alive)
				if alive_members.size() > 0:
					var target = alive_members[randi() % alive_members.size()]
					var hp_loss = int(target.max_hp * 0.1)
					target.take_damage(hp_loss)
			"mp_drain":
				var alive = _party.filter(func(m): return m is Combatant and m.is_alive)
				if alive.size() > 0:
					var target = alive[randi() % alive.size()]
					var mp_loss = int(target.max_mp * 0.15)
					target.current_mp = max(0, target.current_mp - mp_loss)
			"item_loss":
				var alive = _party.filter(func(m): return m is Combatant and m.is_alive)
				if alive.size() > 0:
					var target = alive[randi() % alive.size()]
					for item_id in ["potion", "hi_potion", "ether", "hi_ether"]:
						if target.get_item_count(item_id) > 0:
							target.remove_item(item_id, 1)
							break
			"exp_surge":
				_next_battle_exp_bonus = 0.5  # +50% EXP next battle

	# Check interrupt conditions first
	var interrupt_reason = AutogrindSystem.pre_battle_check()
	if interrupt_reason != "":
		stop_grind(interrupt_reason)
		return

	# Check for system collapse — takes priority over regular meta-boss
	if AutogrindSystem.meta_corruption_level >= AutogrindSystem.corruption_threshold:
		_launch_collapse_boss_battle()
		return

	# Check for fatigue-triggered collapse
	if AutogrindSystem.check_fatigue_collapse():
		print("[AUTOGRIND] FATIGUE COLLAPSE — too many system events!")
		_launch_collapse_boss_battle()
		return

	# Check for regular meta-boss spawn
	if AutogrindSystem.should_spawn_meta_boss():
		_launch_meta_boss_battle()
		return

	# Normal battle — generate scaled enemies
	_current_battle_is_meta_boss = false
	_current_battle_is_collapse_boss = false
	_current_meta_boss_data = {}
	var enemies = _generate_scaled_enemies()
	_state = State.BATTLE_RUNNING
	grind_battle_requested.emit(enemies, _terrain)


## Launch a regular meta-boss battle
func _launch_meta_boss_battle() -> void:
	var boss_data := AutogrindSystem._spawn_meta_boss()
	if boss_data.is_empty():
		stop_grind("Meta-boss data unavailable")
		return

	_current_battle_is_meta_boss = true
	_current_battle_is_collapse_boss = false
	_current_meta_boss_data = boss_data

	print("[AUTOGRIND] Launching meta-boss battle: %s" % boss_data.get("name", "Meta-Boss"))
	_state = State.BATTLE_RUNNING
	grind_battle_requested.emit([boss_data], _terrain)


## Launch a system collapse boss battle
func _launch_collapse_boss_battle() -> void:
	AutogrindSystem._trigger_system_collapse()
	var boss_data := AutogrindSystem.build_meta_boss_enemy_data(true)

	_current_battle_is_meta_boss = true
	_current_battle_is_collapse_boss = true
	_current_meta_boss_data = boss_data

	print("[AUTOGRIND] SYSTEM COLLAPSE -- launching collapse boss: %s" % boss_data.get("name", "NULL::ENTITY"))
	_state = State.BATTLE_RUNNING
	grind_battle_requested.emit([boss_data], _terrain)


## Generate enemies with adaptation scaling
func _generate_scaled_enemies() -> Array:
	# Pick random enemies from BattleScene.MONSTER_TYPES
	var BattleSceneScript = load("res://src/battle/BattleScene.gd")
	var monster_types = BattleSceneScript.MONSTER_TYPES

	var num_enemies = randi_range(2, 3)
	var selected: Array = []

	for i in range(num_enemies):
		var base_type = monster_types[randi() % monster_types.size()]
		var base_data = {
			"id": base_type["id"],
			"name": base_type["name"],
			"color": base_type.get("color", Color.WHITE),
			"stats": base_type["stats"].duplicate(true),
			"weaknesses": base_type.get("weaknesses", []).duplicate(),
			"resistances": base_type.get("resistances", []).duplicate()
		}

		# Apply AutogrindSystem scaling
		var scaled = AutogrindSystem.create_scaled_enemy_data(base_data)
		selected.append(scaled)

	if _next_battle_enemy_boost > 0.0:
		for enemy_data in selected:
			for stat_key in enemy_data.get("stats", {}).keys():
				enemy_data["stats"][stat_key] = int(enemy_data["stats"][stat_key] * (1.0 + _next_battle_enemy_boost))
		_next_battle_enemy_boost = 0.0

	return selected


## Called when a battle ends
func on_battle_ended(victory: bool, exp_gained: int = 0, items_gained: Dictionary = {}) -> void:
	if _state != State.BATTLE_RUNNING:
		return

	_state = State.POST_BATTLE

	if _current_battle_is_collapse_boss:
		# Win or lose: apply post-collapse penalty then continue grinding
		AutogrindSystem.apply_post_collapse_penalty()
		if victory:
			print("[AUTOGRIND] Collapse boss defeated! Corruption reset, efficiency debuffed for 10 battles.")
			AutogrindSystem.on_meta_boss_victory(_current_meta_boss_data)
		else:
			print("[AUTOGRIND] Collapse boss won. Corruption reset, penalty still applied.")
		# Reset boss tracking
		_current_battle_is_meta_boss = false
		_current_battle_is_collapse_boss = false
		_current_meta_boss_data = {}
		# Continue grinding after a longer delay
		_state = State.BETWEEN_BATTLES
		_between_battle_timer = _get_between_battle_delay() * 2.0
		return

	if _current_battle_is_meta_boss:
		if victory:
			print("[AUTOGRIND] Meta-boss defeated! Bonus rewards and corruption reduced.")
			AutogrindSystem.on_meta_boss_victory(_current_meta_boss_data)
		else:
			print("[AUTOGRIND] Party lost to meta-boss! Corruption increased significantly.")
			AutogrindSystem.on_meta_boss_defeat(_current_meta_boss_data)
			# Check if the defeat pushed us into collapse territory
			if AutogrindSystem.meta_corruption_level >= AutogrindSystem.corruption_threshold:
				# Collapse will be handled next _request_next_battle call
				pass
			else:
				stop_grind("Defeated by meta-boss")
				return
		# Reset boss tracking
		_current_battle_is_meta_boss = false
		_current_battle_is_collapse_boss = false
		_current_meta_boss_data = {}
		_state = State.BETWEEN_BATTLES
		_between_battle_timer = _get_between_battle_delay()
		return

	# Normal battle resolution
	if victory:
		var effective_exp = exp_gained
		if _next_battle_exp_bonus > 0.0:
			effective_exp = int(exp_gained * (1.0 + _next_battle_exp_bonus))
			_next_battle_exp_bonus = 0.0
		AutogrindSystem.on_battle_victory(effective_exp, items_gained)
		_state = State.BETWEEN_BATTLES
		_between_battle_timer = _get_between_battle_delay()
	else:
		_next_battle_exp_bonus = 0.0
		AutogrindSystem.on_battle_defeat()
		if AutogrindSystem.is_grinding:
			# on_battle_defeat may have triggered permadeath and already stopped things
			stop_grind("Party defeated")


## Handle region cracked — auto-advance to next world if enabled
func _on_region_cracked(region_id: String, crack_level: int) -> void:
	if not _auto_advance_regions:
		print("[AUTOGRIND] Region %s cracked (level %d), auto-advance disabled" % [region_id, crack_level])
		return

	if crack_level < 1:
		return  # Only advance on first crack

	var next = AutogrindSystem.advance_to_next_region()
	if next.is_empty():
		print("[AUTOGRIND] Region cracked but no next world available (end of progression or locked)")
		return

	_terrain = next["region"]
	region_advanced.emit(region_id, next["region"], next["world"])
	print("[AUTOGRIND] Auto-advancing to %s (World %d)" % [next["name"], next["world"]])


## Stop the grind session
func stop_grind(reason: String = "Manual stop") -> void:
	if _state == State.IDLE:
		return

	_state = State.IDLE
	_current_battle_is_meta_boss = false
	_current_battle_is_collapse_boss = false
	_current_meta_boss_data = {}
	_pending_tier_switch = -1

	# Disconnect region_cracked signal
	if AutogrindSystem.region_cracked.is_connected(_on_region_cracked):
		AutogrindSystem.region_cracked.disconnect(_on_region_cracked)

	# Restore autobattle states
	_restore_autobattle_states()

	# Reset engine speed
	Engine.time_scale = 1.0

	# Stop the autogrind system
	AutogrindSystem.stop_autogrind(reason)

	print("[AUTOGRIND] Controller stopped: %s" % reason)
	grind_complete.emit(reason)


## Save current autobattle toggle states for all party members
func _save_autobattle_states() -> void:
	_saved_autobattle_states.clear()
	for member in _party:
		if member is Combatant:
			var char_id = member.combatant_name.to_lower().replace(" ", "_")
			_saved_autobattle_states[char_id] = AutobattleSystem.is_autobattle_enabled(char_id)


## Force autobattle ON for all party members
func _force_autobattle_on() -> void:
	for member in _party:
		if member is Combatant:
			var char_id = member.combatant_name.to_lower().replace(" ", "_")
			AutobattleSystem.set_autobattle_enabled(char_id, true)
			var active_script = AutobattleSystem.get_character_script(char_id)
			if active_script.is_empty() or not active_script.has("rules") or active_script["rules"].is_empty():
				var default_script = AutobattleSystem.create_default_character_script(char_id)
				AutobattleSystem.set_character_script(char_id, default_script)
				print("[AUTOGRIND] Created default autobattle script for %s" % char_id)
	print("[AUTOGRIND] Forced autobattle ON for all party members")


## Restore autobattle states to what they were before grinding
func _restore_autobattle_states() -> void:
	for char_id in _saved_autobattle_states:
		AutobattleSystem.set_autobattle_enabled(char_id, _saved_autobattle_states[char_id])
	_saved_autobattle_states.clear()
	print("[AUTOGRIND] Restored autobattle states")


## Get current grind stats for UI update
func get_grind_stats() -> Dictionary:
	var sys_stats := AutogrindSystem.get_grind_stats()
	return {
		"efficiency": AutogrindSystem.efficiency_multiplier,
		"corruption": AutogrindSystem.meta_corruption_level,
		"adaptation": AutogrindSystem.monster_adaptation_level,
		"region_crack": AutogrindSystem.region_crack_levels.get(AutogrindSystem.current_region_id, 0),
		"meta_boss_chance": AutogrindSystem.meta_boss_spawn_chance,
		"consecutive_wins": AutogrindSystem.consecutive_wins,
		"battles_won": AutogrindSystem.battles_completed,
		"total_exp": AutogrindSystem.total_exp_gained,
		"total_gold": sys_stats.get("total_gold", 0),
		"total_items": _count_total_items(),
		"collapse_count": AutogrindSystem.collapse_count,
		"post_collapse_debuff_battles": AutogrindSystem.post_collapse_debuff_battles,
		"permadead": AutogrindSystem.permadead_characters.duplicate(),
		"time_multiplier": AutogrindSystem.get_time_multiplier(),
		"fatigue_events_triggered": AutogrindSystem.fatigue_events_triggered
	}


func _count_total_items() -> int:
	var count = 0
	for key in AutogrindSystem.total_items_gained:
		count += AutogrindSystem.total_items_gained[key]
	return count


func switch_tier(new_tier: GrindTier) -> void:
	if new_tier == _current_tier:
		return
	if _state == State.BETWEEN_BATTLES or _state == State.IDLE:
		_current_tier = new_tier
		tier_changed.emit(new_tier)
		print("[AUTOGRIND] Switched to tier: %s" % GrindTier.keys()[new_tier])
	else:
		_pending_tier_switch = new_tier
		print("[AUTOGRIND] Tier switch queued for next between-battles: %s" % GrindTier.keys()[new_tier])


func get_current_tier() -> GrindTier:
	return _current_tier


func cycle_tier() -> void:
	var next = ((_current_tier as int) + 1) % 2  # Only 2 tiers for now
	switch_tier(next as GrindTier)


## Check if currently grinding
func is_grinding() -> bool:
	return _state != State.IDLE
