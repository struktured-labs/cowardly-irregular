extends GutTest

## struktured 2026-08-29: "the bard doesnt need an attack option. riff should be attack but an
## attack with high chance of status ailment."
##
## Riff was a 0.4x poke sitting NEXT TO a plain Attack row. Both changed: riff deals full attack
## damage, and a job whose free_move declares replaces_attack gets no second row.
##
## THE CONSTRAINT THIS MUST NOT BREAK — 2026-08-22, his report: "the bard can attack in auto mode
## but otherwise cant thats a bug". free_move used to REPLACE Attack, so Bard/Mage/Cleric could
## not make a basic attack from the menu while autobattle could. The menu must never do LESS than
## autobattle. Removing Bard's row is only safe BECAUSE riff now deals full damage; a 0-cost move
## dealing less would reopen it. That is why the damage assertion and the row assertion live in
## one file — they are one change, and splitting them lets half of it regress silently.

const CMD_SRC := "res://src/battle/BattleCommandMenu.gd"


func _abilities() -> Dictionary:
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


func _jobs() -> Dictionary:
	var f := FileAccess.open("res://data/jobs.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


func test_riff_hits_as_hard_as_a_basic_attack() -> void:
	# The load-bearing half. If riff ever drops below 1.0 again, Bard's menu silently becomes
	# weaker than autobattle — the exact 2026-08-22 defect, reintroduced by a balance tweak.
	var riff: Dictionary = _abilities().get("riff", {})
	assert_false(riff.is_empty(), "riff must exist")
	assert_gte(float(riff.get("damage_multiplier", 0.0)), 1.0,
		"riff is Bard's ONLY attack row now; below 1.0x the menu does less than autobattle")


func test_riff_keeps_a_high_ailment_chance() -> void:
	var riff: Dictionary = _abilities().get("riff", {})
	assert_ne(str(riff.get("effect", "")), "", "riff must still apply a status effect")
	assert_gte(float(riff.get("effect_chance", 0.0)), 0.5,
		"'high chance of status ailment' — a coin flip or worse is not high")


func test_riff_costs_nothing() -> void:
	# It is still the free move; making it the attack must not have given it a cost.
	assert_eq(int(_abilities().get("riff", {}).get("mp_cost", -1)), 0, "riff must stay 0 MP")


func test_bard_declares_that_its_free_move_replaces_the_attack_row() -> void:
	var fm: Dictionary = (_jobs().get("bard", {}) as Dictionary).get("free_move", {})
	assert_true(bool(fm.get("replaces_attack", false)), "bard's free_move must set replaces_attack")
	assert_eq(str(fm.get("ability_id", "")), "riff", "and it must be riff")


func test_no_other_job_replaces_its_attack() -> void:
	# ARM+. Without this, a flag set everywhere would satisfy the test above while stripping
	# Attack from every job in the game.
	var jobs := _jobs()
	var offenders: Array = []
	var checked := 0
	for jid in jobs:
		var fm = (jobs[jid] as Dictionary).get("free_move", {})
		if not (fm is Dictionary):
			continue
		checked += 1
		if jid != "bard" and bool((fm as Dictionary).get("replaces_attack", false)):
			offenders.append(str(jid))
	assert_gt(checked, 3, "CONTROL: inspected %d jobs with a free_move" % checked)
	assert_eq(offenders.size(), 0, "only bard may replace its Attack row; also set on: %s" % str(offenders))


func test_the_menu_actually_consults_the_flag() -> void:
	# Without this the data says one thing and the menu still builds both rows — the flag would
	# be documentation, not behaviour.
	var src := FileAccess.get_file_as_string(CMD_SRC)
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	# Match the CODE, not the word: the first plain occurrence of "replaces_attack" in this file
	# is the comment above the guard, and a prose match proves nothing about behaviour.
	var code_marker := 'fm_spec.get("replaces_attack", false)'
	assert_true(src.contains(code_marker), "the command menu must READ the flag, not just mention it")
	var i: int = src.find(code_marker)
	var window: String = src.substr(i, 260)
	assert_true(window.contains("_build_attack_item"),
		"the flag must gate the Attack row specifically, not something else")
