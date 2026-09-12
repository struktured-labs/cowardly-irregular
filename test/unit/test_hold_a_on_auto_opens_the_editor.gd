extends GutTest

## Hold ui_accept on the battle command menu's "Auto" row for 1.5s and the autobattle editor
## opens. That is what BattleScene._process_hold_a is for, it runs every frame, and it could
## never fire.
##
## The hold resolves its target from get_selected_item_data() on the ROOT menu — and the root's
## "auto_menu" row carried a submenu, a label and a tooltip but NO `data` key. So selected_data
## was null, `_auto_combatant` was never assigned, and `if _hold_timer >= HOLD_DURATION and
## _auto_combatant` was false forever. Every submenu row under it carries its own combatant; the
## row hosting them did not. The editor stayed reachable via the "Auto Rules" row and the Start
## button, so the failure was a dead shortcut rather than a lockout — which is why nothing caught it.
##
## This asserts against the REAL built menu, not the source text: the neighbouring guard on this
## file pins strings, and a string pin cannot tell a row with a data key from one without.

const MenuBuilder := preload("res://src/battle/BattleCommandMenu.gd")

func _combatant() -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": "Fighter", "max_hp": 100, "max_mp": 20,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10
	})
	add_child_autofree(c)
	return c

## The builder reads `_scene.get_viewport()` and `_scene.test_enemies`. A null scene makes the
## first line ERROR, which ABORTS the function and returns the typed default `[]` — the menu reads
## as empty rather than as broken. My first harness did exactly that and the populated-menu control
## is what caught it, not the assertions under test.
class _StubScene extends Node2D:
	const FORMATION_NAMES := ["V-Formation", "Front Line", "Back Row", "Diamond", "Spread"]
	var current_formation: int = 0
	var test_enemies: Array = []
	var party_members: Array = []
	var party_sprite_nodes: Array = []
	var enemy_sprite_nodes: Array = []

func _items() -> Array:
	var stub := _StubScene.new()
	add_child_autofree(stub)
	var builder = MenuBuilder.new(stub)
	var items: Array = builder.build_command_menu_items_with_targets(_combatant())
	assert_gt(items.size(), 2, "CONTROL: the builder returned a populated menu (%d rows)" % items.size())
	return items

func _row(items: Array, id: String) -> Dictionary:
	for it in items:
		if str((it as Dictionary).get("id", "")) == id:
			return it
	return {}

func test_the_auto_row_carries_the_combatant_the_hold_needs() -> void:
	var row := _row(_items(), "auto_menu")
	assert_false(row.is_empty(), "CONTROL: the Auto row exists at the menu root")
	var data = row.get("data", null)
	assert_true(data is Dictionary,
		"the Auto row has no `data` key — get_selected_item_data() returns null and the hold can never resolve a combatant")
	assert_true((data as Dictionary).get("combatant", null) is Combatant,
		"the Auto row's data must carry the combatant the editor is opened for")

func test_the_submenu_rows_still_carry_theirs() -> void:
	## CONTROL against a fix that moves the data instead of adding it: the rows under Auto each
	## need their own combatant, because that is how their actions resolve a target today.
	var items := _items()
	var auto_row := _row(items, "auto_menu")
	var subs: Array = auto_row.get("submenu", []) as Array
	assert_gt(subs.size(), 2, "CONTROL: the Auto row still hosts its submenu (%d rows)" % subs.size())
	var missing: Array = []
	for s in subs:
		var d = (s as Dictionary).get("data", null)
		if not (d is Dictionary) or not ((d as Dictionary).get("combatant", null) is Combatant):
			missing.append(str((s as Dictionary).get("id", "?")))
	assert_eq(missing.size(), 0, "a submenu row lost its combatant: " + str(missing))

func test_a_polled_hold_refuses_while_a_submenu_is_open() -> void:
	## _process_hold_a polls Input from _process, so it inherits NONE of _input's refusals —
	## cowir-controller's MenuRepeat shape, same file family. With a submenu open the player is
	## confirming a row THERE, while the root's selected row is still auto_menu. Without this
	## refusal, giving the row its data key turns a dead hold into an editor that opens on top of
	## an open submenu. Source-read because the poll needs a live Win98Menu graph; the behavioural
	## half above is what defends the data contract.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(src.length(), 1000, "CONTROL: BattleScene reads")
	var at: int = src.find("func _process_hold_a")
	assert_gt(at, -1, "CONTROL: the hold handler still exists")
	var body: String = src.substr(at, 1200)
	var code: String = ""
	for line in body.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		code += line + "\n"
	assert_true(code.contains("Input.is_action_pressed"),
		"CONTROL: the stripper left the polled read intact")
	assert_true(code.contains("active_win98_menu.submenu"),
		"the polled hold does not consult the open submenu — it fires while the player is in one")

func test_the_editor_stays_reachable_from_the_submenu() -> void:
	## Scope note and anti-overreach: the hold is a SHORTCUT. The Auto Rules row is the route a
	## mouse-only player uses and it must not be what a fix to the shortcut disturbs.
	var auto_row := _row(_items(), "auto_menu")
	var ids: Array = []
	for s in (auto_row.get("submenu", []) as Array):
		ids.append(str((s as Dictionary).get("id", "")))
	assert_true(ids.has("autobattle_edit"), "the Auto Rules row must survive: %s" % str(ids))
