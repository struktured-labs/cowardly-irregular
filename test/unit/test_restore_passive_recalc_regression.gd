extends GutTest

## Live-log find 2026-07-04: _restore_party_from_save_data re-equipped
## each passive via PassiveSystem.equip_passive — but Combatant.from_dict
## already populated equipped_passives (deduped/capped, tick 160), so
## every equip tripped the idempotency guard and logged a false "passive
## skipped" per PC per load. Worse: a restored PC with passives but NO
## equipment never triggered a recalc (equipment equips are what call
## recalculate_stats), so its passive stat bonuses silently vanished on
## load. Fix: validate ids + one recalc that applies mods from the array.


func test_recalc_applies_passive_mod_from_populated_array() -> void:
	# Mimic the from_dict half: passive already in the array, no equip call.
	var c := Combatant.new()
	add_child_autofree(c)  # recalc's PassiveSystem lookup is an absolute path — needs a tree (real restore add_child's first)
	c.combatant_name = "Restored"
	c.base_max_hp = 100
	c.max_hp = 100
	c.equipped_passives = ["hp_boost"] as Array[String]  # +30% max HP
	c.recalculate_stats()
	assert_eq(c.max_hp, 130,
		"recalculate_stats must apply hp_boost from the restored array (130 = 100 * 1.3) — this is what the dead equip loop was supposed to achieve")


func test_restore_loop_no_longer_calls_equip_passive() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn: int = src.find("func _restore_party_from_save_data")
	assert_gt(fn, -1)
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_false(body.contains("PassiveSystem.equip_passive"),
		"restore must NOT re-equip (from_dict already filled the array; equip_passive always failed idempotency)")
	assert_true(body.contains("c.recalculate_stats()"),
		"restore must recalc so passive mods attach even for a PC with no equipment")


func test_restore_drops_dead_passive_ids() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn: int = src.find("func _restore_party_from_save_data")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_true(body.contains("PassiveSystem.get_passive(pid).is_empty()"),
		"restore must drop passives removed from json (the genuine failure the old loop cared about)")
