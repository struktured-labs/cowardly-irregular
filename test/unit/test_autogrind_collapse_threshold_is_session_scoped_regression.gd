extends GutTest

## corruption_threshold is the collapse line the Summary prints as the "/ Y" in "Corruption: X / Y",
## and every collapse lowers it by 0.5 (floor 2.0) so the NEXT collapse arrives sooner. It was the one
## member of that cluster in NEITHER start_autogrind's reset block NOR the snapshot, which is two
## player-visible faults of opposite sign:
##
##   LEAKS   grind 1 collapses twice -> 4.0. Grind 2 resets corruption, collapse_count, max_efficiency
##           and the debuff counter, but starts at 4.0. Its Summary reads "Collapses: 0" beside a
##           line the player is 20% closer to, and the readout attributes it to nothing. It compounds:
##           six collapses in one launch floor it at 2.0 for every grind after.
##   REVERTS pause a collapsed grind, quit, Continue. collapse_count restores as 2; the threshold does
##           not, so the resumed session reads "Collapses: 2" beside the untouched 5.0. The escalation
##           the player earned is handed back.
##
## ⛔ SESSION-SCOPED IS THE READING, not a balance change, because there is no consistent behaviour to
## preserve: the value is in no save file, so it already resets at every relaunch, and every sibling in
## _trigger_system_collapse / apply_post_collapse_penalty is per-session. A stake that evaporates when
## you close the game is an unplumbed variable. A PERSISTED difficulty ratchet is a coherent design and
## a different one — it needs a SaveSystem key and a New Game reset, and it is struktured's to call.
##
## ⛔ WHY THE SIBLING RATCHET MISSED IT. test_autogrind_session_scope_symmetry_regression compares a
## field's membership BETWEEN reset/snapshot/restore, so a field in NONE of the three is never
## iterated — its own header names that blind spot, found when max_efficiency and
## post_collapse_debuff_battles sat in zero sets. This was the third. The census arms below start from
## what the collapse FUNCTIONS assign, which is why they can see a field that is in no set at all.
##
## 🔑 The tell was in this suite, not in src/: test_autogrind_long_run_escalation and
## test_autogrind_session_grade_is_reachable both hand-write corruption_threshold = 5.0 in before_each,
## beside max_efficiency and collapse_count which start_autogrind DOES reset. Two fixtures were already
## compensating for the gap.

const SystemScript = preload("res://src/autogrind/AutogrindSystem.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/AutogrindSystem.gd"

## The three functions that own the collapse. Every member field they write is a collapse-cluster
## field, and the arms below derive that set FROM THEM rather than listing it — a hand list is what
## let this one field sit outside the .347 sweep that fixed the other two.
const COLLAPSE_FUNCS: Array[String] = [
	"_trigger_system_collapse", "apply_post_collapse_penalty", "tick_post_collapse_debuff",
]

var _sys
var _fresh


func before_each() -> void:
	_sys = SystemScript.new()
	add_child_autofree(_sys)
	_sys._test_disable_persistence = true
	## Never started, never collapsed: the shipped defaults, read rather than typed. A literal here
	## would agree with a wrong default forever.
	_fresh = SystemScript.new()
	add_child_autofree(_fresh)
	_fresh._test_disable_persistence = true


func _party() -> Array[Combatant]:
	var m := Combatant.new()
	m.initialize({"name": "Grinder", "max_hp": 200, "max_mp": 50,
		"attack": 12, "defense": 12, "magic": 8, "speed": 10})
	add_child_autofree(m)
	var p: Array[Combatant] = [m]
	return p


func _start() -> void:
	assert_true(_sys.start_autogrind(_party(), {"name": "Dummy", "level": 1}),
		"precondition: the grind must actually start or nothing below is measured")


## Member fields assigned inside the named function. Locals (`var x :=`) are skipped: they are not
## state and would make the census claim resets that cannot exist.
func _fields_written_by(code: String, fname: String) -> Array:
	var out: Array = []
	var lines: PackedStringArray = code.split("\n")
	var inside := false
	var re := RegEx.new()
	re.compile("^\\t([A-Za-z_][A-Za-z0-9_]*)\\s*(=|\\+=|-=)[^=]")
	for line in lines:
		if line.begins_with("func "):
			inside = line.begins_with("func %s(" % fname)
			continue
		if not inside:
			continue
		var m := re.search(line)
		if m == null:
			continue
		var name: String = m.get_string(1)
		if name == "var" or name in out:
			continue
		out.append(name)
	return out


func _collapse_fields() -> Array:
	var code: String = GdSource.code_of(SRC)
	var all: Array = []
	for fname in COLLAPSE_FUNCS:
		for f in _fields_written_by(code, fname):
			if not all.has(f):
				all.append(f)
	return all


func test_a_new_session_starts_at_the_shipped_threshold() -> void:
	_start()
	_sys._trigger_system_collapse()
	_sys._trigger_system_collapse()
	var earned: float = _sys.corruption_threshold
	assert_lt(earned, float(_fresh.corruption_threshold),
		"CONTROL: two collapses must actually lower it, or this arm proves nothing")
	_sys.stop_autogrind("test")
	_start()
	assert_almost_eq(_sys.corruption_threshold, float(_fresh.corruption_threshold), 0.001,
		"a fresh grind resets corruption, collapse_count and the efficiency cap — the collapse line must reset with them, not arrive at %.1f" % earned)


## ⚠️ THIS ARM WAS GREEN BEFORE THE FIX, AND ONLY BECAUSE THE OTHER BUG WAS THERE. The restore never
## carried the key, but the restart never cleared it either, so the earned 4.0 was simply still
## sitting in the field — correct by occupancy. Fixing the leak alone would have turned this red.
func test_a_resumed_session_keeps_the_threshold_it_earned() -> void:
	_start()
	_sys._trigger_system_collapse()
	_sys._trigger_system_collapse()
	var earned: float = _sys.corruption_threshold
	## Through JSON, because that is what a snapshot is. A key that survives in memory and not on
	## disk reads as fixed in a test that skips the encode.
	var block: Dictionary = _sys.build_snapshot_system_block(120.0)
	var round_tripped = JSON.parse_string(JSON.stringify(block))
	assert_true(round_tripped is Dictionary, "CONTROL: the snapshot block must survive JSON at all")
	_sys.stop_autogrind("paused")
	_start()
	_sys.restore_system_from_snapshot(round_tripped)
	assert_eq(int(_sys.collapse_count), 2,
		"CONTROL: the resume restores collapse_count, so the Summary will say two collapses happened")
	assert_almost_eq(_sys.corruption_threshold, earned, 0.001,
		"and it must restore the line those two collapses moved — %.1f, not the untouched default" % earned)


func test_an_old_snapshot_without_the_key_keeps_the_fresh_default() -> void:
	## Backward compatibility, and the reason the restore defaults to the CURRENT value rather than a
	## literal: start_autogrind has just re-baselined, so an absent key must mean "keep that".
	_start()
	var block: Dictionary = _sys.build_snapshot_system_block(60.0)
	block.erase("corruption_threshold")
	_sys.restore_system_from_snapshot(block)
	assert_almost_eq(_sys.corruption_threshold, float(_fresh.corruption_threshold), 0.001,
		"a pre-key snapshot keeps the shipped default instead of zeroing the collapse line")


func test_the_collapse_still_lowers_it_and_still_floors_at_two() -> void:
	## The escalation is the mechanic; scoping it must not flatten it.
	_start()
	var before: float = _sys.corruption_threshold
	_sys._trigger_system_collapse()
	assert_lt(_sys.corruption_threshold, before, "each collapse brings the next one closer")
	for i in 20:
		_sys._trigger_system_collapse()
	assert_almost_eq(_sys.corruption_threshold, 2.0, 0.001, "and the floor still holds at 2.0")


func test_every_collapse_field_is_session_scoped() -> void:
	## The census that would have caught this one. Derived from the collapse functions' own
	## assignments, so a NEW field written there is covered the day it is written.
	var fields: Array = _collapse_fields()
	assert_true(fields.has("max_efficiency") and fields.has("collapse_count"),
		"CONTROL: the parser must find the two known members, or the loop below is vacuous")
	assert_gte(fields.size(), 5, "CONTROL: floor on the census size")
	var missed: Array = []
	for f in fields:
		var shipped = _fresh.get(f)
		_start()
		## Dirty it to something no default equals, then restart.
		_sys.set(f, (float(shipped) + 7.0) if shipped is float else (int(shipped) + 7))
		_sys.stop_autogrind("test")
		_start()
		if str(_sys.get(f)) != str(shipped):
			missed.append("%s=%s (shipped %s)" % [f, _sys.get(f), shipped])
		_sys.stop_autogrind("test")
	assert_eq(missed, [],
		"start_autogrind must re-baseline every field the collapse writes; these carried into the next grind: %s" % str(missed))


func test_every_collapse_field_survives_a_pause() -> void:
	## The other half, same census. A field the collapse moves and the snapshot drops is handed back
	## on resume — which is how the threshold reverted while collapse_count did not.
	var fields: Array = _collapse_fields()
	assert_true(fields.has("corruption_threshold"),
		"CONTROL: the census must include the field this file is about")
	_start()
	var block: Dictionary = _sys.build_snapshot_system_block(30.0)
	var missing: Array = []
	for f in fields:
		if not block.has(f):
			missing.append(f)
	assert_eq(missing, [],
		"a collapse-cluster field absent from the snapshot is reverted by every pause/resume: %s" % str(missing))


func test_the_shipped_default_is_not_typed_twice() -> void:
	## Both readouts print "X / Y" and both used to type their own 5.0 for a missing key. They agree
	## with a literal for exactly as long as nobody retunes the constant — which is the shape that put
	## a tenth of the authored heal in a player's potion.
	var decl: String = GdSource.code_of(SRC)
	assert_true(decl.contains("const DEFAULT_CORRUPTION_THRESHOLD"),
		"CONTROL: the constant must exist, or the arms below are vacuous")
	for path in ["res://src/ui/autogrind/AutogrindSummary.gd", "res://src/ui/autogrind/AutogrindStatsStrip.gd"]:
		var code: String = GdSource.code_of(path)
		assert_gt(code.length(), 500, "CONTROL: %s was actually read" % path)
		assert_true(code.contains("corruption_threshold"), "CONTROL: %s still reads the threshold" % path)
		assert_false(code.contains('"corruption_threshold", 5.0'),
			"%s must take the default from AutogrindSystem, not restate it" % path)
