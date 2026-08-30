extends GutTest

## OverworldController._check_encounter had a fallback that rolled `randf() < rate` whenever
## EncounterSystem was unreachable. That path reaches NONE of the gates check_for_encounter
## enforces: encounters_enabled, repel_steps_remaining, forced_encounter_next_step, or the
## minimum-steps spacing. `encounters_enabled` has no other reader in the file, so es == null
## routed around its only enforcement entirely.
##
## SCOPE, measured 2026-08-24 and worth stating because it was reported as player-facing:
## the sole production caller is _on_player_moved, a handler for player.moved — subscribed in
## _ready and unsubscribed in _exit_tree, both single-site. An out-of-tree controller is not
## subscribed, so gameplay could not reach the fallback. It was reachable only by calling
## _check_encounter directly. Latent, not live — and now closed either way.

const ControllerScript := preload("res://src/exploration/OverworldController.gd")

var _saved: Dictionary = {}


func _es() -> Node:
	return get_tree().root.get_node_or_null("EncounterSystem")


func _gs() -> Node:
	return get_tree().root.get_node_or_null("GameState")


func before_each() -> void:
	_saved.clear()
	var es := _es()
	var gs := _gs()
	if es != null:
		_saved["enabled"] = es.encounters_enabled
		_saved["repel"] = int(es.repel_steps_remaining)
		_saved["steps"] = int(es.steps_since_last_encounter)
	if gs != null:
		_saved["mult"] = float(gs.encounter_rate_multiplier)


func after_each() -> void:
	# after_each runs even when a test body aborts; a trailing restore line does not.
	var es := _es()
	var gs := _gs()
	if es != null and _saved.has("enabled"):
		es.encounters_enabled = _saved["enabled"]
		es.repel_steps_remaining = _saved["repel"]
		es.steps_since_last_encounter = _saved["steps"]
	if gs != null and _saved.has("mult"):
		gs.encounter_rate_multiplier = _saved["mult"]


func _src() -> String:
	var s := FileAccess.get_file_as_string("res://src/exploration/OverworldController.gd")
	assert_gt(s.length(), 500, "CONTROL: read a real file")
	return s


func test_an_unreachable_encounter_system_yields_no_encounter() -> void:
	# Out of tree => es == null => the fallback. It must refuse, not roll.
	var ctrl = ControllerScript.new()
	ctrl._encounter_rate = 1.0
	var fired := 0
	for i in range(200):
		if ctrl._check_encounter():
			fired += 1
	assert_eq(fired, 0, "rate 1.0 with no EncounterSystem fired %d/200 — the unguarded roll is back" % fired)
	ctrl.free()


func test_the_guarded_path_still_produces_encounters() -> void:
	# ARM+. Without this, an unconditional `return false` would satisfy the test above and
	# encounters would be dead everywhere.
	#
	# 2026-08-29: this went RED in a deploy gate at 0/50 after passing the same tree's gate
	# minutes earlier, and it was MY defect, not a flake. _check_encounter multiplies in
	# GameState.encounter_rate_multiplier and returns false outright when that product is <= 0.
	# A sibling test sets it to 0.0 to prove the short-circuit and restores on its LAST line,
	# so any abort in its body leaks a 0 into an autoload every later test reads. This arm
	# asserted "rate 1.0" while never pinning the value that actually gates the roll.
	var es: Node = _es()
	if es == null:
		pending("EncounterSystem autoload unavailable")
		return
	var gs: Node = _gs()
	if gs == null:
		pending("GameState autoload unavailable")
		return
	var ctrl = ControllerScript.new()
	add_child_autofree(ctrl)
	ctrl._encounter_rate = 1.0
	gs.encounter_rate_multiplier = 1.0
	es.encounters_enabled = true
	es.repel_steps_remaining = 0
	# CONTROL: the early return this test cannot see from its own assert.
	assert_gt(float(gs.encounter_rate_multiplier), 0.0,
		"a zero settings multiplier short-circuits _check_encounter before any roll")
	var fired := 0
	for i in range(50):
		es.steps_since_last_encounter = 9999
		if ctrl._check_encounter():
			fired += 1
	assert_gt(fired, 0,
		"in-tree, encounters enabled, controller rate 1.0, settings multiplier %.3f — nothing fired in 50 tries" % float(gs.encounter_rate_multiplier))


func test_the_disabled_flag_is_honoured_on_the_guarded_path() -> void:
	var es: Node = _es()
	if es == null:
		pending("EncounterSystem autoload unavailable")
		return
	var ctrl = ControllerScript.new()
	add_child_autofree(ctrl)
	ctrl._encounter_rate = 1.0
	es.encounters_enabled = false
	var fired := 0
	for i in range(100):
		if ctrl._check_encounter():
			fired += 1
	assert_eq(fired, 0, "encounters_enabled=false still fired %d/100" % fired)


func test_no_unguarded_randf_remains_in_the_encounter_check() -> void:
	# The specific line that was removed, not "randf appears somewhere": the file uses randf
	# legitimately elsewhere, so pin the SHAPE that bypassed the gates.
	var src := _src()
	var idx: int = src.find("func _check_encounter")
	assert_gt(idx, -1, "_check_encounter must exist — if renamed, retarget this test")
	var end: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (end - idx) if end > -1 else src.length() - idx)
	# CODE ONLY. The first version of this searched the raw body and matched the COMMENT that
	# quotes the removed line verbatim — a source pin firing on prose about the act, not the act.
	var code_lines: Array[String] = []
	for raw in body.split("\n"):
		var stripped: String = str(raw).strip_edges()
		if stripped.begins_with("#"):
			continue
		code_lines.append(str(raw))
	var code: String = "\n".join(code_lines)
	assert_true(code.contains("return false"), "CONTROL: the fail-closed return is in the extracted CODE, so a miss below is real")
	assert_false(code.contains("return randf() <"),
		"_check_encounter returns a raw randf roll again — that path reaches none of EncounterSystem's gates")


func test_the_subscription_lifecycle_is_what_kept_this_unreachable() -> void:
	# This is the property that made a real bypass merely latent. If someone connects
	# player.moved from anywhere else — or drops the _exit_tree disconnect — an out-of-tree
	# controller becomes reachable again and the scope note above stops being true.
	var src := _src()
	assert_eq(src.count("moved.connect(_on_player_moved)"), 1, "exactly one subscription site")
	assert_eq(src.count("moved.disconnect(_on_player_moved)"), 1, "exactly one unsubscribe site")
	var ready_idx: int = src.find("func _ready")
	var exit_idx: int = src.find("func _exit_tree")
	var conn_idx: int = src.find("moved.connect(_on_player_moved)")
	var disc_idx: int = src.find("moved.disconnect(_on_player_moved)")
	assert_gt(conn_idx, ready_idx, "the subscription must live in _ready")
	assert_lt(conn_idx, exit_idx, "the subscription must live in _ready, before _exit_tree")
	assert_gt(disc_idx, exit_idx, "the unsubscribe must live in _exit_tree")
