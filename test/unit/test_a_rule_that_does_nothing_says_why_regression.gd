extends GutTest

## A rule whose action ran and changed nothing (Heal Party with no potions, Restore MP with no ethers, Member Casts
## from a silenced or downed healer) printed its reason to the debug log and nowhere else. The Summary counted the rule
## as fired, so it read as working. The system now tallies each reason per session and the Summary lists them.

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for spec in [["cleric", true], ["fighter", false]]:
		var c := Combatant.new()
		c.initialize({"name": str(spec[0]).capitalize(), "max_hp": 1000, "max_mp": 60,
			"attack": 10, "defense": 10, "magic": 20, "speed": 10})
		c.job = {"id": str(spec[0])}
		if bool(spec[1]):
			c.learned_abilities.append("cure")
		add_child_autofree(c)
		_party.append(c)
	_system.grind_party = _party


func test_heal_party_with_an_empty_bag_is_tallied() -> void:
	_party[1].current_hp = 300
	_system.apply_autogrind_actions([{"type": "heal_party"}])
	_system.apply_autogrind_actions([{"type": "heal_party"}])
	assert_eq(int(_system.get_rule_action_noops().get("Heal Party: out of potions", 0)), 2,
		"a Heal Party that found no potion must be counted each time it did nothing")


func test_heal_party_with_nobody_hurt_stays_silent() -> void:
	_system.apply_autogrind_actions([{"type": "heal_party"}])
	assert_true(_system.get_rule_action_noops().is_empty(), "nobody needing healing is the normal case, not a failure")


func test_a_silenced_caster_is_tallied_with_its_reason() -> void:
	_party[1].current_hp = 300
	_party[0].add_status("silence")
	_system.apply_autogrind_actions([{"type": "member_ability", "member": "Cleric", "ability": "cure", "target": "lowest_hp_ally"}])
	var keys: Array = _system.get_rule_action_noops().keys()
	assert_eq(keys.size(), 1, "the refused cast must be tallied")
	assert_string_contains(str(keys[0]) if keys.size() > 0 else "", "silenced", "with the reason the player can act on")


func test_restore_mp_with_no_ethers_is_tallied() -> void:
	_party[0].current_mp = 0
	_system.apply_autogrind_actions([{"type": "restore_mp"}])
	assert_eq(int(_system.get_rule_action_noops().get("Restore MP: out of ethers", 0)), 1, "an empty-bag Restore MP must be tallied")


func test_a_working_heal_is_not_tallied() -> void:
	_party[1].current_hp = 300
	_party[1].add_item("potion", 3)
	_system.apply_autogrind_actions([{"type": "heal_party"}])
	assert_gt(_party[1].current_hp, 300, "CONTROL: the potion must actually be drunk")
	assert_true(_system.get_rule_action_noops().is_empty(), "a heal that worked must not be reported as doing nothing")


func test_the_tally_survives_a_resume_and_resets_on_a_fresh_start() -> void:
	_party[1].current_hp = 300
	_system.apply_autogrind_actions([{"type": "heal_party"}])
	var block: Dictionary = JSON.parse_string(JSON.stringify(_system.build_snapshot_system_block(10.0)))
	_system.start_autogrind(_party, {})
	assert_true(_system.get_rule_action_noops().is_empty(), "a fresh session must not inherit the last one's tally")
	_system.restore_system_from_snapshot(block)
	assert_eq(int(_system.get_rule_action_noops().get("Heal Party: out of potions", 0)), 1,
		"a resumed session must keep the tally it paused with")
	_system.stop_autogrind("test cleanup")


func test_the_summary_lists_the_worst_three_under_your_rules() -> void:
	var summary = load("res://src/ui/autogrind/AutogrindSummary.gd").new()
	add_child_autofree(summary)
	summary.setup({"rule_noops": {"Heal Party: out of potions": 12, "Restore MP: out of ethers": 1,
		"Member Casts: Cleric is silenced — cure won't come out": 5, "Member Casts: Cleric is down": 2}}, "test")
	var rows: Array = summary._rule_noop_rows()
	assert_eq(rows.size(), 3, "capped at three rows")
	assert_string_contains(str(rows[0]["label"]), "out of potions", "the most frequent reason comes first")
	assert_string_contains(str(rows[0]["value"]), "12", "with its count")
	for r in rows:
		assert_lte(str(r["label"]).strip_edges().length(), summary.RULE_NOOP_REASON_CHARS, "a reason must fit the label column")
	await wait_frames(2)
	var texts: PackedStringArray = []
	for n in summary.find_children("*", "Label", true, false):
		texts.append(n.text)
	assert_string_contains("\n".join(texts), "out of potions", "and the row must actually be drawn on the Summary")
