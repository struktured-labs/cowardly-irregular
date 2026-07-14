extends GutTest

## Bugfix 2026-07-05: group / formation attacks summed raw p.attack for their
## power, while the normal attack path and the MAGIC side of the same executors
## use get_buffed_stat. So attack buffs/debuffs (e.g. a Bard's attack-up) were
## silently dropped from All-Out Attack, Limit Break, and every formation
## special that reads attack. All attack reads in the group executors now go
## through get_buffed_stat("attack", ...), matching magic and normal attacks.


func _dummy_enemy() -> Combatant:
	var e := Combatant.new()
	autofree(e)
	e.combatant_name = "Dummy"
	e.defense = 0
	e.max_hp = 1_000_000
	e.current_hp = 1_000_000
	e.is_alive = true
	return e


func _hero(with_buff: bool) -> Combatant:
	var h := Combatant.new()
	autofree(h)
	h.combatant_name = "Hero"
	h.attack = 20
	h.current_ap = 4
	h.is_alive = true
	if with_buff:
		h.add_buff("test_atk", "attack", 2.0, 5)  # 2x attack
	return h


func _all_out_damage(with_buff: bool) -> int:
	var enemy := _dummy_enemy()
	var participants: Array = [_hero(with_buff)]
	var foes: Array[Combatant] = [enemy]
	BattleManager._execute_physical_group(participants, foes, "all_out_attack", 1)
	return 1_000_000 - enemy.current_hp


func test_all_out_attack_scales_with_attack_buff() -> void:
	var base_dmg := _all_out_damage(false)
	var buffed_dmg := _all_out_damage(true)
	assert_gt(base_dmg, 0, "sanity: the all-out attack deals damage")
	assert_gt(buffed_dmg, base_dmg,
		"a 2x attack buff must raise All-Out Attack damage — pre-fix it read raw p.attack and ignored buffs")


func test_all_group_attack_reads_are_buffed_in_source() -> void:
	# Pin that no raw p.attack / attacker.attack sums survive in the group +
	# formation executors (they must all route through get_buffed_stat).
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var start: int = src.find("func _execute_physical_group")
	var stop: int = src.find("func _execute_combo_magic")  # combo/formation live between here and later
	# formation special is after combo; extend the window to its end
	var region_end: int = src.find("func _apply_vulnerability_window")
	var region: String = src.substr(start, max(stop, region_end) - start)
	assert_false(region.contains("+= p.attack"),
		"no group/formation power sum may read raw p.attack — use get_buffed_stat")
	assert_false(region.contains("(p.attack +"),
		"formation mixed-stat sums must use get_buffed_stat for attack too")
