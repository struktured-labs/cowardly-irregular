extends GutTest

## Regression: PartyStatusScreen cards expose an EXP bar so players can
## see how close each member is to leveling up without leaving the screen.
## Pins: bar rendered with correct text format, card height grown to fit,
## EXP denominator matches Combatant.gain_job_exp's `job_level * 100`
## threshold so the visual reflects the real level-up trigger.

const PARTY_STATUS_PATH := "res://src/ui/PartyStatusScreen.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _build_combatant(name_str: String, level: int, exp: int):
	var script = load(COMBATANT_PATH)
	var c = script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	c.job_level = level
	c.job_exp = exp
	c.job = {"id": "mage", "name": "Mage"}
	return c


func _stand_up_screen(party: Array) -> Node:
	var script = load(PARTY_STATUS_PATH)
	var s = script.new()
	add_child_autofree(s)
	s.party = party
	s.focused_index = 0
	s._build_ui()
	return s


func _find_exp_label(root: Node) -> Label:
	if root is Label and (root as Label).text.begins_with("EXP "):
		return root as Label
	for child in root.get_children():
		var found = _find_exp_label(child)
		if found:
			return found
	return null


func test_card_has_exp_bar_with_correct_text() -> void:
	# Level 5, 250 EXP → threshold is 500 (= 5 * 100). Display: "EXP 250/500".
	var c = _build_combatant("TestMage", 5, 250)
	var screen = _stand_up_screen([c])

	var lbl = _find_exp_label(screen)
	assert_not_null(lbl, "Card must render an EXP label/bar")
	if lbl:
		assert_eq(lbl.text, "EXP 250/500",
			"EXP label must show `cur/threshold` using job_level * 100 denominator")
	c.free()


func test_exp_bar_handles_level_one_starter() -> void:
	# New game state: level 1, 0 EXP → "EXP 0/100".
	var c = _build_combatant("FreshHero", 1, 0)
	var screen = _stand_up_screen([c])
	var lbl = _find_exp_label(screen)
	assert_not_null(lbl, "Level-1 PC must still render the EXP bar")
	if lbl:
		assert_eq(lbl.text, "EXP 0/100",
			"Level-1 EXP denominator must be 100, not 0 (divide-by-zero guard)")
	c.free()


func test_exp_bar_guards_against_zero_level() -> void:
	# Defensive: if anything ever sets level=0 on a Combatant, we should
	# still render *something* sane instead of crashing or showing
	# "EXP n/0". The implementation clamps via `lvl > 0 else 1`.
	var c = _build_combatant("ZeroLevel", 0, 42)
	var screen = _stand_up_screen([c])
	var lbl = _find_exp_label(screen)
	assert_not_null(lbl, "level=0 PC should still render an EXP bar (clamped)")
	if lbl:
		assert_eq(lbl.text, "EXP 42/100",
			"level=0 must clamp denominator to 100 instead of producing divide-by-zero")
	c.free()


func test_card_height_grew_to_fit_exp_bar() -> void:
	# Locks in the visual layout — if someone shrinks the card without
	# also moving stats/bars, the EXP bar overlaps stats and the test fails.
	var c = _build_combatant("LayoutTest", 3, 50)
	var screen = _stand_up_screen([c])
	var card = screen._cards[0] as Control
	assert_not_null(card, "screen._cards[0] must be the rendered card Control")
	if card:
		assert_eq(card.size.y, 184.0,
			"Card height must be 184 to fit HP / MP / EXP / Stats rows without overlap")
	c.free()
