extends GutTest

## The composer silently rewrote the player's rules.
##
## Shipped 2026-09-10: a rule casting a costed ability with no mp_percent guard
## gets one supplied, because the threshold is arithmetic the validator already
## performs and a missing guard discarded the player's WHOLE ruleset. That fix is
## right — it took cleric compositions from 0/10 surviving to 8/10 — but it
## installed a ruleset that DIFFERS from what the player asked for and said
## nothing. The preview read "3 rule(s) composed." either way.
##
## This project's rule is that silent failures are worse than crashes; a silent
## CHANGE is the same defect with a friendlier face, and it is worse here than a
## refusal would be, because the player confirms it believing they are installing
## their own request.
##
## So the repair now reports each edit, and the confirm-time preview lists them.
## notes are deliberately NOT errors: errors mean the ruleset was refused, notes
## mean it was accepted and edited.

const OVERLAY := preload("res://src/ui/autobattle/RuleComposerOverlay.gd")

var _rc = null


func before_each() -> void:
	_rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(_rc, "CONTROL: RuleComposer autoload must exist")


func _kit(character_id: String) -> Dictionary:
	return AutobattleSystem.get_deep_check_kit(character_id)


func _unguarded_cure_rule() -> Dictionary:
	return {"conditions": [{"type": "ally_hp_percent", "op": "<", "value": 40}],
			"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}],
			"enabled": true}


# ── the repair reports what it did ────────────────────────────────────────────

func test_supplying_a_guard_produces_a_note() -> void:
	var rules: Array = [_unguarded_cure_rule()]
	var notes: Array = _rc._supply_missing_mp_guards(rules, _kit("cleric"))
	assert_eq(notes.size(), 1, "an edited rule must produce exactly one note")
	assert_true(str(notes[0]).find("cure") != -1,
		"the note must name the ability, so the player can find the rule it changed")
	assert_true(str(notes[0]).find("%") != -1,
		"and state the threshold that was added")


func test_raising_a_weak_guard_also_reports() -> void:
	var rules: Array = [_unguarded_cure_rule()]
	(rules[0]["conditions"] as Array).append({"type": "mp_percent", "op": ">=", "value": 1})
	var notes: Array = _rc._supply_missing_mp_guards(rules, _kit("cleric"))
	assert_eq(notes.size(), 1, "raising an insufficient guard is also a change to the player's rule")
	assert_true(str(notes[0]).to_lower().find("raised") != -1,
		"and must be described as a raise, not as an addition")


func test_a_guard_the_player_already_had_is_not_reported() -> void:
	## CONTROL, and the reason this can't just always emit a note: an untouched
	## rule must produce silence, or the list becomes noise the player learns to
	## skip and the real edits hide inside it.
	var rules: Array = [_unguarded_cure_rule()]
	(rules[0]["conditions"] as Array).append({"type": "mp_percent", "op": ">=", "value": 95})
	var notes: Array = _rc._supply_missing_mp_guards(rules, _kit("cleric"))
	assert_eq(notes.size(), 0, "a rule that needed no change must produce no note")


func test_an_untouched_free_rule_is_not_reported() -> void:
	var rules: Array = [{"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	assert_eq(_rc._supply_missing_mp_guards(rules, _kit("cleric")).size(), 0,
		"a rule with no MP cost is never edited, so it must never be reported")


func test_an_out_of_kit_rule_is_not_reported_as_adjusted() -> void:
	## It is deliberately NOT repaired, so claiming an adjustment would be a lie
	## about a rule that is about to be rejected.
	var rules: Array = [_unguarded_cure_rule()]
	assert_eq(_rc._supply_missing_mp_guards(rules, _kit("fighter")).size(), 0,
		"cure on a fighter is left for the validator — it must not be reported as fixed")


func test_two_edited_rules_produce_two_DISTINGUISHABLE_notes() -> void:
	## Found by running real llama3 output through this path: duplicate 'cure' rules
	## are common, and naming only the ability produced two IDENTICAL lines, so the
	## player could not tell which rule had been edited. The 1-based position is the
	## handle, and it matches the top-to-bottom order the editor displays.
	var rules: Array = [_unguarded_cure_rule(), _unguarded_cure_rule()]
	var notes: Array = _rc._supply_missing_mp_guards(rules, _kit("cleric"))
	assert_eq(notes.size(), 2, "each edited rule must be named, not summarised as one line")
	assert_ne(str(notes[0]), str(notes[1]),
		"two rules casting the same ability must still be TELLABLE APART")
	assert_true(str(notes[0]).find("Rule 1") != -1, "the first must name rule 1")
	assert_true(str(notes[1]).find("Rule 2") != -1, "and the second rule 2")


# ── the result carries them ───────────────────────────────────────────────────

func test_every_result_shape_carries_a_notes_key() -> void:
	## A reader must never have to branch on whether the key exists. The fallback
	## and empty shapes are what callers get on failure.
	for shape in [_rc._fallback_result("autobattle", "cleric"),
			_rc._empty_result("autobattle", "cleric", "test")]:
		assert_true((shape as Dictionary).has("notes"),
			"every result shape must carry 'notes'")
		assert_eq(((shape as Dictionary)["notes"] as Array).size(), 0,
			"and it must be empty when nothing was changed")


func test_notes_are_not_errors() -> void:
	## The discriminator. errors route to _show_error and abandon the composition;
	## notes accompany a ruleset that IS being installed. Conflating them would
	## either hide the edits or refuse a good ruleset.
	var fb: Dictionary = _rc._fallback_result("autobattle", "cleric")
	assert_true(fb.has("errors") and fb.has("notes"),
		"the two must be separate keys, not one list the UI has to classify")


# ── the player sees them before confirming ────────────────────────────────────

func test_the_preview_lists_every_adjustment() -> void:
	var overlay = OVERLAY.new()
	add_child_autofree(overlay)
	overlay._preview_panel = Panel.new()
	overlay.add_child(overlay._preview_panel)
	overlay._populate_preview({
		"description": "Mend the worst, then strike.",
		"rules": [_unguarded_cure_rule()],
		"notes": ["Added an MP check (at least 9%) to the 'cure' rule so it cannot fizzle."],
	})
	var label: Label = overlay._preview_panel.get_node_or_null("PreviewLabel") as Label
	assert_not_null(label, "CONTROL: the preview label must be built")
	assert_true(label.text.find("cure") != -1,
		"the adjustment must be visible BEFORE the player confirms the install")
	assert_true(label.text.find("Mend the worst") != -1,
		"CONTROL: the description must still render alongside it")
	assert_true(label.text.find("1 rule(s) composed") != -1,
		"CONTROL: and so must the rule count")


func test_the_preview_says_nothing_when_nothing_changed() -> void:
	## CONTROL: an unchanged composition must not grow a heading with no items,
	## which would train the player to ignore the section.
	var overlay = OVERLAY.new()
	add_child_autofree(overlay)
	overlay._preview_panel = Panel.new()
	overlay.add_child(overlay._preview_panel)
	overlay._populate_preview({"description": "d", "rules": [], "notes": []})
	var label: Label = overlay._preview_panel.get_node_or_null("PreviewLabel") as Label
	assert_eq(label.text.find("Adjusted"), -1,
		"with no adjustments the section must be absent, not present-and-empty")


func test_the_preview_survives_a_result_with_no_notes_key() -> void:
	## Shapes reach this from tests, saves and older call sites; a missing key must
	## render the ordinary preview rather than crash the confirm screen.
	var overlay = OVERLAY.new()
	add_child_autofree(overlay)
	overlay._preview_panel = Panel.new()
	overlay.add_child(overlay._preview_panel)
	overlay._populate_preview({"description": "d", "rules": []})
	var label: Label = overlay._preview_panel.get_node_or_null("PreviewLabel") as Label
	assert_true(label.text.find("0 rule(s) composed") != -1,
		"a result with no notes key must still render")
