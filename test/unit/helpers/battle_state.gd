extends RefCounted

## Snapshot/restore for the BattleManager AUTOLOAD, for any test that drives a real battle.
##
## ⛔ WHY A HELPER AND NOT A TEARDOWN PER FILE: a hand-written teardown covers the fields its author
## thought of. Measured 2026-09-18, the two files that leaked did so in DIFFERENT fields, and both
## had a teardown:
##
##   test_party_llm_dialogue_regression      no teardown at all -> current_state, current_round,
##                                           volatility, _wd_armed, _execution_phase_count
##   test_win_condition_runtime_integration  restores current_state CORRECTLY, and still leaks
##                                           _battle_results, _party_line_cooldowns,
##                                           _party_line_last_kind
##
## The second is the argument for this file: its author DID think about the teardown, restored the
## field they were reasoning about, and missed three they were not. Same conclusion cowir-music
## reached for SoundManager with `sound_state.gd` — the helper exists because authorship is the
## thing that fails, not diligence.
##
## THE SURFACE IS DERIVED from get_property_list(), so a field added to BattleManager tomorrow is
## covered the day it lands without anyone editing this file.
##
## ⚠️ RESTORES THE *PRIOR* VALUE, never a fresh default. Restoring to a known-clean value would make
## this a BARRIER: it would silence whatever leaked before the caller ran, and the leaker would
## never be found. Restoring prior means a caller cannot mask anyone upstream.
##
## 🔑 AND THAT IS A KNOWN, DELIBERATE LIMIT: a restore-the-prior teardown is a CONDUIT, not a
## barrier — it propagates inherited dirt rather than clearing it. That is correct and it is why
## "every file restores" is not a cleanliness proof. If your ARMS need a clean engine, ESTABLISH the
## state you need in before_each as well as snapshotting it (cowir-sfx's shape); snapshotting alone
## makes you a good citizen, establishing makes you immune.


var _saved: Dictionary = {}
var _bm: Node = null


## Call from before_each (or before_all for a file that starts one battle).
func snapshot() -> void:
	_bm = Engine.get_main_loop().root.get_node_or_null("/root/BattleManager") if Engine.get_main_loop() else null
	if _bm == null:
		return
	_saved.clear()
	for prop in _bm.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = str(prop["name"])
		var v: Variant = _bm.get(n)
		if v is Array or v is Dictionary:
			v = v.duplicate(true)
		_saved[n] = v


## ⛔ POSITION IN THE TEARDOWN IS LOAD-BEARING AND NOTHING TESTS IT. A GDScript error ABORTS THE
## ENCLOSING FUNCTION — CLAUDE.md's rule, which is discussed for test BODIES (rung, vacuity) and
## applies identically to `after_each`, except the consequence is not a vacuous pass but a LEAK, and
## the file is green either way (cowir-sfx, who found their own release call below the restores it
## had to outlive).
##
## ✅ THIS HELPER IS ORDER-INDEPENDENT: it finds the autoload itself, returns if absent, and needs
## nothing to have run before it. So CALL IT FIRST and an error further down cannot skip it.
##
## ⚠️ THAT ADVICE IS WRONG FOR A TEARDOWN WHOSE OTHER LINES RE-DIRTY THE AUTOLOAD — if your
## after_each also calls end_battle(), stop_grinding() or assigns fields, the restore must run LAST
## or those lines undo it, and then it IS abort-exposed with no ordering that fixes it
## (cowir-autogrind, 39 files in that shape). The repair there is a FILE-SCOPE snapshot in
## before_all restored in after_all, as a backstop under the per-test restore: abort-proof for the
## cross-file half, which is the defect class that matters.
##
## Call from after_each / after_all. Ends a battle left running, then puts every field back.
func restore() -> void:
	if _bm == null or _saved.is_empty():
		return
	## _cleanup_battle first so signal connections on the battle's combatants are dropped rather than
	## left dangling on freed nodes — assigning the fields back does NOT disconnect anything.
	if _bm.current_state != _bm.BattleState.INACTIVE and _bm.has_method("_cleanup_battle"):
		_bm._cleanup_battle()
	for n in _saved:
		var saved_v: Variant = _saved[n]
		## ⛔ TYPED ARRAYS GO BACK THROUGH assign(), NEVER set(). player_party is Array[Combatant],
		## and assigning a plain Array to a typed property is a SCRIPT ERROR that ABORTS THE ENCLOSING
		## FUNCTION — so every field after it in this loop would silently never be restored, and the
		## surviving defaults would look like a partial teardown rather than a crash. CLAUDE.md's
		## first Common Pitfall, reached from the restore side. assign() coerces into the live array's
		## own type, so it cannot fail that way.
		if saved_v is Array:
			var live: Variant = _bm.get(str(n))
			if live is Array:
				live.assign(_valid_only(saved_v))
				continue
		_bm.set(str(n), saved_v)


## ⛔ A SNAPSHOTTED ARRAY OF COMBATANTS CAN HOLD INSTANCES THE TEST FREED, and putting those back is
## worse than the leak — every later reader of player_party gets a dangling reference. Not
## hypothetical: test_win_condition_runtime_integration's own teardown carries a comment saying `is`
## on a freed instance is a SCRIPT ERROR that ABORTS after_each, so its restores silently never ran.
## A general helper must be at least as careful as the hand-written teardown it replaces.
func _valid_only(a: Array) -> Array:
	var out: Array = []
	for e in a:
		if e is Object and not is_instance_valid(e):
			continue
		out.append(e)
	return out


## ⛔ IF YOU RUN `tools/probes/autoload_leak_probe.gd` ON BattleManager YOU WILL GET 8 LEAK LINES.
## THEY ARE TRIAGED, NOT UNEXAMINED — measured 2026-09-18 over all 2,076 test scripts, twice
## (fresh-instance and live-at-arm baselines, identical results). Recorded here so the next reader
## does not re-derive the triage, which is green the whole way through: nothing fails, no guard
## fires, and the work looks like work right up until you find this note.
##
##   a_corpse_is_not_poisoned · a_heal_popup_says_what_landed · a_multi_hit_rolls_its_status_once
##   the_doomed_actually_run_out_of_turns      _first_damage_round/_phase/_setup_turns_used
##   boss_defeat_tactics_logged_regression     _full_autobattle
##   calibrant_phase_barks                     _battle_action_log
##   smoke_bomb_escape_item_regression         _c3_nonbasic_used
##   execute_next_action_after_battle_end      the above + current_combatant (LIVE, not freed —
##                                             checked with is_instance_valid, it is not dangling)
##
## ✅ EVERY ONE OF THOSE FIELDS IS RESET BY `start_battle`, so the next battle cannot inherit them.
## They are visible to a later test that READS the field without starting a battle, which is why
## they are reported rather than churned — six files whose leak survived `start_battle` were fixed
## instead (v3.33.426). Fix one of these only if you have a reader that actually suffers.
##
## ⚠️ AND THE COUNT IS NOT A RATCHET. Nothing asserts it stays 8; a ninth would appear silently in
## the probe output and read exactly like these do. If you want it pinned, pin it — this note only
## says what the eight ARE.


## For a guard that wants to ASSERT cleanliness rather than enforce it: the fields that differ from
## a fresh instance of the same script. In-process baseline, so "default" cannot drift from the code.
## Returns ["field = value (baseline X)"], empty when clean.
static func dirty_fields(exclude: Array = []) -> Array[String]:
	var bm: Node = Engine.get_main_loop().root.get_node_or_null("/root/BattleManager")
	var out: Array[String] = []
	## ⛔ REPORTS ITS OWN FAILURE AS A FINDING, NEVER AS CLEAN. Returning `[]` when the subject cannot
	## be found is the silent direction: every caller asserts `dirty_fields(...) == []`, so an oracle
	## that lost its autoload — or its script — would read as a clean tree rather than a broken probe.
	## cowir-sfx found the same shape as a path a guard READ but nothing checked was read; here the
	## unchecked read is the baseline itself. A sentinel makes the caller's existing assert fire and
	## name the cause, with no new arm for anyone to remember to write.
	if bm == null:
		out.append("PROBE BROKEN: no /root/BattleManager autoload — this is not a clean tree")
		return out
	var script: Variant = load("res://src/battle/BattleManager.gd")
	if script == null:
		out.append("PROBE BROKEN: could not load BattleManager.gd for an in-process baseline")
		return out
	var fresh: Node = script.new()
	for prop in fresh.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = str(prop["name"])
		if n in exclude:
			continue
		var live_v: Variant = bm.get(n)
		var base_v: Variant = fresh.get(n)
		if typeof(live_v) == TYPE_OBJECT or typeof(base_v) == TYPE_OBJECT:
			if (live_v == null) != (base_v == null):
				out.append("%s: %s (baseline %s)" % [n, "obj" if live_v != null else "null", "obj" if base_v != null else "null"])
			continue
		if live_v != base_v:
			var shown: String = str(live_v)
			if shown.length() > 60:
				shown = shown.substr(0, 60) + "..."
			out.append("%s = %s (baseline %s)" % [n, shown, str(base_v)])
	fresh.free()
	return out
