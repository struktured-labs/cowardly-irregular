extends GutTest

## struktured 2026-10-03: "the queued up actions when you advance ABSOLUTELY must be shown somewhere ...
## cascading cards". The queue surfaced only as a count in the hint bar. Each queued action now leaves a
## card (order badge, icon, name, -> target) cascading off the live command menu; undo pops the top one.
## Driven through BattleScene's real queue handler, on a real Win98Menu.

const SCENE := preload("res://src/battle/BattleScene.gd")


func _combatant(n: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 100, "max_mp": 50, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func _rig() -> Array:
	var scene = SCENE.new()  # bare: _ready stops before starting a battle (no .tscn nodes)
	add_child_autofree(scene)
	scene.test_enemies.assign([_combatant("Goblin A"), _combatant("Goblin B")] as Array[Combatant])
	scene.party_members.assign([_combatant("Fighter"), _combatant("Cleric")] as Array[Combatant])
	var menu := Win98Menu.new()
	menu.is_root_menu = true
	scene.add_child(menu)
	menu.position = Vector2(540, 380)
	menu.size = Vector2(240, 200)
	menu.set_max_queue_size(5)
	scene.active_win98_menu = menu
	menu.queue_changed.connect(scene._on_advance_queue_changed)
	return [scene, menu]


const ENTRIES := [
	{"id": "attack_0", "data": {"target_idx": 0, "action": "attack"}, "label": "Goblin A"},
	{"id": "ability_fire_enemy_1", "data": {"ability_id": "fire", "target_idx": 1, "target_type": "enemy"}, "label": "Goblin B"},
	{"id": "item_potion_ally_1", "data": {"item_id": "potion", "target_idx": 1, "target_type": "ally"}, "label": "Cleric"},
]


func _cards(scene) -> AdvanceQueueCards:
	return scene.get_node_or_null("AdvanceQueueCards") as AdvanceQueueCards


func test_each_advance_leaves_a_card_in_order() -> void:
	var r := _rig()
	var scene = r[0]
	var menu: Win98Menu = r[1]
	for e in ENTRIES:
		menu._queue_current_action(e)
	var cards := _cards(scene)
	assert_not_null(cards, "queuing an Advance must put the queue on screen, not only in the hint bar")
	assert_eq(cards.card_count(), 3, "three advances, three cards")
	var texts := [cards.card_text(0), cards.card_text(1), cards.card_text(2)]
	assert_true(texts[0].begins_with("Attack") and texts[0].ends_with("Goblin A"), "card 1 is the first action and its target: %s" % texts[0])
	assert_true(texts[1].begins_with(AbilityIcons.name_of("fire")) and texts[1].ends_with("Goblin B"), "card 2: %s" % texts[1])
	assert_true(texts[2].ends_with("Cleric"), "card 3 names the ally it heals: %s" % texts[2])


func test_undo_pops_the_top_card() -> void:
	var r := _rig()
	var menu: Win98Menu = r[1]
	for e in ENTRIES:
		menu._queue_current_action(e)
	menu._undo_last_action()
	var cards := _cards(r[0])
	assert_not_null(cards, "the queue must be on screen before undo can pop it")
	if cards == null:
		return
	assert_eq(cards.card_count(), 2, "undo removes the newest card")
	assert_true(cards.card_text(1).ends_with("Goblin B"), "and leaves the earlier ones as they were: %s" % cards.card_text(1))


func test_an_emptied_queue_clears_the_cards() -> void:
	var r := _rig()
	var menu: Win98Menu = r[1]
	for e in ENTRIES:
		menu._queue_current_action(e)
	assert_not_null(_cards(r[0]), "CONTROL: the queue must be on screen before it can be cleared")
	if _cards(r[0]) == null:
		return
	menu._cancel_all_queued()
	assert_eq(_cards(r[0]).card_count(), 0, "a cancelled queue leaves no cards behind")


func test_the_hud_reads_the_same_queue_through_one_accessor() -> void:
	var r := _rig()
	var menu: Win98Menu = r[1]
	for e in ENTRIES:
		menu._queue_current_action(e)
	var shown: Array = r[0].queued_action_display()
	assert_eq(shown.size(), 3, "queued_action_display is what the turn-order card reads; it must match the cards")
	assert_eq(str(shown[1].get("target", "")), "Goblin B", "same target resolution as the cards")
