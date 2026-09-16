extends RefCounted
class_name HeadlessBattleResolver

## HeadlessBattleResolver — Pure math battle resolution for ludicrous speed autogrind.
## No scene tree, no rendering, no timers. Resolves a full battle in <1ms.

const MAX_ROUNDS = 50
const ACTION_SPEEDS = {"attack": 5, "ability": 10, "item": 8, "defend": 0, "defer": 0}

## Formation definitions (mirrored from BattleCommandMenu.FORMATIONS)
const FORMATIONS = [
	{"id": "four_heroes", "required_jobs": ["fighter", "cleric", "mage", "rogue"], "min_members": 4, "ap_cost": 2},
	{"id": "arcane_tempest", "required_jobs": ["mage", "cleric", "bard"], "min_members": 3, "ap_cost": 3},
	{"id": "blade_storm", "required_jobs": ["fighter", "rogue", "ninja"], "min_members": 3, "ap_cost": 2},
	{"id": "iron_wall", "required_jobs": ["fighter", "guardian", "cleric"], "min_members": 3, "ap_cost": 2},
	{"id": "shadow_strike", "required_jobs": ["rogue", "ninja"], "min_members": 2, "ap_cost": 2},
	{"id": "chaos_theory", "required_jobs": ["speculator", "bard"], "min_members": 2, "ap_cost": 3},
]

## Group attack cooldown — don't spam every round
const GROUP_ATTACK_COOLDOWN = 3
var _rounds_since_group_attack: int = 99

var _player_party: Array = []
var _enemy_party: Array = []
var _current_round: int = 0
var _battle_log: Array[String] = []


func resolve_battle(player_party: Array, enemy_party: Array) -> Dictionary:
	_player_party = player_party
	_enemy_party = enemy_party
	_current_round = 0
	_battle_log.clear()
	_rounds_since_group_attack = 99

	## Tick 145: mark encountered monsters as seen in the bestiary,
	## mirroring BattleScene._show_battle_quip. Pre-fix autogrind
	## battles never updated the bestiary — a player running
	## autogrind for hours could face hundreds of monster types
	## without any of them showing up in their bestiary.
	# Tick 260: pass current map id so the "Last seen: <location>"
	# bestiary hint reflects autogrind encounters too.
	var loc: String = ""
	if MapSystem and "current_map_id" in MapSystem:
		loc = str(MapSystem.current_map_id)
	for enemy in _enemy_party:
		if not is_instance_valid(enemy):
			continue
		var mtype: String = ""
		if enemy.has_method("get_meta") and enemy.has_meta("monster_type"):
			mtype = str(enemy.get_meta("monster_type", ""))
		if mtype != "":
			BestiarySystem.mark_seen(mtype, loc)

	# Edge case: empty or all-dead party = immediate defeat
	var alive_players = _player_party.filter(func(c): return c.is_alive)
	if alive_players.is_empty():
		_log("No alive party members — immediate defeat")
		return _build_results(false)

	# Edge case: no enemies = immediate victory with 0 EXP
	if _enemy_party.is_empty():
		_log("No enemies — immediate victory")
		return _build_results(true)

	# Temporarily register parties in BattleManager so AutobattleSystem
	# target-resolution (_get_enemies_for / _get_allies_for) works correctly.
	# Engine.has_singleton("BattleManager") is ALWAYS FALSE for autoloads in
	# Godot 4 — fetch from scene tree root, then fall back to _get_autoload
	# for the test harness path.
	var tree = Engine.get_main_loop()
	var bm: Node = null
	if tree is SceneTree and (tree as SceneTree).root != null:
		bm = (tree as SceneTree).root.get_node_or_null("BattleManager")
	if not bm:
		bm = _get_autoload("BattleManager")
	var _bm_player_backup: Array = []
	var _bm_enemy_backup: Array = []
	## `turn` / TURN_COUNT rule conditions read BattleManager.current_round, whose only writers are
	## on the live path — so a grind evaluated them against a frozen number and every turn-gated
	## rule was permanently true or permanently false. Borrow and restore it like the parties.
	var _bm_round_backup: int = 0
	if bm:
		_bm_player_backup = bm.player_party.duplicate()
		_bm_enemy_backup = bm.enemy_party.duplicate()
		_bm_round_backup = bm.current_round
		bm.player_party.clear()
		bm.enemy_party.clear()
		for c in _player_party:
			bm.player_party.append(c)
		for c in _enemy_party:
			bm.enemy_party.append(c)

	while _current_round < MAX_ROUNDS:
		_current_round += 1
		if bm:
			bm.current_round = _current_round

		_tick_round_start()

		var actions = _selection_phase()

		actions.sort_custom(func(a, b): return a.get("speed", 0) < b.get("speed", 0))

		for action in actions:
			_execute_action(action)

			if _all_dead(_enemy_party):
				if bm:
					_restore_bm(bm, _bm_player_backup, _bm_enemy_backup, _bm_round_backup)
				return _build_results(true)
			if _all_dead(_player_party):
				if bm:
					_restore_bm(bm, _bm_player_backup, _bm_enemy_backup, _bm_round_backup)
				return _build_results(false)

	# Cadence #19: MAX_ROUNDS exhaustion used to _build_results(false) silently — no log, no diagnostic. A player rule facing an unkillable enemy (healing boss, wrong element, undertuned party) would grind to a halt reporting defeats forever with no reason. Now: log + push_warning + termination_reason in results so callers can distinguish "died fair and square" from "battle timed out".
	_log("Battle exhausted MAX_ROUNDS=%d without resolution — treating as defeat" % MAX_ROUNDS)
	push_warning("[HeadlessBattleResolver] Battle stalemated at MAX_ROUNDS=%d — party may be undertuned for this encounter, or enemy has a heal/regen loop this ruleset can't break" % MAX_ROUNDS)
	if bm:
		_restore_bm(bm, _bm_player_backup, _bm_enemy_backup, _bm_round_backup)
	return _build_results(false, "stalemate")


func _restore_bm(bm, player_backup: Array, enemy_backup: Array, round_backup: int = 0) -> void:
	bm.current_round = round_backup
	bm.player_party.clear()
	bm.enemy_party.clear()
	for c in player_backup:
		bm.player_party.append(c)
	for c in enemy_backup:
		bm.enemy_party.append(c)


func _get_autoload(name: String) -> Object:
	var tree = Engine.get_main_loop()
	if tree and tree.root:
		return tree.root.get_node_or_null("/root/" + name)
	return null


func _tick_round_start() -> void:
	for combatant in _player_party + _enemy_party:
		if not combatant.is_alive:
			continue
		combatant.is_defending = false
		combatant.end_turn()
		if combatant.current_ap < 0:
			combatant.gain_ap(1)


func _selection_phase() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	_rounds_since_group_attack += 1

	# Try group attack first (cooldown, AP check, formation match)
	var group_action = _try_group_attack()
	if not group_action.is_empty():
		actions.append(group_action)
		# Group attack consumes all players' turns — skip to enemies
		for enemy in _enemy_party:
			if not enemy.is_alive:
				continue
			enemy.gain_ap(1)
			var skip = _check_status_skip(enemy)
			if skip != "":
				if skip == "confuse_attack":
					var confused_action = _confused_attack(enemy)
					confused_action["combatant"] = enemy
					confused_action["speed"] = _speed_for(confused_action, enemy)
					actions.append(confused_action)
				continue
			var a = _select_enemy_action(enemy)
			a["combatant"] = enemy
			a["speed"] = _speed_for(a, enemy)
			actions.append(a)
		return actions

	for combatant in _player_party:
		if not combatant.is_alive:
			continue
		combatant.gain_ap(1)

		# Status effect checks — match BattleManager behavior
		var skip = _check_status_skip(combatant)
		if skip != "":
			if skip == "confuse_attack":
				# Confused: attack random target (ally or enemy)
				var confused_action = _confused_attack(combatant)
				confused_action["combatant"] = combatant
				confused_action["speed"] = _speed_for(confused_action, combatant)
				actions.append(confused_action)
			continue

		var abs_node = _get_autoload("AutobattleSystem")
		var raw: Array[Dictionary] = []
		if abs_node:
			raw = abs_node.execute_grid_autobattle(combatant)
		else:
			raw = [_default_attack_action(combatant, _enemy_party)]

		if raw.size() == 1:
			var a = raw[0].duplicate()
			a["combatant"] = combatant
			a["speed"] = _speed_for(a, combatant)
			actions.append(a)
		elif raw.size() > 1:
			## ASK the live rule, never restate it. BattleManager.billed_ap is declared the one
			## authority ("Every readout must ask this rather than computing `queued` itself") after
			## two UI surfaces each rolled their own subtraction and both misreported a full-bank
			## turn. This resolver was a third: it charged size-1 at EVERY size, so a 3-action
			## Advance cost 2 AP here and 3 in the game it simulates — cheaper automation than
			## manual play, which is the yield tax inverted.
			## The cap is the live rule too: this line restated _apply_full_bank_rule under the comment above.
			var ruled: Array = BattleManager._apply_full_bank_rule(combatant, raw)["actions"]
			## Copied element-wise: the rule returns raw's own typed array today, but one rebuilt untyped would abort here.
			var kept: Array[Dictionary] = []
			for sub in ruled:
				kept.append(sub)
			raw = kept
			var ap_cost: int = BattleManager.billed_ap(combatant.current_ap, raw.size())
			if combatant.can_brave(ap_cost):
				combatant.spend_ap(ap_cost)
				for sub in raw:
					var a = sub.duplicate()
					a["combatant"] = combatant
					a["speed"] = _speed_for(a, combatant)
					actions.append(a)
			else:
				var a = raw[0].duplicate()
				a["combatant"] = combatant
				a["speed"] = _speed_for(a, combatant)
				actions.append(a)

	for enemy in _enemy_party:
		if not enemy.is_alive:
			continue
		enemy.gain_ap(1)

		# Status effect checks for enemies too
		var skip = _check_status_skip(enemy)
		if skip != "":
			if skip == "confuse_attack":
				var confused_action = _confused_attack(enemy)
				confused_action["combatant"] = enemy
				confused_action["speed"] = _speed_for(confused_action, enemy)
				actions.append(confused_action)
			continue

		var a = _select_enemy_action(enemy)
		a["combatant"] = enemy
		a["speed"] = _speed_for(a, enemy)
		actions.append(a)

	return actions


func _speed_for(action: Dictionary, combatant) -> int:
	var base = ACTION_SPEEDS.get(action.get("type", "attack"), 5)
	return base - combatant.speed


## Check status effects that skip a combatant's turn.
## Returns "" if no skip, "skip" to skip silently, "confuse_attack" for confusion.
## ═══════════════════════════════════════════════════════════════════════
## GROUP ATTACKS
## ═══════════════════════════════════════════════════════════════════════

func _try_group_attack() -> Dictionary:
	"""Attempt a group attack if conditions are met. Returns action dict or empty."""
	if _rounds_since_group_attack < GROUP_ATTACK_COOLDOWN:
		return {}

	var alive = _player_party.filter(func(c): return c.is_alive)
	if alive.size() < 2:
		return {}

	# Check for formation special first (most powerful)
	var formation = _detect_formation(alive)
	if not formation.is_empty():
		var ap_cost = formation["ap_cost"]
		if alive.all(func(c): return c.current_ap >= ap_cost):
			_rounds_since_group_attack = 0
			return _execute_group_formation(alive, formation)

	# Check for all-out attack (any 2+ alive party, 1 AP each)
	if alive.size() >= 2 and alive.all(func(c): return c.current_ap >= 1):
		# Only use all-out if multiple enemies alive (AoE value)
		var alive_enemies = _enemy_party.filter(func(e): return e.is_alive)
		if alive_enemies.size() >= 2:
			_rounds_since_group_attack = 0
			return _execute_group_physical(alive, "all_out_attack")

	return {}


func _detect_formation(alive_party: Array) -> Dictionary:
	"""Check if party jobs match any formation. Returns best match or empty."""
	var party_jobs: Array = []
	for m in alive_party:
		var job_id = m.job.get("id", "") if m.job else ""
		if job_id != "" and job_id not in party_jobs:
			party_jobs.append(job_id)

	for formation in FORMATIONS:
		if alive_party.size() < formation["min_members"]:
			continue
		var all_present = true
		for req_job in formation["required_jobs"]:
			if req_job not in party_jobs:
				all_present = false
				break
		if all_present:
			return formation
	return {}


func _execute_group_physical(participants: Array, group_type: String) -> Dictionary:
	"""Execute all-out attack — AoE physical damage to all enemies."""
	var total_power = 0.0
	for p in participants:
		if p is Combatant and p.is_alive:
			p.spend_ap(1)
			total_power += p.get_buffed_stat("attack", p.attack)

	var scale = pow(participants.size(), 1.5)
	var alive_enemies = _enemy_party.filter(func(e): return e.is_alive)

	for enemy in alive_enemies:
		var raw_damage = int(total_power * scale / max(1.0, float(alive_enemies.size())))
		var mitigated = max(1, raw_damage)
		enemy.take_damage(mitigated)
		_log("%s hits %s for %d!" % [group_type, enemy.combatant_name, mitigated])

	_log("GROUP: %s with %d participants!" % [group_type, participants.size()])
	return {"type": "group_done", "combatant": participants[0], "speed": -99}


func _execute_group_formation(participants: Array, formation: Dictionary) -> Dictionary:
	"""Execute a formation special based on party composition."""
	var formation_id = formation["id"]
	var ap_cost = formation["ap_cost"]
	var alive_enemies = _enemy_party.filter(func(e): return e.is_alive)

	for p in participants:
		if p is Combatant and p.is_alive:
			p.spend_ap(ap_cost)

	var scale = pow(participants.size(), 1.5)

	match formation_id:
		"four_heroes":
			var total_power = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_power += (p.get_buffed_stat("attack", p.attack) + p.get_buffed_stat("magic", p.magic)) * 0.5
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var damage = max(1, int(total_power * scale / max(1.0, float(alive_enemies.size()))))
				enemy.take_damage(damage)
				_log("Four Heroes strikes %s for %d!" % [enemy.combatant_name, damage])
			for p in participants:
				if p is Combatant and p.is_alive:
					p.heal(int(p.max_hp * 0.25))
			_log("FORMATION: Four Heroes — balanced strike + 25% party heal!")

		"arcane_tempest":
			var total_magic = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_magic += p.get_buffed_stat("magic", p.magic)
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var damage = max(1, int(total_magic * scale / max(1.0, float(alive_enemies.size()))))
				enemy.take_damage(damage, true)
				_log("Arcane Tempest blasts %s for %d!" % [enemy.combatant_name, damage])
			_log("FORMATION: Arcane Tempest — raw magic ignores resistances!")

		"blade_storm":
			var hit_count = participants.size() * 2
			for _hit in range(hit_count):
				var attacker = participants[randi() % participants.size()]
				if not (attacker is Combatant) or not attacker.is_alive: continue
				if alive_enemies.is_empty(): break
				var target = alive_enemies[randi() % alive_enemies.size()]
				if not target.is_alive: continue
				var base_dmg = int(attacker.get_buffed_stat("attack", attacker.attack) * 0.7)
				if randf() < 0.3:
					base_dmg = int(base_dmg * 1.5)
				var damage = max(1, base_dmg)
				target.take_damage(damage)
				_log("Blade Storm hits %s for %d!" % [target.combatant_name, damage])
			_log("FORMATION: Blade Storm — %d rapid strikes!" % hit_count)

		"iron_wall":
			for p in participants:
				if p is Combatant and p.is_alive:
					p.add_buff("iron_wall_def", "defense", 1.5, 3)
			var total_atk = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_atk += p.get_buffed_stat("attack", p.attack)
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var damage = max(1, int(total_atk * scale * 0.6 / max(1.0, float(alive_enemies.size()))))
				enemy.take_damage(damage)
				_log("Iron Wall crushes %s for %d!" % [enemy.combatant_name, damage])
			_log("FORMATION: Iron Wall — DEF +50%% (3 turns) + crushing blow!")

		"shadow_strike":
			var total_atk = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_atk += p.get_buffed_stat("attack", p.attack)
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var full_hp_bonus = 2.0 if enemy.current_hp == enemy.max_hp else 1.0
				var damage = max(1, int(total_atk * scale * full_hp_bonus / max(1.0, float(alive_enemies.size()))))
				enemy.take_damage(damage)
				_log("Shadow Strike hits %s for %d!" % [enemy.combatant_name, damage])
			_log("FORMATION: Shadow Strike — 2x on full HP!")

		"chaos_theory":
			var roll = randf()
			if roll < 0.4:
				var total_power = 0.0
				for p in participants:
					if p is Combatant and p.is_alive:
						total_power += (p.get_buffed_stat("attack", p.attack) + p.get_buffed_stat("magic", p.magic))
				for enemy in alive_enemies:
					if not enemy.is_alive: continue
					var damage = max(1, int(total_power * scale * 1.5 / max(1.0, float(alive_enemies.size()))))
					enemy.take_damage(damage, true)
				_log("FORMATION: Chaos Theory — JACKPOT! Massive damage!")
			elif roll < 0.7:
				for p in participants:
					if p is Combatant and p.is_alive:
						p.add_buff("chaos_atk", "attack", 1.3, 3)
						p.add_buff("chaos_def", "defense", 1.3, 3)
						p.add_buff("chaos_spd", "speed", 1.3, 3)
				_log("FORMATION: Chaos Theory — party buffed! ATK/DEF/SPD +30%%!")
			elif roll < 0.9:
				var total_power = 0.0
				for p in participants:
					if p is Combatant and p.is_alive:
						total_power += p.get_buffed_stat("attack", p.attack)
				for enemy in alive_enemies:
					if not enemy.is_alive: continue
					var damage = max(1, int(total_power * scale * 0.8 / max(1.0, float(alive_enemies.size()))))
					enemy.take_damage(damage)
				for p in participants:
					if p is Combatant and p.is_alive:
						p.heal(int(p.max_hp * 0.15))
				_log("FORMATION: Chaos Theory — moderate damage + party heal!")
			else:
				for p in participants:
					if p is Combatant and p.is_alive:
						p.take_damage(int(p.max_hp * 0.1))
				_log("FORMATION: Chaos Theory — BACKFIRE! Party takes recoil!")

		_:
			return _execute_group_physical(participants, "formation")

	return {"type": "group_done", "combatant": participants[0], "speed": -99}


func _check_status_skip(combatant) -> String:
	if combatant.has_status("stun"):
		combatant.remove_status("stun")
		_log("%s is stunned and cannot act!" % combatant.combatant_name)
		return "skip"

	if combatant.has_status("sleep"):
		if randf() < 0.3:
			combatant.remove_status("sleep")
			_log("%s woke up!" % combatant.combatant_name)
			return ""
		else:
			_log("%s is asleep..." % combatant.combatant_name)
			return "skip"

	if combatant.has_status("confuse"):
		if randf() < 0.4:
			combatant.remove_status("confuse")
			_log("%s snapped out of confusion!" % combatant.combatant_name)
			return ""
		else:
			_log("%s is confused and attacks wildly!" % combatant.combatant_name)
			return "confuse_attack"

	if combatant.has_status("fear"):
		if randf() < 0.25:
			combatant.remove_status("fear")
			_log("%s overcame their fear!" % combatant.combatant_name)
			return ""
		elif randf() < 0.5:
			_log("%s is paralyzed with fear!" % combatant.combatant_name)
			return "skip"

	return ""


## Confused attack: hit a random target from either side.
func _confused_attack(combatant) -> Dictionary:
	var all_alive: Array = []
	for p in _player_party:
		if p.is_alive:
			all_alive.append(p)
	for e in _enemy_party:
		if e.is_alive:
			all_alive.append(e)
	if all_alive.is_empty():
		return {"type": "defer"}
	var target = all_alive[randi() % all_alive.size()]
	return {"type": "attack", "target": target}


func _default_attack_action(combatant, enemies: Array) -> Dictionary:
	var alive = enemies.filter(func(e): return e.is_alive)
	if alive.is_empty():
		return {"type": "defer"}
	alive.sort_custom(func(a, b): return a.current_hp < b.current_hp)
	return {"type": "attack", "target": alive[0]}


func _select_enemy_action(enemy) -> Dictionary:
	var alive_players = _player_party.filter(func(p): return p.is_alive)
	if alive_players.is_empty():
		return {"type": "defer"}

	if enemy.current_hp < enemy.max_hp * 0.30:
		var heal_ability = _find_heal_ability(enemy)
		if heal_ability != "":
			var mp_cost = _get_ability_mp_cost(heal_ability)
			if enemy.current_mp >= mp_cost:
				return {"type": "ability", "ability_id": heal_ability, "targets": [enemy]}

	if enemy.current_mp > 0:
		var atk_ability = _find_attack_ability(enemy)
		if atk_ability != "":
			var mp_cost = _get_ability_mp_cost(atk_ability)
			if enemy.current_mp >= mp_cost:
				alive_players.sort_custom(func(a, b): return a.current_hp < b.current_hp)
				return {"type": "ability", "ability_id": atk_ability, "targets": [alive_players[0]]}

	alive_players.sort_custom(func(a, b): return a.current_hp < b.current_hp)
	return {"type": "attack", "target": alive_players[0]}


func _find_heal_ability(combatant) -> String:
	var js = _get_autoload("JobSystem")
	if not js:
		return ""
	for ability_id in combatant.learned_abilities:
		var ability = js.get_ability(ability_id) if js.has_method("get_ability") else {}
		# `type` is the field abilities author (289/289); `category` is authored by NONE, so this read was constant "" and no enemy ever healed in a headless battle.
		if str(ability.get("type", ability.get("category", ""))) == "healing":
			return ability_id
	return ""


func _find_attack_ability(combatant) -> String:
	var js = _get_autoload("JobSystem")
	if not js:
		return ""
	var best_id = ""
	var best_power = 0.0
	for ability_id in combatant.learned_abilities:
		var ability = js.get_ability(ability_id) if js.has_method("get_ability") else {}
		# Both keys were dead: `category` authored 0/289 (the field is `type`) and `power` 0/289 (it is `damage_multiplier`), so the guard never passed and this returned "" on every call — enemies fell through to a basic attack for the whole battle.
		var cat := str(ability.get("type", ability.get("category", "")))
		if cat in ["magic", "physical"]:
			var power := float(ability.get("power", ability.get("damage_multiplier", 0.0)))
			if power > best_power:
				best_power = power
				best_id = ability_id
	return best_id


func _get_ability_mp_cost(ability_id: String) -> int:
	var js = _get_autoload("JobSystem")
	if not js:
		return 0
	var ability = js.get_ability(ability_id) if js.has_method("get_ability") else {}
	return ability.get("mp_cost", 0)


func _execute_action(action: Dictionary) -> void:
	var combatant = action.get("combatant")
	if not combatant or not combatant.is_alive:
		return

	match action.get("type", "attack"):
		"attack":
			var target = action.get("target")
			if target and target.is_alive:
				var dmg = _resolve_attack(combatant, target)
				_log("%s attacks %s for %d" % [combatant.combatant_name, target.combatant_name, dmg])

		"ability":
			var ability_id = action.get("ability_id", "")
			var targets = action.get("targets", [])
			if ability_id != "" and targets.size() > 0:
				_resolve_ability(combatant, ability_id, targets)

		"item":
			var item_id = action.get("item_id", "")
			var targets = action.get("targets", [])
			if item_id != "" and targets.size() > 0:
				_resolve_item(combatant, item_id, targets[0])

		"defer":
			combatant.is_defending = true
			_log("%s defers" % combatant.combatant_name)

		"group_done":
			pass  # Already executed during selection phase


func _resolve_attack(attacker, target) -> int:
	if not target or not target.is_alive:
		return 0

	## BLIND: the live engine adds 0.40 to the miss rate (BattleManager's attack miss check) and this
	## resolver applied the status and then ignored it — the Bard's Riff inflicts blind on a 70% roll,
	## so his signature disruption did nothing in a grind while doing its job in a live fight.
	## INVISIBLE and SHADOW_STEP on the TARGET: the live engine misses outright and the status falls
	## off on the swing — "the swing reveals them" (_target_dodges_physical). Both were applied in a
	## grind and read by nobody, the same shape blind had, and both are cast by SHIPPED presets:
	## ninja_defensive spends 12 MP on vanish, ninja_balanced and ninja_aggressive 8 on shadow_step.
	## Checked before the miss ROLL rather than folded into it, because live does not roll at all.
	## ⚠️ Written as two LITERAL has_status calls rather than a loop over a list, deliberately. The
	## parity guard derives its ignored-status set by scanning both engines for has_status("…") and a
	## loop variable is invisible to it — the first draft of this fix used one, and the guard went on
	## reporting `invisible` as ignored while the code honoured it. A composed writer under a literal
	## scan is the exact shape that guard exists to catch, so the implementation reads the way the
	## measurement does.
	if target.has_status("invisible"):
		target.remove_status("invisible")
		_log("%s strikes thin air — %s was invisible!" % [attacker.combatant_name, target.combatant_name])
		return 0
	if target.has_status("shadow_step"):
		target.remove_status("shadow_step")
		_log("%s strikes thin air — %s had stepped into shadow!" % [attacker.combatant_name, target.combatant_name])
		return 0

	var base_miss: float = 0.10
	if attacker.has_status("blind"):
		base_miss += 0.40
	var miss_chance = max(0.02, min(0.60, base_miss - (attacker.speed - target.speed) * 0.05))
	if randf() < miss_chance:
		_log("%s misses %s!" % [attacker.combatant_name, target.combatant_name])
		return 0

	var damage = float(attacker.get_buffed_stat("attack", attacker.attack))
	## ONE-SHOT, consumed as live consumes it (BattleManager:4374-4377) — a charged strike pays off
	## once, not on every swing for the rest of the battle.
	damage *= _take_charged_multiplier(attacker)
	damage *= randf_range(0.85, 1.15)

	## SHADOW_STEP on the ATTACKER: a guaranteed crit live (_calculate_crit_chance returns 1.0 up
	## front). The Ninja's whole setup move is "step into the shadows so the next swing crits", and
	## in a grind it bought nothing at all.
	var crit_chance = min(0.50, 0.05 + attacker.speed * 0.01)
	var is_crit = randf() < crit_chance
	if attacker.has_status("shadow_step"):
		is_crit = true
	if is_crit:
		damage *= 1.5
		_log("Critical hit!")

	var def_val = float(target.get_buffed_stat("defense", target.defense))
	# Guard divisor (mirrors Combatant.take_damage). attack 0 + defense 0
	# combinations are reachable: get_buffed_stat returns 0 for base 0
	# (the maxi(1, …) clamp only applies when base > 0), so a base-0
	# attack stat × base-0 defense produces a 0/0 NaN that int() casts
	# to a sentinel — silent garbage damage in autogrind sims.
	var denom = maxf(1.0, damage + def_val)
	var actual = int((damage * damage) / denom)
	actual = max(1, actual)
	if target.is_defending:
		actual = actual / 2

	target.take_damage(actual)
	return actual


## Canonical effect -> [stat, modifier] pairs, mirroring BattleManager's own names. Only the
## shapes headless actually needs; anything absent is handled as a status or a no-op, never damage.
func _effect_to_stat(effect: String) -> Array:
	match effect:
		"attack_up": return ["attack", 1.5]
		"defense_up": return ["defense", 1.5]
		"magic_up": return ["magic", 1.5]
		"speed_up": return ["speed", 1.5]
		"magic_defense_up": return ["magic_defense", 1.5]
		"attack_down": return ["attack", 0.75]
		"defense_down": return ["defense", 0.75]
		"magic_down": return ["magic", 0.75]
		"speed_down": return ["speed", 0.75]
		"volatility_down": return ["volatility", 0.75]
	return []


## Same side = both in the player party, or neither. Used to refuse friendly fire from an
## ability type this resolver does not model.
func _is_same_side(a, b) -> bool:
	return (a in _player_party) == (b in _player_party)


func _resolve_ability(caster, ability_id: String, targets: Array) -> void:
	var js = _get_autoload("JobSystem")
	var ability: Dictionary = {}
	if js and js.has_method("get_ability"):
		ability = js.get_ability(ability_id)

	## An id JobSystem cannot resolve returns {}, and `type` then defaults to "magic" below — so a
	## typo'd or removed ability in an autobattle script DEALT MAGIC DAMAGE, to an ally when the
	## script aimed it at one. Found by a census control asserting an unknown id is a no-op.
	## You cannot resolve what you cannot read: do nothing, and do not charge MP for it.
	if ability.is_empty():
		_log("%s: unknown ability '%s' — no effect" % [caster.combatant_name, ability_id])
		return

	var mp_cost = ability.get("mp_cost", 5)
	if not caster.spend_mp(mp_cost):
		_log("%s has no MP for %s" % [caster.combatant_name, ability_id])
		return

	## Tick 393: dispatch on `type` (the canonical abilities.json
	## schema field) instead of `category` (which no ability authors).
	## Pre-fix `ability.get("category", "magic")` always returned the
	## "magic" default for every ability, so the `match category:` arm
	## always fired the magic-damage branch — heal abilities dealt
	## magic damage to the target instead of healing, support abilities
	## did nothing useful, etc. Major divergence between live combat
	## and autogrind simulation that silently corrupted reward
	## calculations whenever a non-physical-non-magic ability fired.
	##
	## Also accept `damage_multiplier` as a power fallback so abilities
	## that author the canonical magic-shape field aren't reading the
	## default 1.0 (which would silently nerf eidolon casts and similar).
	var category = ability.get("type", ability.get("category", "magic"))
	## A healing ability that heals OVER TIME reaches the wrong arm otherwise. `regenerate` authors
	## `effect: regen` with `regen_per_turn: 40` and NO heal_amount, so the healing arm's fallback healed
	## magic x power ONCE and ticked nothing. Live routes exactly this shape to its support executor
	## (cowir-battle dcfb2158). Re-pointed rather than copied: the support arm below already owns what
	## an `effect` means, and duplicating it here is how two definitions of "regen" start to drift.
	if category == "healing" and str(ability.get("effect", "")) != "" and int(ability.get("heal_amount", 0)) <= 0:
		category = "support"
	var power = ability.get("power", ability.get("damage_multiplier", 1.0))
	var element = ability.get("element", "")
	## Live runs the damage step `hits` times (BattleManager:4854) for the 5 abilities that author it —
	## all monster-side, all drawn from the same pools the grind draws from, so the grind was taking a
	## third of the authored damage from them. Third instance of this file's field-mismatch class.
	var hits: int = max(1, int(ability.get("hits", 1)))
	## Live heals the caster for this share of the damage it actually dealt (BattleManager:5121). Four
	## POOLED monsters drain — specter, pipe_phantom, shadow_knight, bone_warden — and the Necromancer's
	## drain_life is a player build. Neither side healed in the grind.
	var drain_pct: float = float(ability.get("drain_percentage", 0))
	## Multiplies the POWER, so it must land before either damage arm reads it.
	power = float(power) * _missing_hp_multiplier(caster, ability)

	match category:
		"healing":
			for target in targets:
				if target and target.is_alive:
					## `heal_amount` is what healing abilities author (6/7; regenerate is a regen
					## effect with none) — `power`/`damage_multiplier` are authored by 0 of 7, so
					## this read the 1.0 default and healed magic*1 instead of the authored value.
					## cure at magic 20: 20 HP here vs 1300 live. Same field-mismatch class the two
					## comments above document, on the arm nobody revisited. Formula mirrors
					## BattleManager:5227 so headless and live agree.
					var authored = int(ability.get("heal_amount", 0))
					var heal_amount = int(authored * (1.0 + caster.get_buffed_stat("magic", caster.magic) / 20.0)) if authored > 0 else int(caster.get_buffed_stat("magic", caster.magic) * power)
					heal_amount = max(1, heal_amount)
					var healed = target.heal(heal_amount)
					_log("%s heals %s for %d" % [caster.combatant_name, target.combatant_name, healed])

		"magic":
			## BEFORE the loop and ONCE, mirroring BattleManager:4969 — an AoE gets the boosted
			## multiplier on every target and the charge clears a single time, not per target.
			power = float(power) * _take_charged_multiplier(caster)
			## Accumulated ACROSS the cast, because live's recoil is proportional to the whole volley
			## (BattleManager:4981/5172) — stack_overflow hits all_enemies and pays 20% of the total.
			var total_for_recoil: int = 0
			for target in targets:
				if target and target.is_alive:
					var base_dmg = int(caster.get_buffed_stat("magic", caster.magic) * power)
					## Doubles, mirroring BattleManager:5054 — live's own comment calls it "a rough
					## compensation for take_damage's defense formula" rather than a true-damage path, and
					## the grind must compensate the same way or phantom_byte lands at half strength here.
					if bool(ability.get("ignores_defense", false)):
						base_dmg *= 2
					## Rolled BEFORE the elemental multiplier, mirroring BattleManager:5013-5015 — live
					## applies it to `damage` ahead of the terrain/element path, and the order changes the
					## spread once a weakness or resistance is in play. type_error authors 2.0, so its roll
					## spans [0, 2x] where every other spell sits near 1.0; forgotten_variable (POOLED)
					## casts it, and a grind met a predictable attacker where the real game met a swingy one.
					var variance: float = float(ability.get("damage_variance", 0.0))
					if variance > 0.0:
						base_dmg = int(base_dmg * randf_range(0.0, variance))
					var elem_mod = target.calculate_elemental_modifier(element) if element != "" else 1.0
					var actual = int(base_dmg * elem_mod)
					actual = max(1, actual)
					if target.is_defending:
						actual = actual / 2
					## ONE HIT, deliberately. Live reads `hits` only in _execute_physical_ability, so
					## temporal_strike (magic, hits=2) strikes ONCE in the real game. I looped here in
					## 04f2b2f8 and the grind hit harder than the game it simulates — @cowir-battle 2d14d92d.
					var dealt: int = target.take_damage(actual, true)
					_drain_to(caster, dealt, drain_pct, ability_id)
					## PER TARGET and gated on damage landing, mirroring BattleManager:5085-5090 — so
					## memory_drain (all_enemies) stacks its restore across the party exactly as live does.
					_siphon_mp(caster, ability, dealt, ability_id)
					_log("%s casts %s on %s for %d" % [caster.combatant_name, ability_id, target.combatant_name, dealt])
					total_for_recoil += dealt
					_maybe_inflict_status(caster, target, ability, ability_id)
			_recoil_to(caster, ability, total_for_recoil, ability_id)

		"physical":
			for target in targets:
				if target and target.is_alive:
					var base_dmg = int(_scaled_base(caster, ability) * power)
					## HP DELTA, not the helper's return: _resolve_attack_with_power returns its computed
					## figure and take_damage then applies the defense formula AGAIN, so the return runs
					## high. Live drains a share of what was ACTUALLY dealt, and the log should say so too.
					var hp_before: int = target.current_hp
					for _h in hits:
						if not target.is_alive:
							break
						_resolve_attack_with_power(caster, target, base_dmg)
					var dmg: int = hp_before - target.current_hp
					## NO DRAIN HERE, deliberately: live reads drain_percentage only in _execute_magic_ability, so
					## dark_slash (physical, 30%) heals its caster in NEITHER engine. Draining here would make the
					## grind heal bone_warden and shadow_knight where the game does not (@cowir-battle 2d14d92d).
					_log("%s uses %s on %s for %d" % [caster.combatant_name, ability_id, target.combatant_name, dmg])
					_maybe_inflict_status(caster, target, ability, ability_id)

		"mp_restore":
			## pray (single_ally) and channel (self) had no arm and fell to the default, which
			## DAMAGED the ally they restore. Arm from cowir-battle's a0e74614 — the authored
			## mp_amount is the source and `power` is only the fallback, mirroring the healing
			## arm and avoiding the field-mismatch class this file documents twice already.
			for target in targets:
				if target and target.is_alive:
					var authored_mp := int(ability.get("mp_amount", 0))
					var mp_amount := authored_mp if authored_mp > 0 else int(caster.get_buffed_stat("magic", caster.magic) * power)
					var restored = target.restore_mp(max(1, mp_amount))
					_log("%s restores %d MP to %s" % [caster.combatant_name, restored, target.combatant_name])

		"revival":
			## Mirrors BattleManager._execute_revival_ability:5470-5477 — authored
			## revive_percentage of max_hp, living targets skipped. Routed through
			## Combatant.revive so a permakilled PC stays dead in a grind too.
			var revive_pct := float(ability.get("revive_percentage", 50))
			for target in targets:
				if target == null or not is_instance_valid(target) or target.is_alive:
					continue
				target.revive(int(target.max_hp * revive_pct / 100.0))
				_log("%s revives %s with %d HP" % [caster.combatant_name, target.combatant_name, target.current_hp])

		"support", "song", "status":
			## BattleManager:4424 groups these three in one arm; headless had only "support", so
			## every song fell to the `_:` damage default below — battle_hymn cost the ally it
			## buffs 25 HP. Grouping alone is not enough: the support path reads stat/modifier
			## and songs author `effect`, so discord would have BUFFED the enemy's attack.
			for target in targets:
				if target == null or not target.is_alive:
					continue
				var duration = int(ability.get("duration", 3))
				var effect := str(ability.get("effect", ""))
				var stat = ability.get("stat", "")
				var modifier = float(ability.get("modifier", ability.get("stat_modifier", 1.5)))
				if stat == "" and effect != "":
					var mapped: Array = _effect_to_stat(effect)
					if not mapped.is_empty():
						stat = mapped[0]
						modifier = float(mapped[1])
					elif effect == "all_stats_down":
						## Mirrors BattleManager:5887. Four DISTINCT names on purpose — add_debuff
						## keys on the name and refreshes in place, so one shared name would
						## debuff a single stat and look like it worked.
						var mod := float(ability.get("stat_modifier", ability.get("modifier", 0.75)))
						target.add_debuff("Despair (ATK)", "attack", mod, duration)
						target.add_debuff("Despair (DEF)", "defense", mod, duration)
						target.add_debuff("Despair (SPD)", "speed", mod, duration)
						target.add_debuff("Despair (MAG)", "magic", mod, duration)
						_log("%s uses %s on %s (all stats down)" % [caster.combatant_name, ability_id, target.combatant_name])
						continue
					elif effect == "cleanse":
						## Esuna is in the DEFAULT cleric script and two presets, and headless had no
						## arm for it — so it fell to the generic add_status below and gave the ally a
						## junk status called "cleanse" while the blind it was cast to cure stayed on.
						## The ailment list is BattleManager:6104 verbatim — that array is the parity
						## anchor, NOT the has_status call, which takes a loop variable on both sides
						## and is invisible to a literal `has_status("x")` scan either way.
						var cleansed: Array[String] = []
						for ailment in ["poison", "blind", "sleep", "stun", "burning", "curse", "confuse", "fear", "charm", "doom"]:
							if target.has_status(ailment):
								cleansed.append(ailment)
								target.remove_status(ailment)
						if target.doom_counter > 0:
							target.doom_counter = 0
							if not cleansed.has("doom"):
								cleansed.append("doom")
						if cleansed.is_empty():
							_log("%s uses %s on %s (nothing to cleanse)" % [caster.combatant_name, ability_id, target.combatant_name])
						else:
							_log("%s cleanses %s (%s)" % [caster.combatant_name, target.combatant_name, ", ".join(cleansed)])
						continue
					elif effect == "mp_restore_and_ap":
						target.restore_mp(int(target.max_mp * 0.25))
						target.gain_ap(1)
						_log("%s uses %s on %s (MP + AP)" % [caster.combatant_name, ability_id, target.combatant_name])
						continue
					elif effect == "regen":
						## Combatant.end_turn ticks "regen" and reads an authored override off
						## `_regen_per_turn`, falling back to 5% of max HP when absent — so adding the
						## status alone would heal the DEFAULT, not the authored 40. Live sets both
						## (BattleManager's regen arm); so do we, or the amount silently differs.
						target.add_status("regen", duration)
						if target.has_method("set_meta"):
							target.set_meta("_regen_per_turn", int(ability.get("regen_per_turn", 0)))
						_log("%s grants regen to %s (%d/turn for %d)" % [caster.combatant_name, target.combatant_name, int(ability.get("regen_per_turn", 0)), duration])
						continue
					else:
						## Live owns a ~40-arm effect table; headless deliberately does NOT mirror
						## it. An effect we do not model is a NO-OP, never damage.
						target.add_status(effect, duration)
						_log("%s uses %s on %s (%s)" % [caster.combatant_name, ability_id, target.combatant_name, effect])
						continue
				if stat == "":
					stat = "attack"
				if modifier >= 1.0:
					target.add_buff(ability_id, stat, modifier, duration)
				else:
					target.add_debuff(ability_id, stat, modifier, duration)
				_log("%s uses %s on %s" % [caster.combatant_name, ability_id, target.combatant_name])
			## ONCE per cast, after the loop — live calls it once with the whole target list, and a
			## per-target call would roll howl's 0.3 fear separately for each enemy it already covers.
			_apply_secondary_effect(caster, ability, targets, ability_id)
			## Stored on the CASTER for its next swing, mirroring BattleManager:6326 — burrow authors 1.5
			## and ironback_beetle (POOLED) casts it, so the telegraph never paid off in a grind.
			var nam: float = float(ability.get("next_attack_multiplier", 0.0))
			if nam > 0.0 and caster != null and caster.is_alive:
				caster.set_meta("_next_attack_multiplier", nam)
				_log("%s charges its next strike (x%.1f) with %s" % [caster.combatant_name, nam, ability_id])

		_:
			## Was: magic damage to targets[0]. AutobattleSystem builds targets from target_type,
			## so an all_allies ability arrived holding the PARTY and this attacked them. 39
			## abilities author a type with no arm (meta 24 · summon 7 · song 4 · mp_restore 2 ·
			## revival 1 · escape 1), so the blast radius was never just the Bard.
			var target = targets[0] if targets.size() > 0 else null
			if target and target.is_alive:
				if _is_same_side(caster, target):
					_log("%s uses %s on %s (unmodelled type — no effect)" % [caster.combatant_name, ability_id, target.combatant_name])
				else:
					var base_dmg = int(caster.get_buffed_stat("magic", caster.magic) * power)
					target.take_damage(max(1, base_dmg), true)
					_log("%s uses %s on %s" % [caster.combatant_name, ability_id, target.combatant_name])


## The status a DAMAGING ability inflicts, on the same roll the live engine makes.
##
## ⛔ Headless dealt the damage and dropped the status entirely: 68 abilities author `effect_chance`
## (0.2 to 1.0) and the grind honoured none of them, in EITHER direction — the Bard's Riff never
## blinded, plague_bite never poisoned at its authored 1.0, and no enemy ever stunned the party. A
## player spends hours in the grind, so this is not a corner.
##
## Mirrors BattleManager:4899-4920 — the parity anchor, including both of its aliases and its
## deliberate 0.0 default (a damaging ability opts IN to a status by authoring a chance; only
## `random_debuff` defaults to 1.0, because two abilities present the debuff as their headline and
## omit the key). Kept as literal arms rather than a shared helper for the reason this file's other
## mirrors are: the two engines are separate implementations, and the parity guard scans both.
const _RANDOM_DEBUFF_POOL := ["poison", "blind", "burn", "confuse", "fear", "silence", "curse"]


func _maybe_inflict_status(caster, target, ability: Dictionary, ability_id: String) -> void:
	if target == null or not target.is_alive:
		return
	var effect := str(ability.get("effect", ""))
	if effect == "":
		return
	var chance: float = float(ability.get("effect_chance", 1.0 if effect == "random_debuff" else 0.0))
	if chance <= 0.0 or randf() >= chance:
		return
	var status_to_add := effect
	if effect == "random_debuff":
		status_to_add = _RANDOM_DEBUFF_POOL[randi() % _RANDOM_DEBUFF_POOL.size()]
	## freeze aliases to stun and burn to burning — the DoT ticks only "burning", and both aliases
	## are applied at the same point live applies them, so the cleanse lists match too.
	if status_to_add == "freeze":
		status_to_add = "stun"
	if status_to_add == "burn":
		status_to_add = "burning"
	target.add_status(status_to_add, int(ability.get("duration", 3)))
	_log("%s inflicts %s on %s (%s)" % [caster.combatant_name, status_to_add, target.combatant_name, ability_id])

## Drains a share of damage ACTUALLY DEALT back to the caster, mirroring BattleManager:5121-5123.
## Takes the accumulated total so a multi-hit drain heals off the whole volley, as live does.
func _drain_to(caster, damage_dealt: int, drain_pct: float, ability_id: String) -> void:
	if drain_pct <= 0.0 or damage_dealt <= 0:
		return
	var drained: int = int(damage_dealt * drain_pct / 100.0)
	if drained <= 0:
		return
	var healed: int = caster.heal(drained)
	_log("%s drains %d HP with %s" % [caster.combatant_name, healed, ability_id])



## The stat a physical ability computes its damage FROM, and the missing-HP multiplier, mirroring
## BattleManager:4736-4758.
##
## ⛔ Headless used `attack` for every physical ability, so guard_strike on a high-defense caster dealt
## poverty damage — the live engine's own words for the same bug when IT had it (tick 437). rat_guard
## (pooled) casts guard_strike; throw_shuriken and last_stand_ability are job abilities.
##
## ⛔ `target_defense` and `most_used_ability` are NOT here, and that is deliberate: LIVE reads neither
## (0 references), so `complement` and `player_knowledge` scale from attack in both engines. Wiring
## them here alone would push the simulation past the game it simulates. Declared, with an arm that
## reds if live starts reading either.
func _scaled_base(caster, ability: Dictionary) -> int:
	match str(ability.get("scales_with", "")):
		"defense":
			return int(caster.get_buffed_stat("defense", caster.defense))
		"speed":
			return int(caster.get_buffed_stat("speed", caster.speed))
		_:
			return int(caster.get_buffed_stat("attack", caster.attack))


## Linear from 1.0x at full HP to max_multiplier at zero, exactly as live computes it. Separate from
## _scaled_base because it multiplies the POWER rather than swapping the base stat.
func _missing_hp_multiplier(caster, ability: Dictionary) -> float:
	if str(ability.get("scales_with", "")) != "missing_hp" or caster.max_hp <= 0:
		return 1.0
	var hp_pct: float = float(caster.current_hp) / float(caster.max_hp)
	var max_mult: float = float(ability.get("max_multiplier", 5.0))
	return 1.0 + (1.0 - hp_pct) * (max_mult - 1.0)

## The SECOND effect a support ability authors, on the same roll the live engine makes.
##
## ⛔ 9 abilities author `secondary_effect` and the grind honoured none — so a spider's web_shot only
## slowed and never stunned, a wolf's howl never frightened the party, and enrage was a free attack
## buff with no defense penalty. Six of the casters are POOLED monsters a grind draws every session.
##
## Mirrors BattleManager:6368 — its target groups, its `secondary_chance` default of 1.0, its
## `secondary_modifier` default of 0.7, and its fall-through to add_status for a name that is not a
## stat. Called from the support arm ONLY, which is where live calls it (_execute_support_ability is
## its single call site): `subset_drain` (magic) and `toxic_embrace` (physical) therefore keep their
## secondaries dropped HERE TOO, because live drops them. Applying them only in the grind would make
## the grind harsher than the game it simulates, which is this file's own failure mode inverted.
const _SECONDARY_STAT_BUFF_MAP: Dictionary = {
	"attack_up": ["attack", "Secondary Attack Up"],
	"defense_up": ["defense", "Secondary Defense Up"],
	"magic_up": ["magic", "Secondary Magic Up"],
	"speed_up": ["speed", "Secondary Speed Up"],
	"magic_defense_up": ["magic_defense", "Secondary Magic Defense Up"],
}
const _SECONDARY_STAT_DEBUFF_MAP: Dictionary = {
	"attack_down": ["attack", "Secondary Attack Down"],
	"defense_down": ["defense", "Secondary Defense Down"],
	"magic_down": ["magic", "Secondary Magic Down"],
	"speed_down": ["speed", "Secondary Speed Down"],
	"magic_defense_down": ["magic_defense", "Secondary Magic Defense Down"],
}


func _apply_secondary_effect(caster, ability: Dictionary, primary_targets: Array, ability_id: String) -> void:
	var sec_effect: String = str(ability.get("secondary_effect", ""))
	if sec_effect == "":
		return
	var sec_chance: float = clampf(float(ability.get("secondary_chance", 1.0)), 0.0, 1.0)
	if sec_chance <= 0.0:
		return
	var sec_targets: Array = []
	## Sides resolved by MEMBERSHIP, from the caster out. A grind resolves monster casts too, so a
	## fixed `_enemy_party` here would make a wolf's howl frighten its own pack.
	var caster_is_player: bool = _player_party.has(caster)
	var foes: Array = _enemy_party if caster_is_player else _player_party
	var allies: Array = _player_party if caster_is_player else _enemy_party
	match str(ability.get("secondary_target", "")):
		"all_enemies":
			for c in foes:
				if c != null and c.is_alive:
					sec_targets.append(c)
		"all_allies":
			for c in allies:
				if c != null and c.is_alive:
					sec_targets.append(c)
		"self":
			if caster != null and caster.is_alive:
				sec_targets.append(caster)
		_:
			for t in primary_targets:
				if t != null and t.is_alive:
					sec_targets.append(t)
	if sec_targets.is_empty():
		return
	var sec_modifier: float = float(ability.get("secondary_modifier", 0.7))
	var sec_duration: int = int(ability.get("duration", 3))
	for t in sec_targets:
		if randf() >= sec_chance:
			continue
		if _SECONDARY_STAT_BUFF_MAP.has(sec_effect):
			var b: Array = _SECONDARY_STAT_BUFF_MAP[sec_effect]
			t.add_buff(b[1], b[0], sec_modifier, sec_duration)
		elif _SECONDARY_STAT_DEBUFF_MAP.has(sec_effect):
			var d: Array = _SECONDARY_STAT_DEBUFF_MAP[sec_effect]
			t.add_debuff(d[1], d[0], sec_modifier, sec_duration)
		else:
			t.add_status(sec_effect, sec_duration)
		_log("%s: secondary %s on %s (%s)" % [caster.combatant_name, sec_effect, t.combatant_name, ability_id])



## The MP a damaging magic ability siphons back to its caster, mirroring BattleManager:5085.
##
## ⛔ Two POOLED monsters advertise an MP siphon and got nothing in the grind: data_wraith's data_drain
## (20) and the_absence's memory_drain (15, all_enemies). Live refills the caster per damaging hit, so
## they keep casting; here they ran dry and stopped, and the grind's version of those fights was
## weaker than the game's — which is what the safety limits are calibrated against.
##
## Magic arm ONLY, because live reads drain_mp only in _execute_magic_ability and both owners are
## type=magic. Adding it elsewhere would make the grind harsher than the game it simulates.
func _siphon_mp(caster, ability: Dictionary, damage_dealt: int, ability_id: String) -> void:
	var amount: int = int(ability.get("drain_mp", 0))
	if amount <= 0 or damage_dealt <= 0 or caster == null or not caster.is_alive:
		return
	var restored: int = caster.restore_mp(amount)
	if restored > 0:
		_log("%s siphons %d MP with %s" % [caster.combatant_name, restored, ability_id])



## The self-damage a magic ability costs its caster, mirroring BattleManager:5171-5174.
##
## ⛔ The FIRST parity gap in this file that made the grind HARDER than the game. stack_overflow is
## 3.0x to all_enemies with a 20% recoil, and recursive_loop (POOLED) casts it — so in the grind that
## monster paid nothing for its biggest attack and survived fights the real game kills it in. Live's
## own comment records the same field being unread on ITS side once: "stack_overflow dealt 3.0x to all
## enemies for free, defeating the catastrophic-damage / 20%-recoil tradeoff design."
##
## After the loop and proportional to the WHOLE volley, not per target — an all_enemies cast pays once
## on the total. Skipped when the caster died to something else this cast, as live skips it.
func _recoil_to(caster, ability: Dictionary, total_dealt: int, ability_id: String) -> void:
	var pct: float = float(ability.get("damage_to_self_pct", 0.0))
	if pct <= 0.0 or total_dealt <= 0 or caster == null or not caster.is_alive:
		return
	var recoil: int = max(1, int(round(total_dealt * pct)))
	caster.take_damage(recoil, true)
	_log("%s takes %d recoil from %s" % [caster.combatant_name, recoil, ability_id])



## Reads and CLEARS a stored next-attack multiplier, returning 1.0 when there is none.
##
## ⛔ Live SETS this in _execute_support_ability (:6326) and CONSUMES it on BOTH the basic-attack path
## (:4374) and the magic path (:4969) — two consumers, one producer. The grind had none of the three,
## so burrow was a wasted turn: ironback_beetle (POOLED) telegraphed and then hit for the same damage.
##
## One-shot BY CONSTRUCTION — the clear lives here rather than at each call site, so a third consumer
## cannot forget it and leave a permanent bonus running.
func _take_charged_multiplier(combatant) -> float:
	if combatant == null or not combatant.has_method("get_meta"):
		return 1.0
	var stored: float = float(combatant.get_meta("_next_attack_multiplier", 0.0))
	if stored <= 0.0:
		return 1.0
	combatant.set_meta("_next_attack_multiplier", 0.0)
	return stored


func _resolve_attack_with_power(attacker, target, base_damage: int) -> int:
	if not target or not target.is_alive:
		return 0
	var def_val = float(target.get_buffed_stat("defense", target.defense))
	var dmg = float(base_damage)
	# Same divisor guard as _resolve_attack — see comment there.
	var denom = maxf(1.0, dmg + def_val)
	var actual = int((dmg * dmg) / denom)
	actual = max(1, actual)
	if target.is_defending:
		actual = actual / 2
	target.take_damage(actual)
	return actual


func _resolve_item(user, item_id: String, target) -> void:
	if not user.has_item(item_id):
		return
	user.remove_item(item_id)

	## Tick 394: route through ItemSystem.use_item so autogrind item
	## use matches live battle exactly. Pre-fix hardcoded handlers
	## for potion (50), hi_potion (200), ether (30), hi_ether (100)
	## and a unconditional heal(50) default. The default silently
	## mishandled every other item:
	##   - mega_potion silently healed 50 instead of 100
	##   - phoenix_down silently healed 50 instead of reviving
	##   - holy_water / bomb_fragment / etc silently healed 50
	##     instead of damaging an enemy
	##   - power_drink / speed_tonic silently healed 50 instead of
	##     applying their buff
	## All silently corrupted autogrind reward / tier calculations.
	if target == null or not target.is_alive:
		return
	var its = _get_autoload("ItemSystem")
	if its != null and its.has_method("use_item"):
		var typed_targets: Array[Combatant] = [target]
		its.use_item(user, item_id, typed_targets)
		_log("%s uses %s on %s" % [user.combatant_name, item_id, target.combatant_name])
		return
	# Fallback: ItemSystem unavailable. Original hardcoded list.
	match item_id:
		"potion":
			target.heal(50)
		"hi_potion":
			target.heal(200)
		"ether":
			target.restore_mp(30)
		"hi_ether":
			target.restore_mp(100)
		_:
			target.heal(50)
	_log("%s uses %s on %s (fallback path — ItemSystem missing)" % [user.combatant_name, item_id, target.combatant_name])


func _all_dead(party: Array) -> bool:
	for combatant in party:
		if combatant.is_alive:
			return false
	return true


func _build_results(victory: bool, termination_reason: String = "") -> Dictionary:
	var exp = 0
	var gold = 0
	# authored rewards, same as live battles — stat-derived formulas broke the full-parity ruling both directions
	var mdb: Dictionary = {}
	if EncounterSystem and not EncounterSystem.monster_database.is_empty():
		mdb = EncounterSystem.monster_database
	if victory:
		# Cadence #23: reward_multiplier parity with BM._get_battle_reward_multiplier (line 968) — max across the enemy party's monster_data.reward_multiplier. Pre-fix rare-encounter monsters gave bonus rewards in live but flat rate in headless, a hidden yield tax on ludicrous-tier grinders (violates struktured's 2026-07-01 full-parity ruling: "automation isn't cheating — it's enlightenment"; ludicrous/headless MUST receive the same yields as live). Read from mdb (authored source) to match the existing exp_reward/gold_reward lookup pattern in this same loop.
		var reward_multiplier: float = 1.0
		for enemy in _enemy_party:
			var mt_key: String = str(enemy.get_meta("monster_type", "")) if enemy.has_method("get_meta") and enemy.has_meta("monster_type") else ""
			var mrow: Dictionary = mdb.get(mt_key, {})
			var em: float = float(mrow.get("reward_multiplier", 1.0))
			if em > reward_multiplier:
				reward_multiplier = em
		for enemy in _enemy_party:
			var mt_key: String = str(enemy.get_meta("monster_type", "")) if enemy.has_method("get_meta") and enemy.has_meta("monster_type") else ""
			var mrow: Dictionary = mdb.get(mt_key, {})
			exp += int(float(mrow.get("exp_reward", 25)) * reward_multiplier)
			gold += int(float(mrow.get("gold_reward", int(enemy.max_hp * 0.3 + enemy.defense))) * reward_multiplier)
			## Tick 146: mark defeated. mark_seen happened at the top
			## of resolve_battle (tick 145); this is the kill credit.
			# Tick 260: forward location through the defeat call too.
			if not is_instance_valid(enemy):
				continue
			if enemy.has_method("get_meta") and enemy.has_meta("monster_type"):
				var mtype: String = str(enemy.get_meta("monster_type", ""))
				if mtype != "":
					var defeat_loc: String = ""
					if MapSystem and "current_map_id" in MapSystem:
						defeat_loc = str(MapSystem.current_map_id)
					BestiarySystem.mark_defeated(mtype, defeat_loc)
		# Tick 341: parallel to tick 340 — apply game_constants
		# ["exp_multiplier"] and ["gold_multiplier"] so Scriptweaver /
		# RebalanceDaemon nudges affect the headless autogrind path too.
		# Pre-fix this returned raw enemy-stat sums; AutogrindSystem.on_
		# battle_victory consumed exp directly via gain_job_exp without
		# the multiplier, so a knob set to 2.0 had ZERO effect on
		# headless autogrind. Same defensive clampf([0.1, 10.0]) band
		# as BattleManager line ~431 and the live-autogrind fix in
		# GameLoop._on_autogrind_battle_ended.
		var gs: Object = null
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			gs = tree.root.get_node_or_null("GameState")
		if gs != null and "game_constants" in gs:
			var exp_mult: float = clampf(
				float(gs.game_constants.get("exp_multiplier", 1.0)),
				0.1, 10.0)
			var gold_mult: float = clampf(
				float(gs.game_constants.get("gold_multiplier", 1.0)),
				0.1, 10.0)
			exp = int(exp * exp_mult)
			gold = int(gold * gold_mult)

	# Drop parity with BattleManager (~line 596): pre-fix ludicrous mode gave EXP+gold
	# but ZERO item drops — rare_item_found never fired and inventory_items interrupts
	# were dead in headless. Same chance * drop_rate_mult * reward_multiplier math.
	var drops: Dictionary = {"item_drops": {}, "rare_drops": []}
	if victory:
		var enemy_types: Array = []
		for enemy in _enemy_party:
			if is_instance_valid(enemy) and enemy.has_method("get_meta") and enemy.has_meta("monster_type"):
				var mt: String = str(enemy.get_meta("monster_type", ""))
				if mt != "":
					enemy_types.append(mt)
		var monsters_data: Dictionary = {}
		var drop_rate_mult: float = 1.0
		var tree2: SceneTree = Engine.get_main_loop() as SceneTree
		if tree2 != null and tree2.root != null:
			var enc: Node = tree2.root.get_node_or_null("EncounterSystem")
			if enc != null and "monster_database" in enc:
				monsters_data = enc.monster_database
			var gs2: Node = tree2.root.get_node_or_null("GameState")
			if gs2 != null and "game_constants" in gs2:
				drop_rate_mult = clampf(
					float(gs2.game_constants.get("drop_rate_multiplier", 1.0)),
					0.1, 10.0)
		drops = _roll_drop_tables(enemy_types, monsters_data, drop_rate_mult)

	return {
		"victory": victory,
		"rounds": _current_round,
		"exp_gained": exp,
		"gold_gained": gold,
		"item_drops": drops["item_drops"],
		"rare_drops": drops["rare_drops"],
		"log": _battle_log.duplicate(),
		"player_party": _player_party,
		"enemy_party": _enemy_party,
		"termination_reason": termination_reason,  # cadence #19: "" = normal (victory or fair defeat), "stalemate" = MAX_ROUNDS exhausted
	}


## Pure drop-roll over monster drop_tables. rand_func injectable for deterministic tests.
## Returns {"item_drops": {item_id: qty}, "rare_drops": [{item, chance}]} — rare = base chance < 0.10.
static func _roll_drop_tables(enemy_types: Array, monsters_data: Dictionary, drop_rate_mult: float, rand_func: Callable = Callable()) -> Dictionary:
	var item_drops: Dictionary = {}
	var rare_drops: Array = []
	for mt in enemy_types:
		if not monsters_data.has(mt):
			continue
		var record: Dictionary = monsters_data[mt]
		var reward_mult: float = float(record.get("reward_multiplier", 1.0))
		for drop in record.get("drop_table", []):
			var chance: float = float(drop.get("chance", 0.0))
			var roll: float = rand_func.call() if rand_func.is_valid() else randf()
			if roll < chance * drop_rate_mult * reward_mult:
				var item_id: String = str(drop.get("item", ""))
				if item_id == "":
					continue
				item_drops[item_id] = int(item_drops.get(item_id, 0)) + 1
				if chance < 0.10:
					rare_drops.append({"item": item_id, "chance": chance})
	return {"item_drops": item_drops, "rare_drops": rare_drops}


func _log(text: String) -> void:
	_battle_log.append(text)
