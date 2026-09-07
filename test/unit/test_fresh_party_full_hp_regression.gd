extends GutTest

## Regression (web-smoke stage-4 shot, 2026-07-11): a FRESH New Game showed
## Fighter at 132/181 HP, 11 seconds in, zero battles. initialize() sets
## current=max, then hp_boost passive + power_ring/armor raise max_hp —
## nothing topped current back up, so the flagship character spawned
## visibly damaged in every new game. Both party-creation paths must end
## with a full-restore sweep.

const GL_PATH := "res://src/GameLoop.gd"


func _fn_body(src: String, fn: String) -> String:
	var start := src.find("func %s(" % fn)
	assert_gt(start, -1, "%s must exist" % fn)
	return src.substr(start, src.find("\nfunc ", start + 1) - start)


func test_both_creation_paths_end_at_full() -> void:
	var src := FileAccess.get_file_as_string(GL_PATH)
	for fn in ["_create_party", "_create_party_from_customizations"]:
		var body := _fn_body(src, fn)
		assert_true("m.current_hp = m.max_hp" in body,
			"%s must top every member to full HP after passives/equipment raise max" % fn)
		assert_true("m.current_mp = m.max_mp" in body,
			"%s must top every member to full MP too" % fn)


func test_full_restore_comes_after_the_last_member() -> void:
	# The sweep must run AFTER all appends — a mid-function restore would
	# miss members built later.
	var src := FileAccess.get_file_as_string(GL_PATH)
	var body := _fn_body(src, "_create_party")
	assert_gt(body.find("m.current_hp = m.max_hp"), body.rfind("party.append("),
		"restore sweep must follow the final party.append")


func test_hp_boost_equip_shape_reproduces_the_gap() -> void:
	# Behavioral proof of the mechanism: raising max after init leaves
	# current behind unless swept.
	var c := Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "gap_proof", "max_hp": 132, "max_mp": 30,
		"attack": 10, "defense": 10, "magic": 5, "speed": 10})
	assert_eq(c.current_hp, 132, "init sets current=max")
	c.max_hp = 181
	assert_eq(c.current_hp, 132, "raising max leaves current behind — the bug shape")
	c.current_hp = c.max_hp
	assert_eq(c.current_hp, 181, "the sweep closes it")
