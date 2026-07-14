extends GutTest

## tick 285: Combatant.add_status now refreshes duration on re-apply.
##
## Pre-fix add_status was a silent no-op when the status already
## existed:
##
##   if status not in status_effects:
##       status_effects.append(status)
##       status_durations[status] = duration
##       status_added.emit(status)
##
## Calling add_status("poison", 3) followed by add_status("poison", 5)
## left the duration at 3 — the second call did literally nothing.
## Inconsistent with add_buff and add_debuff which both refresh
## remaining_turns on re-apply (Combatant.gd:380, :401).
##
## Player-facing impact: couldn't extend a beneficial DOT like regen
## or refresh a debuff stacking on an enemy. The re-apply attempt
## "succeeded" (cast went through, MP spent, ability animation
## played) but had zero mechanical effect.


const COMBATANT_SCRIPT := "res://src/battle/Combatant.gd"


func _make_combatant() -> Combatant:
	var script: GDScript = load(COMBATANT_SCRIPT)
	var c: Combatant = script.new()
	c.combatant_name = "Test"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	add_child_autofree(c)
	return c


# ── Re-applying the same status refreshes duration ────────────────

func test_re_apply_refreshes_duration() -> void:
	var c := _make_combatant()
	c.add_status("poison", 3)
	assert_eq(c.status_durations["poison"], 3, "first apply sets duration to 3")
	c.add_status("poison", 5)
	assert_eq(c.status_durations["poison"], 5,
		"re-apply must refresh duration to the new value (was silent no-op pre-tick-285)")


# ── Re-apply with shorter duration also overwrites (matches add_buff) ─

func test_re_apply_with_shorter_duration_overwrites() -> void:
	# Matches add_buff/add_debuff behavior (line 380 / 401: overwrite,
	# not max). Caller is responsible for choosing the right semantics
	# at the ability layer.
	var c := _make_combatant()
	c.add_status("poison", 5)
	c.add_status("poison", 2)
	assert_eq(c.status_durations["poison"], 2,
		"re-apply with SHORTER duration overwrites — matches add_buff (caller chooses)")


# ── status_effects list stays single-entry ────────────────────────

func test_status_effects_list_no_duplicate_on_reapply() -> void:
	var c := _make_combatant()
	c.add_status("poison", 3)
	c.add_status("poison", 5)
	c.add_status("poison", 7)
	var count: int = 0
	for s in c.status_effects:
		if s == "poison":
			count += 1
	assert_eq(count, 1,
		"status_effects array must not duplicate the status on re-apply")


# ── status_added signal fires only on first add ──────────────────

func test_status_added_signal_fires_only_on_first_add() -> void:
	var c := _make_combatant()
	watch_signals(c)
	c.add_status("poison", 3)
	assert_signal_emit_count(c, "status_added", 1,
		"first apply fires status_added once")
	c.add_status("poison", 5)
	assert_signal_emit_count(c, "status_added", 1,
		"re-apply must NOT re-fire status_added (UI already shows the icon)")


# ── Different status types still add normally ─────────────────────

func test_different_status_types_co_exist() -> void:
	var c := _make_combatant()
	c.add_status("poison", 3)
	c.add_status("burn", 4)
	assert_eq(c.status_effects.size(), 2, "different statuses co-exist")
	assert_eq(c.status_durations["poison"], 3)
	assert_eq(c.status_durations["burn"], 4)


# ── Parity with add_buff/add_debuff refresh behavior ─────────────

func test_parity_with_add_buff_refresh() -> void:
	# Source-pin: both add_status and add_buff should refresh on
	# re-apply. If add_buff's refresh path is ever removed, this pin
	# catches the asymmetry going the OTHER direction too.
	var src: String = FileAccess.get_file_as_string(COMBATANT_SCRIPT)
	# add_status now references `status in status_effects` (refresh path).
	assert_true(src.contains("if status in status_effects:"),
		"add_status must have a refresh path for already-applied statuses")
	# add_buff still refreshes via existing["remaining_turns"] = duration.
	assert_true(src.contains("existing[\"remaining_turns\"] = duration"),
		"add_buff must still refresh remaining_turns on re-apply (parity check)")
