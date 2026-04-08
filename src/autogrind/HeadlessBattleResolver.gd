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
	var bm = Engine.get_singleton("BattleManager") if Engine.has_singleton("BattleManager") else null
	if not bm:
		bm = _get_autoload("BattleManager")
	var _bm_player_backup: Array = []
	var _bm_enemy_backup: Array = []
	if bm:
		_bm_player_backup = bm.player_party.duplicate()
		_bm_enemy_backup = bm.enemy_party.duplicate()
		bm.player_party.clear()
		bm.enemy_party.clear()
		for c in _player_party:
			bm.player_party.append(c)
		for c in _enemy_party:
			bm.enemy_party.append(c)

	while _current_round < MAX_ROUNDS:
		_current_round += 1

		_tick_round_start()

		var actions = _selection_phase()

		actions.sort_custom(func(a, b): return a.get("speed", 0) < b.get("speed", 0))

		for action in actions:
			_execute_action(action)

			if _all_dead(_enemy_party):
				if bm:
					_restore_bm(bm, _bm_player_backup, _bm_enemy_backup)
				return _build_results(true)
			if _all_dead(_player_party):
				if bm:
					_restore_bm(bm, _bm_player_backup, _bm_enemy_backup)
				return _build_results(false)

	if bm:
		_restore_bm(bm, _bm_player_backup, _bm_enemy_backup)
	return _build_results(false)


func _restore_bm(bm, player_backup: Array, enemy_backup: Array) -> void:
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
			var ap_cost = raw.size() - 1
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
			total_power += p.attack

	var scale = pow(participants.size(), 1.5)
	var alive_enemies = _enemy_party.filter(func(e): return e.is_alive)

	for enemy in alive_enemies:
		var raw_damage = int(total_power * scale / max(1.0, float(alive_enemies.size())))
		var mitigated = max(1, raw_damage - enemy.defense)
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
					total_power += (p.attack + p.get_buffed_stat("magic", p.magic)) * 0.5
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var damage = max(1, int(total_power * scale / max(1.0, float(alive_enemies.size())) - enemy.defense * 0.5))
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
				var base_dmg = int(attacker.attack * 0.7)
				if randf() < 0.3:
					base_dmg = int(base_dmg * 1.5)
				var damage = max(1, base_dmg - target.defense / 2)
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
					total_atk += p.attack
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var damage = max(1, int(total_atk * scale * 0.6 / max(1.0, float(alive_enemies.size())) - enemy.defense))
				enemy.take_damage(damage)
				_log("Iron Wall crushes %s for %d!" % [enemy.combatant_name, damage])
			_log("FORMATION: Iron Wall — DEF +50%% (3 turns) + crushing blow!")

		"shadow_strike":
			var total_atk = 0.0
			for p in participants:
				if p is Combatant and p.is_alive:
					total_atk += p.attack
			for enemy in alive_enemies:
				if not enemy.is_alive: continue
				var full_hp_bonus = 2.0 if enemy.current_hp == enemy.max_hp else 1.0
				var damage = max(1, int(total_atk * scale * full_hp_bonus / max(1.0, float(alive_enemies.size()))))
				enemy.take_damage(damage)
				_log("Shadow Strike hits %s for %d!" % [enemy.combatant_name, damage])
			_log("FORMATION: Shadow Strike — defense ignored, 2x on full HP!")

		"chaos_theory":
			var roll = randf()
			if roll < 0.4:
				var total_power = 0.0
				for p in participants:
					if p is Combatant and p.is_alive:
						total_power += (p.attack + p.get_buffed_stat("magic", p.magic))
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
						total_power += p.attack
				for enemy in alive_enemies:
					if not enemy.is_alive: continue
					var damage = max(1, int(total_power * scale * 0.8 / max(1.0, float(alive_enemies.size())) - enemy.defense))
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
		if ability.get("category", "") == "healing":
			return ability_id
	return ""


func _find_attack_ability(combatant) -> String:
	var js = _get_autoload("JobSystem")
	if not js:
		return ""
	var best_id = ""
	var best_power = 0
	for ability_id in combatant.learned_abilities:
		var ability = js.get_ability(ability_id) if js.has_method("get_ability") else {}
		var cat = ability.get("category", "")
		if cat in ["magic", "physical"]:
			var power = ability.get("power", 0)
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

	var miss_chance = max(0.02, min(0.60, 0.10 - (attacker.speed - target.speed) * 0.05))
	if randf() < miss_chance:
		_log("%s misses %s!" % [attacker.combatant_name, target.combatant_name])
		return 0

	var damage = float(attacker.get_buffed_stat("attack", attacker.attack))
	damage *= randf_range(0.85, 1.15)

	var crit_chance = min(0.50, 0.05 + attacker.speed * 0.01)
	var is_crit = randf() < crit_chance
	if is_crit:
		damage *= 1.5
		_log("Critical hit!")

	var def_val = float(target.get_buffed_stat("defense", target.defense))
	var actual = int((damage * damage) / (damage + def_val))
	actual = max(1, actual)
	if target.is_defending:
		actual = actual / 2

	target.take_damage(actual)
	return actual


func _resolve_ability(caster, ability_id: String, targets: Array) -> void:
	var js = _get_autoload("JobSystem")
	var ability: Dictionary = {}
	if js and js.has_method("get_ability"):
		ability = js.get_ability(ability_id)

	var mp_cost = ability.get("mp_cost", 5)
	if not caster.spend_mp(mp_cost):
		_log("%s has no MP for %s" % [caster.combatant_name, ability_id])
		return

	var category = ability.get("category", "magic")
	var power = ability.get("power", 1.0)
	var element = ability.get("element", "")

	match category:
		"healing":
			for target in targets:
				if target and target.is_alive:
					var heal_amount = int(caster.get_buffed_stat("magic", caster.magic) * power)
					heal_amount = max(1, heal_amount)
					var healed = target.heal(heal_amount)
					_log("%s heals %s for %d" % [caster.combatant_name, target.combatant_name, healed])

		"magic":
			for target in targets:
				if target and target.is_alive:
					var base_dmg = int(caster.get_buffed_stat("magic", caster.magic) * power)
					var elem_mod = target.calculate_elemental_modifier(element) if element != "" else 1.0
					var actual = int(base_dmg * elem_mod)
					actual = max(1, actual)
					if target.is_defending:
						actual = actual / 2
					target.take_damage(actual, true)
					_log("%s casts %s on %s for %d" % [caster.combatant_name, ability_id, target.combatant_name, actual])

		"physical":
			for target in targets:
				if target and target.is_alive:
					var base_dmg = int(caster.get_buffed_stat("attack", caster.attack) * power)
					var dmg = _resolve_attack_with_power(caster, target, base_dmg)
					_log("%s uses %s on %s for %d" % [caster.combatant_name, ability_id, target.combatant_name, dmg])

		"support":
			for target in targets:
				if target and target.is_alive:
					var stat = ability.get("stat", "attack")
					var modifier = ability.get("modifier", 1.5)
					var duration = ability.get("duration", 3)
					if modifier >= 1.0:
						target.add_buff(ability_id, stat, modifier, duration)
					else:
						target.add_debuff(ability_id, stat, modifier, duration)
					_log("%s uses %s on %s" % [caster.combatant_name, ability_id, target.combatant_name])

		_:
			var target = targets[0] if targets.size() > 0 else null
			if target and target.is_alive:
				var base_dmg = int(caster.get_buffed_stat("magic", caster.magic) * power)
				target.take_damage(max(1, base_dmg), true)
				_log("%s uses %s on %s" % [caster.combatant_name, ability_id, target.combatant_name])


func _resolve_attack_with_power(attacker, target, base_damage: int) -> int:
	if not target or not target.is_alive:
		return 0
	var def_val = float(target.get_buffed_stat("defense", target.defense))
	var dmg = float(base_damage)
	var actual = int((dmg * dmg) / (dmg + def_val))
	actual = max(1, actual)
	if target.is_defending:
		actual = actual / 2
	target.take_damage(actual)
	return actual


func _resolve_item(user, item_id: String, target) -> void:
	if not user.has_item(item_id):
		return
	user.remove_item(item_id)

	match item_id:
		"potion":
			if target and target.is_alive:
				target.heal(50)
				_log("%s uses Potion on %s" % [user.combatant_name, target.combatant_name])
		"hi_potion":
			if target and target.is_alive:
				target.heal(200)
				_log("%s uses Hi-Potion on %s" % [user.combatant_name, target.combatant_name])
		"ether":
			if target and target.is_alive:
				target.restore_mp(30)
				_log("%s uses Ether on %s" % [user.combatant_name, target.combatant_name])
		"hi_ether":
			if target and target.is_alive:
				target.restore_mp(100)
				_log("%s uses Hi-Ether on %s" % [user.combatant_name, target.combatant_name])
		_:
			if target and target.is_alive:
				target.heal(50)
				_log("%s uses %s on %s" % [user.combatant_name, item_id, target.combatant_name])


func _all_dead(party: Array) -> bool:
	for combatant in party:
		if combatant.is_alive:
			return false
	return true


func _build_results(victory: bool) -> Dictionary:
	var exp = 0
	var gold = 0
	if victory:
		for enemy in _enemy_party:
			exp += int(enemy.max_hp * 0.5 + enemy.attack * 2)
			gold += int(enemy.max_hp * 0.3 + enemy.defense)

	return {
		"victory": victory,
		"rounds": _current_round,
		"exp_gained": exp,
		"gold_gained": gold,
		"log": _battle_log.duplicate(),
		"player_party": _player_party,
		"enemy_party": _enemy_party,
	}


func _log(text: String) -> void:
	_battle_log.append(text)
