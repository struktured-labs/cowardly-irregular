extends GutTest

## Simulate's real invariant: it REFUSES what the probe cannot honestly decide.
##
## The readout's own comment names the defect it exists to prevent — "the exact 'the UI says
## something the engine doesn't do' defect" — and it guarded that with an explicit list of
## battlefield conditions. But a list is only as good as its coverage, and three conditions were
## outside it while being answered confidently:
##
##   turn        reads BattleManager.current_round, which OUTSIDE a fight still holds the LAST
##               battle's final round. Not an unknown guessed at — another fight's leftovers
##               reported as fact, so two players with identical rules got different readouts.
##               7 of the 15 shipped templates gate on turn.
##   item_count  reads the CASTER's bag, and the probe carried none — so every
##               "hp low AND potions > 0 -> use potion" rule read as never-firing with a full
##               bag. 12 of the 15 shipped templates gate on item_count.
##   ally_dead   added 2026-09-10 and unclassified on arrival, which is how the previous two got
##               in: a condition lands, the list is not part of adding one, nothing notices.
##
## So the ratchet below is the point of this file, more than the three fixes: every condition in
## CONDITION_TYPES must be classified, in BOTH directions, so the next one cannot arrive silently.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"


func _editor() -> Node:
	var e: Node = load(EDITOR).new()
	e.character_id = "classify_probe"
	e.character_name = "Probe"
	add_child_autofree(e)
	return e


func test_every_condition_is_classified_in_both_directions() -> void:
	var e := _editor()
	var classified: Array = []
	classified.append_array(e._PROBE_DECIDABLE)
	classified.append_array(e._BATTLEFIELD_CONDITIONS)
	classified.append_array(e._ROUND_CONDITIONS)

	var registry: Array = AutobattleSystem.CONDITION_TYPES.keys()
	assert_gt(registry.size(), 0, "control: the condition registry must be non-empty")

	var unclassified: Array = []
	for t in registry:
		if not classified.has(str(t)):
			unclassified.append(str(t))
	assert_eq(unclassified.size(), 0,
		("these conditions are in CONDITION_TYPES but classified nowhere, so Simulate GUESSES at " +
		"them against a probe that cannot know: %s") % str(unclassified))

	## The other direction, which is the half that rots quietly: a classification naming a
	## condition that no longer exists suppresses nothing and hides the next real gap.
	var stale: Array = []
	for t in classified:
		if not registry.has(str(t)):
			stale.append(str(t))
	assert_eq(stale.size(), 0,
		"these are classified for Simulate but are not registered conditions any more — delete them: %s" % str(stale))


func test_a_turn_gated_rule_is_refused_rather_than_answered_from_the_last_fight() -> void:
	var e := _editor()
	var rules: Array = [
		{"enabled": true, "conditions": [{"type": "turn", "op": "==", "value": 1}],
		 "actions": [{"type": "ability", "id": "battle_hymn", "target": "all_allies"}]},
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]},
	]
	var lines: Array = e._simulate_report(rules)
	assert_gt(lines.size(), 0, "control: the readout produced lines to inspect")
	for line in lines:
		assert_true(str(line).contains("which round"),
			"a turn-gated opener must be reported as undecidable with its reason, never resolved against a leftover round counter — got: %s" % str(line))


func test_an_item_rule_can_fire_when_the_character_actually_carries_the_item() -> void:
	var e := _editor()
	var hero := Combatant.new()
	hero.initialize({"name": "Bag Hero", "max_hp": 100, "max_mp": 40,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(hero)
	hero.add_item("potion", 3)
	assert_gt(hero.get_item_count("potion"), 0,
		"precondition: the edited character must actually carry the item, or this measures the wrong thing")
	e.combatant = hero

	var rules: Array = [
		{"enabled": true,
		 "conditions": [{"type": "hp_percent", "op": "<", "value": 50},
			{"type": "item_count", "item_id": "potion", "op": ">", "value": 0}],
		 "actions": [{"type": "item", "id": "potion", "target": "self"}]},
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]},
	]
	var lines: Array = e._simulate_report(rules)
	var fired := false
	for line in lines:
		if str(line).contains("rule 1 fires"):
			fired = true
	assert_true(fired,
		"with three potions in the bag and a sampled state below the HP threshold, the potion rule must show as firing — the probe carried no inventory, so it always read as dead: %s" % str(lines))


func test_ally_dead_is_refused_like_the_other_battlefield_conditions() -> void:
	var e := _editor()
	var lines: Array = e._simulate_report([
		{"enabled": true, "conditions": [{"type": "ally_dead"}],
		 "actions": [{"type": "ability", "id": "raise", "target": "lowest_hp_ally"}]},
	])
	for line in lines:
		assert_true(str(line).contains("battlefield"),
			"ally_dead reads the live party and must be refused, not answered from whatever the parties happen to hold: %s" % str(line))
