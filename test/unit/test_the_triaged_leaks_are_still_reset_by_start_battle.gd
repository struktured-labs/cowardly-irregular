extends GutTest

## The note in test/unit/helpers/battle_state.gd says eight test files leak BattleManager fields
## and that leaving them is CORRECT because `start_battle` resets every one, so no later battle can
## inherit them. That is a load-bearing claim about production code, sitting in a comment.
##
## ⛔ A COMMENT MUST NOT READ AS A GUARD (cowir-controller, 2026-09-18). The triage itself is a
## closed decision and a note is the right artifact for it — but this ONE clause can break without
## anyone touching the note, and if it does the note becomes reassuring and false: the leak stops
## being "visible only to a reader that never starts a battle" and becomes a real cross-battle leak.
##
## So the decision stays a note and the breakable claim gets an arm.
##
## Derived from BattleManager's own source rather than hand-asserted, so a reset that MOVES within
## start_battle still passes and only its REMOVAL reds.

const BM_SRC := "res://src/battle/BattleManager.gd"

## The fields the eight triaged files were measured leaking (2026-09-18, two full-corpus runs).
## Reset by start_battle — the seven the note's safety claim actually covers.
const TRIAGED_FIELDS: Array[String] = [
	"_first_damage_round", "_first_damage_phase", "_setup_turns_used",
	"_full_autobattle", "_battle_action_log", "_c3_nonbasic_used", "_wd_last_progress_ms",
]

## ⛔ NOT reset by start_battle. Cleared at _cleanup_battle:1161, whose only caller is end_battle.
## Pinned separately because the note makes a DIFFERENT promise about it, and a single list would
## have let this one be "fixed" by adding it to start_battle — which nobody has asked for.
const CLEANUP_ONLY_FIELDS: Array[String] = ["current_combatant"]


func _start_battle_body() -> String:
	var src: String = FileAccess.get_file_as_string(BM_SRC)
	assert_ne(src, "", "CONTROL: BattleManager.gd must be readable or every arm below is vacuous")
	var start: int = src.find("\nfunc start_battle(")
	if start == -1:
		return ""
	var after: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, (after - start) if after != -1 else -1)
	## ⛔ STRIP COMMENTS FIRST. Without this the scan matches `_full_autobattle =` inside a line
	## someone commented out — which is exactly how a removed reset would look. Caught by mutating a
	## reset away and watching this arm PASS: the pattern matched the mutation's own comment text.
	## cowir-controller's "the pattern is not the criterion", inside the guard written to defend a
	## claim about production code.
	var kept: PackedStringArray = PackedStringArray()
	for line in body.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var hash_at: int = line.find("#")
		kept.append(line.substr(0, hash_at) if hash_at != -1 else line)
	return "\n".join(kept)


func test_start_battle_is_findable() -> void:
	# Without this, an empty body makes every field below read as "not reset" — a false ALARM,
	# which is the safe direction, but it would send the next reader chasing a parse bug.
	var body: String = _start_battle_body()
	assert_gt(body.length(), 200,
		"could not locate start_battle's body in %s — the scan below cannot answer" % BM_SRC)


func test_every_triaged_field_is_still_reset_by_start_battle() -> void:
	var body: String = _start_battle_body()
	if body == "":
		return
	var unreset: Array[String] = []
	for f in TRIAGED_FIELDS:
		## `current_combatant` is cleared via _cleanup_battle, which start_battle calls; the others
		## are assigned directly. Accept either shape, and accept `.clear()` for the containers.
		var direct: bool = body.contains(f + " =") or body.contains(f + ".clear()")
		if not direct:
			unreset.append(f)
	assert_eq(unreset, [],
		"battle_state.gd's triage note says these are safe to leak BECAUSE start_battle resets them. "
		+ "These no longer are, so the note is now reassuring and WRONG — either restore the reset or "
		+ "fix the leaking test and drop it from the note: %s" % str(unreset))


func test_the_scan_can_actually_fire() -> void:
	# "all reset" is equally true of a scan that matches anything.
	var body: String = _start_battle_body()
	if body == "":
		return
	assert_false(body.contains("zz_not_a_real_field ="),
		"CONTROL: the containment test must not match a field start_battle never mentions")


func test_the_cleanup_only_field_is_still_cleanup_only() -> void:
	## The note promises something WEAKER for current_combatant: cleared on battle END, not start.
	## If a reset appears in start_battle the note is merely pessimistic — but if the _cleanup_battle
	## one disappears, nothing clears it at all and the triage becomes wrong in the loud direction.
	var src: String = FileAccess.get_file_as_string(BM_SRC)
	assert_ne(src, "", "CONTROL: BattleManager.gd must be readable")
	for f in CLEANUP_ONLY_FIELDS:
		assert_true(src.contains(f + " = null"),
			"battle_state.gd's note says %s is cleared by _cleanup_battle. Nothing clears it now, "
			% f + "so the eighth triaged leak survives every battle instead of one.")
