extends Control
class_name FastTravelMenu

## FastTravelMenu — player-facing crystal-to-crystal warp (old queue item 4).
##
## Lists save crystals the player has ACTIVATED (GameState.activated_crystals,
## keyed by map_id — a crystal activates the first time you save at it).
## Warping costs gold scaling with world-tier distance. Debug TeleportMenu
## stays separate — this is the diegetic, gated, paid version.
##
## Emits `teleport_requested(map_id, spawn_point)` on a paid pick; the caller
## (SavePoint) routes it to GameLoop._on_area_transition.

signal teleport_requested(map_id: String, spawn_point: String)
signal closed()

## map_id → world tier for cost scaling. Prefix-matched, first hit wins.
const WORLD_TIERS: Dictionary = {
	"overworld": 1, "harmonia": 1, "whispering": 1, "castle": 1,
	"ice_dragon": 1, "fire_dragon": 1, "shadow_dragon": 1, "lightning_dragon": 1,
	"frosthold": 1, "eldertree": 1, "grimhollow": 1, "sandrift": 1, "ironhaven": 1,
	"scriptura": 1,
	"tavern": 1, "inn_interior": 1, "shop_interior": 1, "blacksmith": 1,
	"suburban": 2, "maple": 2,
	"steampunk": 3, "brasston": 3,
	"industrial": 4, "rivet": 4, "assembly": 4,
	"futuristic": 5, "node_prime": 5, "root_process": 5,
	"abstract": 6, "vertex": 6, "null_chamber": 6,
}

const BASE_COST: int = 50
const COST_PER_TIER: int = 100

const ROW_HEIGHT: int = 28
const ROW_FONT_SIZE: int = 13
const BG_COLOR = Color(0.05, 0.05, 0.10, 0.95)
const PANEL_COLOR = Color(0.10, 0.10, 0.15)
const SELECTED_COLOR = Color(0.20, 0.30, 0.50)
const TEXT_COLOR = Color(1.00, 1.00, 1.00)
const GOLD_COLOR = Color(1.00, 0.90, 0.30)
const DISABLED_COLOR = Color(0.40, 0.40, 0.40)

## Injected by the caller: where the player currently is (excluded + cost anchor).
var current_map_id: String = "overworld"

var _rows: Array = []              # {id, label, spawn, cost, affordable}
var _selected: int = 0
var _highlight_refs: Array = []
var _cursor_refs: Array = []


static func world_tier_for(map_id: String) -> int:
	for prefix in WORLD_TIERS:
		if map_id.begins_with(prefix):
			return WORLD_TIERS[prefix]
	return 1


static func travel_cost(from_map: String, to_map: String) -> int:
	return BASE_COST + COST_PER_TIER * abs(world_tier_for(from_map) - world_tier_for(to_map))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_collect_rows()
	_build_ui()


func _collect_rows() -> void:
	_rows.clear()
	var meta: Dictionary = {}
	for dest in TeleportMenu.DESTINATIONS:
		meta[dest["id"]] = dest
	var gold: int = GameState.get_gold()
	for map_id in GameState.activated_crystals:
		if map_id == current_map_id:
			continue
		var m: Dictionary = meta.get(map_id, {})
		var label: String = m.get("label", str(map_id).replace("_", " ").capitalize())
		var spawn: String = m.get("spawn", "default")
		var cost: int = travel_cost(current_map_id, map_id)
		_rows.append({"id": map_id, "label": label, "spawn": spawn,
			"cost": cost, "affordable": gold >= cost})
	_rows.sort_custom(func(a, b): return a["cost"] < b["cost"])


func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	MenuMouseHelper.add_right_click_cancel(bg, _close)

	var panel = Control.new()
	panel.position = Vector2(size.x * 0.24, size.y * 0.14)
	panel.size = Vector2(size.x * 0.52, size.y * 0.72)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)
	RetroPanel.add_border(panel, panel.size, RetroPanel.BORDER_LIGHT, RetroPanel.BORDER_SHADOW)

	var title = Label.new()
	title.text = "CRYSTAL WARP"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0))
	panel.add_child(title)

	var gold_label = Label.new()
	gold_label.text = "%d G" % GameState.get_gold()
	gold_label.position = Vector2(panel.size.x - 136, 10)
	gold_label.size = Vector2(120, 20)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.add_theme_font_size_override("font_size", 14)
	gold_label.add_theme_color_override("font_color", GOLD_COLOR)
	panel.add_child(gold_label)

	var sub = Label.new()
	sub.text = "Warp between attuned crystals — cost scales with distance"
	sub.position = Vector2(16, 32)
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(sub)

	if _rows.is_empty():
		var empty = Label.new()
		empty.text = "No other attuned crystals yet.\nSave at crystals across the worlds to attune them."
		empty.position = Vector2(16, 72)
		empty.size = Vector2(panel.size.x - 32, 60)
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", DISABLED_COLOR)
		panel.add_child(empty)
		return

	var y: float = 60.0
	for i in range(_rows.size()):
		var row = _rows[i]
		var item = Control.new()
		item.position = Vector2(16, y)
		item.size = Vector2(panel.size.x - 32, ROW_HEIGHT - 2)
		item.mouse_filter = Control.MOUSE_FILTER_STOP

		var hl = ColorRect.new()
		hl.color = Color.TRANSPARENT
		hl.size = item.size
		item.add_child(hl)

		var cursor = Label.new()
		cursor.text = "  "
		cursor.position = Vector2(4, 3)
		cursor.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		cursor.add_theme_color_override("font_color", Color.YELLOW)
		item.add_child(cursor)

		var name_label = Label.new()
		name_label.text = row["label"]
		name_label.position = Vector2(26, 3)
		name_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		name_label.add_theme_color_override("font_color",
			TEXT_COLOR if row["affordable"] else DISABLED_COLOR)
		item.add_child(name_label)

		var cost_label = Label.new()
		cost_label.text = "%d G" % row["cost"]
		cost_label.position = Vector2(item.size.x - 110, 3)
		cost_label.size = Vector2(100, ROW_HEIGHT - 6)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost_label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		cost_label.add_theme_color_override("font_color",
			GOLD_COLOR if row["affordable"] else DISABLED_COLOR)
		item.add_child(cost_label)

		MenuMouseHelper.make_clickable(item, i, int(item.size.x), ROW_HEIGHT - 2,
			_on_row_click.bind(i), _on_row_hover.bind(i))

		panel.add_child(item)
		_highlight_refs.append(hl)
		_cursor_refs.append(cursor)
		y += ROW_HEIGHT

	_update_selection()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up") and not event.is_echo():
		_move(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") and not event.is_echo():
		_move(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_pick()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close()
		get_viewport().set_input_as_handled()


func _move(delta: int) -> void:
	if _rows.is_empty():
		return
	var n = _rows.size()
	_selected = ((_selected + delta) % n + n) % n
	_update_selection()
	if SoundManager:
		SoundManager.play_ui("menu_move")


func _update_selection() -> void:
	for i in range(_highlight_refs.size()):
		_highlight_refs[i].color = SELECTED_COLOR if i == _selected else Color.TRANSPARENT
		_cursor_refs[i].text = "▶ " if i == _selected else "  "


func _pick() -> void:
	if _rows.is_empty() or _selected >= _rows.size():
		return
	var row = _rows[_selected]
	if not row["affordable"]:
		if SoundManager:
			SoundManager.play_ui("menu_error")
		return
	if not GameState.spend_gold(row["cost"]):
		if SoundManager:
			SoundManager.play_ui("menu_error")
		return
	if SoundManager:
		SoundManager.play_ui("menu_select")
		# crystal-to-crystal dimensional whoosh (cowir-sfx msg 2160)
		SoundManager.play_ui("portal_enter")
	teleport_requested.emit(row["id"], row["spawn"])
	closed.emit()
	queue_free()


func _on_row_click(idx: int) -> void:
	_selected = idx
	_update_selection()
	_pick()


func _on_row_hover(idx: int) -> void:
	if idx != _selected:
		_selected = idx
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")


func _close() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_cancel")
	closed.emit()
	queue_free()
