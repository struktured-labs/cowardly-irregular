extends GutTest

## A group attack leaves every participant `exposed` + `cannot_defer` for 2 turns — taking 1.5x
## damage with their defensive option gone. The L/Q shoulder explains that: `player_defer` emits
## "X cannot defer while exposed!" to the battle log. The MENU said nothing — the row carried
## `disabled: has_status("cannot_defer")`, and a disabled row is SKIPPED BY THE CURSOR
## (Win98Menu:2087), so the player could not even land on the one row that would explain it.
##
## That is the exact asymmetry `reject_reason` was added for: Win98Menu:2083 records the previous
## instance as `disabled: not can_afford`, "but nothing told the player why nothing happened".
## A reject_reason row stays landable, plays menu_error and writes its reason to the hint bar.
##
## Same shape as the silenced-caster fix: the engine knew, one surface said so, the other did not.

const MenuClass = preload("res://src/battle/BattleCommandMenu.gd")
const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")
const SCENE_PATH := "res://src/battle/BattleScene.gd"

var _saved_player: Array = []
var _saved_enemy: Array = []


func before_each() -> void:
	_saved_player = BattleManager.player_party.duplicate()
	_saved_enemy = BattleManager.enemy_party.duplicate()


func after_each() -> void:
	var live_p: Array[Combatant] = []
	for p in _saved_player:
		if is_instance_valid(p):
			live_p.append(p)
	var live_e: Array[Combatant] = []
	for e in _saved_enemy:
		if is_instance_valid(e):
			live_e.append(e)
	BattleManager.player_party.assign(live_p)
	BattleManager.enemy_party.assign(live_e)


func _pc(who: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = who
	c.max_hp = 200
	c.max_mp = 30
	c.current_hp = 200
	c.current_mp = 30
	c.is_alive = true
	c.job = JobSystem.get_job("fighter")
	return c


func _battle_rows(party: Array) -> Array:
	var scene: Node = load(SCENE_PATH).new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var enemy := Combatant.new()
	add_child_autofree(enemy)
	enemy.combatant_name = "Rat"
	enemy.max_hp = 10
	enemy.current_hp = 10
	enemy.is_alive = true
	scene.test_enemies.assign([enemy])
	var typed: Array[Combatant] = []
	for m in party:
		typed.append(m)
	scene.party_members.assign(typed)
	BattleManager.player_party.assign(typed)
	var menu = MenuClass.new(scene)
	return menu.build_command_menu_items_with_targets(party[0])


func _row(rows: Array, id: String) -> Dictionary:
	for r in rows:
		if r is Dictionary and str(r.get("id", "")) == id:
			return r
	return {}


## FLOOR: the symbols these arms reach, named so a rename reds with the name rather than aborting an
## arm mid-frame and scoring as a pass.
func test_the_subjects_this_file_drives_exist() -> void:
	var c := _pc("Probe")
	assert_true(c.has_method("has_status"), "FLOOR: the lock is a status read")
	assert_true(c.has_method("add_status"), "FLOOR: the arms below apply cannot_defer")
	var m = Win98MenuClass.new()
	add_child_autofree(m)
	assert_true(m.has_method("_row_unavailable"),
		"FLOOR: _row_unavailable is the predicate that decides a row refuses")
	assert_true(m.has_method("_reject_selection"),
		"FLOOR: _reject_selection is what puts the reason in front of the player")
	assert_true(m.has_method("_on_item_pressed"), "FLOOR: confirm enters through _on_item_pressed")


## CONTROL — an unexposed combatant's Defer row must be plainly usable. Without this arm, a row that
## refused unconditionally would satisfy every assertion below.
func test_an_unexposed_defer_row_is_plainly_usable() -> void:
	var pc := _pc("Bram")
	var rows: Array = await _battle_rows([pc])
	var defer_row := _row(rows, "defer")
	assert_false(defer_row.is_empty(), "CONTROL: a Defer row must be offered at all")
	assert_eq(str(defer_row.get("reject_reason", "")), "",
		"CONTROL: an unexposed character must be able to Defer with no reason attached. Row: %s"
		% str(defer_row))
	assert_false(bool(defer_row.get("disabled", false)),
		"CONTROL: the usable Defer row must not be disabled either")


func test_an_exposed_defer_row_is_landable_rather_than_skipped() -> void:
	var pc := _pc("Bram")
	pc.add_status("cannot_defer", 2)
	var rows: Array = await _battle_rows([pc])
	var defer_row := _row(rows, "defer")
	assert_false(defer_row.is_empty(), "the Defer row must still be built while exposed")
	assert_false(bool(defer_row.get("disabled", false)),
		("a DISABLED row is skipped by the cursor (Win98Menu:2087), so the player can never reach "
		+ "the row that would explain the lock. Row: %s") % str(defer_row))
	assert_ne(str(defer_row.get("reject_reason", "")), "",
		"the locked row must carry a reason, or landing on it still explains nothing")


func test_the_reason_names_the_cause_the_shoulder_already_names() -> void:
	var pc := _pc("Bram")
	pc.add_status("cannot_defer", 2)
	var rows: Array = await _battle_rows([pc])
	var reason: String = str(_row(rows, "defer").get("reject_reason", ""))
	assert_true("exposed" in reason.to_lower(),
		("the battle log says \"cannot defer while exposed\" for the shoulder press; the menu must "
		+ "name the same cause or the two surfaces teach different things. Got: '%s'") % reason)


## THE EFFECT, not the bookkeeping: the dict field is only a means. What the player gets is the
## refusal sound and the reason in the hint bar, and no turn spent.
func test_confirming_the_locked_row_shows_the_reason_and_spends_nothing() -> void:
	var pc := _pc("Bram")
	pc.add_status("cannot_defer", 2)
	var rows: Array = await _battle_rows([pc])
	var defer_row := _row(rows, "defer")
	assert_false(defer_row.is_empty(), "fixture: the Defer row must exist for this arm to mean anything")
	var m = Win98MenuClass.new()
	add_child_autofree(m)
	m.setup("Test", [defer_row], Vector2(40, 40), "fighter")
	await get_tree().process_frame
	var picked: Array = []
	m.item_selected.connect(func(id, _data): picked.append(id))
	var hint := Label.new()
	add_child_autofree(hint)
	hint.text = "hint"
	m._hint_label_cache = hint
	m._can_accept_input = true
	m.selected_index = 0
	m._on_item_pressed(0)
	assert_eq(picked.size(), 0,
		"confirm must not queue a Defer the engine will refuse — that would spend the turn")
	assert_ne(hint.text, "hint",
		"the hint bar must change: this is the only channel that tells a menu-using player why "
		+ "their defence is gone")
	assert_true("exposed" in hint.text.to_lower(),
		"the hint must name the cause, not just refuse. Got: '%s'" % hint.text)


## And the real predicate must agree that the row refuses — restating the flag here would test my own
## spelling rather than the menu's policy.
func test_the_menus_own_predicate_calls_the_locked_row_unavailable() -> void:
	var pc := _pc("Bram")
	pc.add_status("cannot_defer", 2)
	var locked: Dictionary = _row(await _battle_rows([pc]), "defer")
	var open := _pc("Milo")
	var usable: Dictionary = _row(await _battle_rows([open]), "defer")
	var m = Win98MenuClass.new()
	add_child_autofree(m)
	assert_true(m._row_unavailable(locked),
		"the menu's own predicate must refuse the exposed row, or confirm would queue it")
	assert_false(m._row_unavailable(usable),
		"CONTROL: and it must NOT refuse the ordinary one, or Defer is unreachable for everyone")
