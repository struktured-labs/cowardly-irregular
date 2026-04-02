extends RefCounted
class_name HeadlessBattleResolver

## HeadlessBattleResolver — Pure math battle resolution for ludicrous speed autogrind.
## No scene tree, no rendering, no timers. Resolves a full battle in <1ms.

const MAX_ROUNDS = 50
const ACTION_SPEEDS = {"attack": 5, "ability": 10, "item": 8, "defend": 0, "defer": 0}

var _player_party: Array = []
var _enemy_party: Array = []
var _current_round: int = 0
var _battle_log: Array[String] = []


func resolve_battle(player_party: Array, enemy_party: Array) -> Dictionary:
	_player_party = player_party
	_enemy_party = enemy_party
	_current_round = 0
	_battle_log.clear()

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

	for combatant in _player_party:
		if not combatant.is_alive:
			continue
		combatant.gain_ap(1)

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
		var a = _select_enemy_action(enemy)
		a["combatant"] = enemy
		a["speed"] = _speed_for(a, enemy)
		actions.append(a)

	return actions


func _speed_for(action: Dictionary, combatant) -> int:
	var base = ACTION_SPEEDS.get(action.get("type", "attack"), 5)
	return base - combatant.speed


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
	if victory:
		for enemy in _enemy_party:
			exp += int(enemy.max_hp * 0.5 + enemy.attack * 2)

	return {
		"victory": victory,
		"rounds": _current_round,
		"exp_gained": exp,
		"log": _battle_log.duplicate(),
		"player_party": _player_party,
		"enemy_party": _enemy_party,
	}


func _log(text: String) -> void:
	_battle_log.append(text)
