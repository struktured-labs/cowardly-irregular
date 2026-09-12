extends GutTest

const GdSource = preload("res://test/unit/helpers/gd_source.gd")

## `.310` made the four autogrind safety limits settable from the console; they were per-SESSION, so a
## player who set stop-at-50%-HP got 20% back on next launch with no indication. For a speed toggle
## that is a preference; for a safety net it is the net quietly moving.
##
## They now ride `user://settings.json` through SaveSystem — the existing per-machine settings store,
## chosen over the two alternatives for reasons worth recording:
##   autogrind_presets.json  its root is an ARRAY and its loader REJECTS a non-Array root, so adding
##                           a sibling key would break every existing player's presets file
##   a new user:// file      an unprotected player-data surface. run_tests.sh's PLAYER-DATA NET
##                           covers script_exports/ only, and the preset test records that a `const`
##                           path "can't easily be redirected" — which is how a suite overwrote real
##                           player data for nine deploys
##
## ⛔ THIS FILE DELIBERATELY NEVER CALLS save_settings(). CLAUDE.md: run_tests.sh HONOURS
## XDG_DATA_HOME, it does not SET one, so a bare caller writes his REAL user://. The new logic is
## WHICH keys persist and HOW they are restored — both testable with no file I/O. The file plumbing is
## SaveSystem's existing, separately-tested machinery; borrowing it must not mean writing to it.

var _sys

## Exactly the keys a player can change from the console.
const PERSISTED := ["hp_threshold", "max_battles", "party_death", "item_depleted"]
## In interrupt_rules, and deliberately NOT persisted.
const NOT_PERSISTED := "corruption_limit"


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_sys = AutogrindSystem


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false
	_sys.set_interrupt_rules({"hp_threshold": 20.0, "max_battles": 100, "party_death": true, "item_depleted": true})


func _save_src() -> String:
	var s := FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	assert_ne(s, "", "control: SaveSystem.gd must be readable or every arm here is vacuous")
	return s


## ⛔ TWO TRAPS THIS FILE HIT ON ITS FIRST RUN, both of which I have hit before this session.
## 1. `src.find("autogrind_interrupt_rules")` lands on the SAVE site; the restore is 100 lines later,
##    so every restore assertion measured the wrong function and failed on correct code.
## 2. The ban on `corruption_limit` fired on MY OWN COMMENT explaining why it is excluded.
## So: scan a named FUNCTION's body, with comments stripped. No positional anchors, no bare find().
func _code_only(path: String, must_survive: String) -> String:
	## PATH-taking by construction, so the blank-control floor is safe. Note the ORDER changed with
	## it: the whole file is stripped BEFORE _fn_body windows it. Windowing first let a commented-out
	## "func " truncate the window early — zero such lines in SaveSystem.gd today, occupancy again.
	assert_gt(must_survive.length(), 0,
		"CONTROL: must_survive must name a real code site — an empty control asserts nothing")
	var raw: String = FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 0, "CONTROL: %s must be readable" % path)
	var stripped: String = str(GdSource.split(raw)["code"])
	assert_true(stripped.contains(must_survive),
		"CONTROL: the stripper removed load-bearing code (%s) — every arm below it is vacuous" % must_survive)
	return stripped


func _fn_body(src: String, header: String) -> String:
	var i: int = src.find(header)
	assert_gt(i, -1, "%s not found — the guard is scanning a function that no longer exists" % header)
	var j: int = src.find("\nfunc ", i + header.length())
	return src.substr(i, (j - i) if j > -1 else 4000)


## THE ROUND TRIP, without touching a file. What `save_settings` would store, fed back through the
## path `load_settings` uses. If either end drops a key the player's choice does not survive.
func test_a_stored_dict_restores_every_limit_a_player_can_set() -> void:
	_sys.set_interrupt_rules({"hp_threshold": 50.0, "max_battles": 25, "party_death": false, "item_depleted": false})
	var stored := {}
	for k in PERSISTED:
		stored[k] = _sys.interrupt_rules[k]
	gut.p("  would persist: %s" % [stored])

	## Simulate the next launch: defaults, then load_settings' restore call.
	_sys.set_interrupt_rules({"hp_threshold": 20.0, "max_battles": 100, "party_death": true, "item_depleted": true})
	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), 20.0,
		"CONTROL: the fresh-launch default must differ from the stored 50.0, or this passes vacuously")

	_sys.set_interrupt_rules(stored)
	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), 50.0, "hp_threshold did not survive the round trip")
	assert_eq(int(_sys.interrupt_rules["max_battles"]), 25, "max_battles did not survive")
	assert_false(bool(_sys.interrupt_rules["party_death"]), "party_death did not survive")
	assert_false(bool(_sys.interrupt_rules["item_depleted"]), "item_depleted did not survive")


## JSON hands ints back as floats. The same hop the resume snapshot has, so the same assertion.
func test_the_limits_survive_the_json_hop_settings_json_performs() -> void:
	_sys.set_interrupt_rules({"hp_threshold": 30.0, "max_battles": 200, "party_death": false, "item_depleted": true})
	var stored := {}
	for k in PERSISTED:
		stored[k] = _sys.interrupt_rules[k]

	var back = JSON.parse_string(JSON.stringify({"autogrind_interrupt_rules": stored}))
	var resumed: Dictionary = back["autogrind_interrupt_rules"]
	gut.p("  max_battles over the wire: %s (%s)" % [resumed["max_battles"], type_string(typeof(resumed["max_battles"]))])

	_sys.set_interrupt_rules({"hp_threshold": 20.0, "max_battles": 100})
	_sys.set_interrupt_rules(resumed)
	assert_eq(int(_sys.interrupt_rules["max_battles"]), 200, "max_battles lost across JSON")
	assert_eq(typeof(_sys.interrupt_rules["max_battles"]), TYPE_INT,
		"max_battles came back as %s — set_interrupt_rules' int() is what normalises the JSON float" % type_string(typeof(_sys.interrupt_rules["max_battles"])))
	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), 30.0, "hp_threshold lost across JSON")


## ⛔ corruption_limit must NOT be persisted. No UI sets it, so a stored copy is a value only CODE
## chooses — and every old settings.json on disk would then silently override a later rebalance.
func test_the_collapse_gate_is_not_persisted() -> void:
	var block: String = _fn_body(_code_only("res://src/save/SaveSystem.gd", "func save_settings"), "func save_settings")
	assert_true(block.contains("autogrind_interrupt_rules"),
		"save_settings does not persist the autogrind safety limits at all")
	assert_false(block.contains(NOT_PERSISTED),
		"'%s' is in the persisted set — no UI edits it, so a stored copy freezes a code-side default against every future rebalance" % NOT_PERSISTED)
	assert_true(_sys.interrupt_rules.has(NOT_PERSISTED),
		"CONTROL: '%s' must still EXIST as a rule, or this arm is excluding something absent" % NOT_PERSISTED)
	for k in PERSISTED:
		assert_true(block.contains(k), "'%s' is settable from the console but SaveSystem does not persist it" % k)


## Restore must go through the clamping setter, not a raw assign — a hand-edited settings.json is
## player-authored input, and an out-of-range stop is a net that never fires.
func test_restore_goes_through_the_clamping_setter() -> void:
	var after: String = _fn_body(_code_only("res://src/save/SaveSystem.gd", "func load_settings"), "func load_settings")
	assert_true(after.contains("set_interrupt_rules("),
		"the restore path does not call set_interrupt_rules — a raw assign skips the clamps AND drops corruption_limit")

	## And the clamps really do hold for the values a stored file could carry.
	_sys.set_interrupt_rules({"max_battles": 0})
	assert_eq(int(_sys.interrupt_rules["max_battles"]), 1,
		"a stored max_battles of 0 was accepted — battles_completed >= 0 stops the grind instantly and the START button looks broken")
	_sys.set_interrupt_rules({"hp_threshold": 999.0})
	assert_eq(float(_sys.interrupt_rules["hp_threshold"]), 100.0, "a stored hp_threshold above 100% was accepted unclamped")


## A non-Dictionary value must warn and keep defaults rather than crash the whole settings load —
## losing every setting because one hand-edited key is the wrong shape is the documented pre-fix bug
## in load_settings' own docstring.
func test_a_hand_edited_non_dictionary_does_not_take_the_settings_load_down() -> void:
	var after: String = _fn_body(_code_only("res://src/save/SaveSystem.gd", "func load_settings"), "func load_settings")
	## ⛔ NOT `contains("is Dictionary")`. MEASURED: load_settings already holds that string TWICE for
	## unrelated checks (`json.data is Dictionary`, `battle_fx_flags ... is Dictionary`), so the assert
	## was satisfied by pre-existing text and the mutation that deleted MY check scored GREEN, 6/6.
	## Pin something only this check can produce: the key name beside the type test, and its warning.
	assert_true(after.contains("stored is Dictionary"),
		"the stored value's own type is not checked — a hand-edited string or array reaches set_interrupt_rules")
	assert_true(after.contains("autogrind_interrupt_rules is %s"),
		"a wrong-shaped stored value is discarded silently; load_settings' own 3-stage loud-fail pattern says warn, and the warning must name THIS key")


## The console must persist at the moment of change. There is no "apply" step in a radial ring, so a
## limit set and then lost to a crash is indistinguishable from never persisting.
func test_the_console_saves_when_a_dial_moves() -> void:
	var body: String = _fn_body(_code_only("res://src/ui/autogrind/AutogrindUI.gd", "func _cycle_safety"), "func _cycle_safety")
	assert_true(body.contains("save_settings("),
		"_cycle_safety applies the limit but never persists it — the setting survives until the player quits")
	assert_true(body.contains("set_interrupt_rules("),
		"_cycle_safety must still apply to the live system, not only save for next launch")

	## ⛔ AND THE SAVE MUST BE GATED. Adding it ungated made test_autogrind_safety_limits_are_reachable
	## — which moves a dial — write user://settings.json on every run. run_tests.sh HONOURS
	## XDG_DATA_HOME but does not SET one, so a bare caller overwrites HIS real settings: the defect
	## class that put fixture data in struktured's live saves for nine deploys. I reintroduced it and
	## caught it only because a sandbox file reappeared after I deleted it.
	assert_true(body.contains("_test_disable_persistence"),
		"_cycle_safety saves settings WITHOUT checking _test_disable_persistence — every test that moves a dial then writes the player's real settings.json")


## The gate is only worth the flag actually reaching it. A save path that checks a flag nobody sets is
## the same as no gate, so pin that the dial guard sets it — the two files have to agree.
func test_the_dial_guard_sets_the_flag_the_save_path_checks() -> void:
	var dial := FileAccess.get_file_as_string("res://test/unit/test_autogrind_safety_limits_are_reachable_regression.gd")
	assert_ne(dial, "", "control: the dial guard must exist — it is the test the gate protects")
	assert_true(dial.contains("_test_disable_persistence = true"),
		"the guard that moves safety dials does not disable persistence, so the gate in _cycle_safety never engages")
