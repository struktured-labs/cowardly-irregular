extends GutTest

## Part 2 of the Advance queue cards (struktured 2026-10-03, "cascading cards"): while an Advance RUNS,
## the acting PC's actions show beside them; the current one is lit, each done one names who it
## ACTUALLY hit (a retarget says so) and peels away, and a step that never fired reads "held". Fed by
## the same action_executing / action_executed BattleManager emits for a menu Advance and an autobattle
## plan alike; driven here through BattleScene's two hooks on a bare scene.

const SCENE := preload("res://src/battle/BattleScene.gd")

var _scene
var _saved_pp: Array = []
var _saved_ep: Array = []
var _hero: Combatant
var _a: Combatant
var _b: Combatant


func _c(n: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 100, "max_mp": 50, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func before_each() -> void:
	_saved_pp = BattleManager.player_party.duplicate()
	_saved_ep = BattleManager.enemy_party.duplicate()
	_scene = SCENE.new()
	add_child_autofree(_scene)
	_hero = _c("Fighter")
	_a = _c("Goblin A")
	_b = _c("Goblin B")
	_scene.party_members.assign([_hero] as Array[Combatant])
	_scene.test_enemies.assign([_a, _b] as Array[Combatant])
	var s := AnimatedSprite2D.new()  # party_sprite_nodes is Array[AnimatedSprite2D]; assign() drops anything else
	s.position = Vector2(900, 300)
	_scene.add_child(s)
	_scene.party_sprite_nodes.assign([s])
	## _get_combatant_sprite resolves through BattleManager's party, as in a live battle.
	BattleManager.player_party.assign([_hero] as Array[Combatant])
	BattleManager.enemy_party.assign([_a, _b] as Array[Combatant])
	Engine.time_scale = 8.0  # no motion: the arms read state, not tweens


func after_each() -> void:
	Engine.time_scale = 1.0
	BattleManager.player_party.assign(_saved_pp.filter(func(x): return is_instance_valid(x)))
	BattleManager.enemy_party.assign(_saved_ep.filter(func(x): return is_instance_valid(x)))


func _advance() -> Dictionary:
	return {"type": "advance", "actions": [
		{"type": "attack", "target": _a},
		{"type": "ability", "ability_id": "fire", "targets": [_a]},
		{"type": "attack", "target": _b},
	]}


func _run() -> AdvanceQueueCards:
	return _scene.get_node_or_null("AdvanceRunCards") as AdvanceQueueCards


func test_an_advance_shows_its_steps_with_the_first_lit() -> void:
	_scene._track_advance_run_begin(_hero, _advance())
	var run := _run()
	assert_not_null(run, "a running Advance must be on screen")
	if run == null:
		return
	assert_eq(run.card_count(), 3, "one card per step")
	assert_true(run.is_running(), "the first step is pending")
	assert_true(run.card_text(0).begins_with("Attack") and run.card_text(0).ends_with("Goblin A"), run.card_text(0))


func test_a_step_names_who_it_actually_hit_including_a_retarget() -> void:
	var adv := _advance()
	_scene._track_advance_run_begin(_hero, adv)
	var run := _run()
	if run == null:
		fail_test("no run cards")
		return
	_scene._track_advance_run_step(_hero, adv["actions"][0], [_a])
	_scene._track_advance_run_step(_hero, adv["actions"][1], [_b])
	assert_string_contains(run.card_text(0), "Goblin A", "step 1 hit who it planned")
	assert_string_contains(run.card_text(1), "Goblin B (retarget)", "step 2 planned Goblin A and hit Goblin B, so the card says so")


func test_a_run_cut_short_marks_what_never_fired_held() -> void:
	var adv := _advance()
	_scene._track_advance_run_begin(_hero, adv)
	var run := _run()
	if run == null:
		fail_test("no run cards")
		return
	_scene._track_advance_run_step(_hero, adv["actions"][0], [_a])
	var texts_before_end: Array = [run.card_text(1), run.card_text(2)]
	_scene._track_advance_run_begin(_a, {"type": "attack", "target": _hero})  # the next actor starts
	assert_false(run.is_running(), "another actor starting ends the run")
	assert_eq(texts_before_end.size(), 2, "CONTROL")


func test_held_text_lands_on_the_unfired_steps() -> void:
	var cards := AdvanceQueueCards.new()
	add_child_autofree(cards)
	cards.run_begin(_advance()["actions"], Rect2(Vector2(900, 200), Vector2(80, 120)), true)
	cards.run_step([_a], true)
	## Animated, so the cards linger long enough to read what run_end wrote on them.
	var unfired: Array = [cards._cards[1], cards._cards[2]]
	cards.run_end(true)
	for c in unfired:
		var l: Label = c.find_child("Text", true, false)
		assert_string_contains(l.text, "held", "a step that never fired must say so: '%s'" % l.text)
	assert_false(cards.is_running(), "ended")


func test_an_enemy_advance_shows_nothing() -> void:
	_scene._track_advance_run_begin(_a, {"type": "advance", "actions": [{"type": "attack", "target": _hero}]})
	var run := _run()
	assert_true(run == null or not run.is_running(), "the cards are the party's plan; an enemy's Advance has none")


func test_the_battle_signals_feed_the_run() -> void:
	## The arms above drive the hooks; this pins that the live handlers call them.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	for pair in [["func _on_action_executing(", "_track_advance_run_begin(combatant, action)"],
			["func _on_action_executed(", "_track_advance_run_step(combatant, action, targets)"],
			["func _on_battle_ended(", "_end_advance_run()"]]:
		var at := src.find(pair[0])
		assert_gt(at, -1, "%s must exist" % pair[0])
		var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
		assert_true(body.contains(pair[1]), "%s must call %s" % [pair[0], pair[1]])


func test_a_held_step_is_marked_held_and_the_next_step_lands_on_its_own_card() -> void:
	## .557: a heal/Raise nobody needs is HELD at execution and emits no action_executed. Counting events
	## would have pinned step 3's target on step 2's card and called step 3 "held".
	var adv := _advance()
	var cards := AdvanceQueueCards.new()
	add_child_autofree(cards)
	cards.run_begin(adv["actions"], Rect2(Vector2(900, 200), Vector2(80, 120)), true)
	var c1: Control = cards._cards[1]
	var c2: Control = cards._cards[2]
	cards.run_step([_a], true, adv["actions"][0])
	cards.run_step([_b], true, adv["actions"][2])  # step 2 (index 1) was held: no event
	var t1: String = (c1.find_child("Text", true, false) as Label).text
	var t2: String = (c2.find_child("Text", true, false) as Label).text
	assert_string_contains(t1, "held", "the skipped step must read held: '%s'" % t1)
	assert_string_contains(t2, "Goblin B", "step 3 names its own target: '%s'" % t2)
	assert_false(t2.contains("held"), "and is not the one called held")
