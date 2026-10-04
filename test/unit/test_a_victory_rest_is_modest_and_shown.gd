extends GutTest

## struktured 2026-10-03 on the post-victory rest (GameLoop restored 25% max HP AND 25% max MP to everyone,
## silently): "that feels very generous" and "it should be indicated somewhere". Decided (cowir-main's
## option 2, his to retune): 10% MP, no HP, nothing for the KO'd; each results card shows what landed.

const OverlayScript = preload("res://src/battle/VictoryOverlay.gd")


func _member(n: String, mp: int, max_mp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 500, "max_mp": max_mp, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_mp = mp
	c.current_hp = 200
	return c


func test_the_decided_amounts() -> void:
	## A deliberate retune changes these two numbers and this arm together.
	assert_almost_eq(BattleManager.POST_BATTLE_MP_RESTORE_FRACTION, 0.10, 0.0001, "MP rest is 10% of max")
	assert_almost_eq(BattleManager.POST_BATTLE_HP_RESTORE_FRACTION, 0.0, 0.0001, "no HP rest")


func test_the_rest_applies_its_fraction_and_nothing_else() -> void:
	var m := _member("Cleric", 50, 130)
	var got: Dictionary = BattleManager.apply_post_battle_restore([m])
	assert_eq(m.current_mp, 63, "130 max MP at 10% restores 13")
	assert_eq(m.current_hp, 200, "HP is not restored")
	assert_eq(int(got["Cleric"]["mp"]), 13, "the reported amount is what was applied")


func test_a_kod_member_gets_nothing() -> void:
	var m := _member("Mage", 10, 130)
	m.current_hp = 0
	m.is_alive = false
	var got: Dictionary = BattleManager.apply_post_battle_restore([m])
	assert_eq(m.current_mp, 10, "a KO'd member's MP does not move")
	assert_eq(int(got["Mage"]["mp"]), 0, "and the report says so")


func test_a_full_bar_reports_zero() -> void:
	var m := _member("Bard", 99, 99)
	var got: Dictionary = BattleManager.apply_post_battle_restore([m])
	assert_eq(int(got["Bard"]["mp"]), 0, "a full bar takes nothing, so the card must not claim anything")


func _overlay(names: Array) -> Control:
	var cr: Array = []
	for n in names:
		cr.append({"name": n, "job_name": "cleric", "is_alive": true, "exp_gained": 10, "job_exp_before": 0,
			"exp_to_next": 100, "leveled_up": false, "job_level": 2, "job_exp": 0})
	var o = OverlayScript.new()
	add_child_autofree(o)
	o.build({"char_results": cr, "total_gold": 0, "item_drops": [], "bonuses": [], "injuries": []}, null)
	return o


func _line(o: Control, member_name: String) -> Label:
	for c in o.get_children():
		if c.has_meta("member_name") and str(c.get_meta("member_name")) == member_name:
			return c.find_child("RestoreLine", true, false)
	return null


func test_each_card_shows_exactly_what_its_member_received() -> void:
	var cleric := _member("Cleric", 50, 130)
	var bard := _member("Bard", 99, 99)
	var o := _overlay(["Cleric", "Bard"])
	o.show_restores(BattleManager.apply_post_battle_restore([cleric, bard]))
	var c_line := _line(o, "Cleric")
	var b_line := _line(o, "Bard")
	assert_not_null(c_line, "CONTROL: each card carries a restore line")
	assert_true(c_line.visible and c_line.text == "+13 MP", "the Cleric's card shows the 13 MP she got: '%s'" % c_line.text)
	assert_false(b_line.visible, "a full bar got nothing, so the Bard's card says nothing")


func test_gameloop_rests_through_the_shared_amounts() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("BattleManager.apply_post_battle_restore(party)"),
		"the victory branch must rest through the one owner, so the card and the bars agree")
	assert_false(src.contains("int(member.max_hp * 0.25)"),
		"the silent 25% HP rest must be gone")
