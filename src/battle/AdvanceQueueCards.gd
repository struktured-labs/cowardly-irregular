extends Control
class_name AdvanceQueueCards

## The Advance queue, shown (struktured 2026-10-03: "the queued up actions when you advance ABSOLUTELY
## must be shown somewhere ... cascading cards"). One card per queued action, trailing the live command
## menu up and to the right into open battlefield, oldest nearest the menu. Until now the queue surfaced
## only as a count in the hint bar. Reads the menu's queue; never writes it.

const CARD_W := 210.0
const CARD_H := 30.0
## Each newer card steps this far up-right of the last, so the stack reads as a cascade, not a list.
const STEP := Vector2(22.0, -24.0)
const BADGES := ["①", "②", "③", "④", "⑤"]

var _cards: Array[PanelContainer] = []
var _keys: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 99  # under the live menu (100), over the battlefield


## A queued entry as the player should read it: what, and at whom.
static func describe(data, scene) -> Dictionary:
	var d: Dictionary = data if data is Dictionary else {}
	var out := {"name": "?", "target": "", "icon": null}
	if d.has("ability_id"):
		var aid := str(d["ability_id"])
		out["name"] = AbilityIcons.name_of(aid)
		out["icon"] = AbilityIcons.tinted(aid)
	elif d.has("item_id"):
		var iid := str(d["item_id"])
		out["name"] = str(ItemSystem.get_item(iid).get("name", iid.capitalize())) if ItemSystem else iid.capitalize()
		out["icon"] = ItemIcons.tinted(iid)
	elif str(d.get("action", "")) == "attack":
		out["name"] = "Attack"
	elif d.has("group_type"):
		out["name"] = str(d.get("formation_id", d["group_type"])).capitalize().replace("_", " ")
	out["target"] = _target_name(d, scene)
	return out


static func _target_name(d: Dictionary, scene) -> String:
	if not d.has("target_idx") or scene == null:
		return ""
	var idx := int(d["target_idx"])
	var pool: Array = []
	match str(d.get("target_type", "enemy")):
		"ally", "dead_ally":
			pool = scene.party_members if "party_members" in scene else []
		_:
			pool = scene.test_enemies if "test_enemies" in scene else []
	if idx < 0 or idx >= pool.size() or not is_instance_valid(pool[idx]):
		return ""
	return str(pool[idx].combatant_name)


## Rebuild from the queue: keep the cards that still match, pop the ones undone, add the new ones.
func show_queue(entries: Array, anchor: Rect2, scene, animate: bool) -> void:
	var keys: Array[String] = []
	for e in entries:
		keys.append(str(e.get("id", "")) + "|" + str(e.get("data", {})))
	var keep := 0
	while keep < mini(keys.size(), _keys.size()) and keys[keep] == _keys[keep]:
		keep += 1
	while _cards.size() > keep:
		_pop(_cards.pop_back(), animate)
		_keys.pop_back()
	for i in range(keep, entries.size()):
		var card := _make_card(i, describe(entries[i].get("data", {}), scene))
		add_child(card)
		_cards.append(card)
		_keys.append(keys[i])
		_place(card, i, anchor, animate)
	for i in range(keep):
		_cards[i].position = _slot(i, anchor)


func clear(animate: bool = false) -> void:
	show_queue([], Rect2(), null, animate)


func card_count() -> int:
	return _cards.size()


func card_text(i: int) -> String:
	if i < 0 or i >= _cards.size():
		return ""
	var l: Label = _cards[i].find_child("Text", true, false)
	return l.text if l else ""


## Up-right from the menu's top-right corner when a full queue fits above it; a menu near the top
## of the screen (the lead PC's) mirrors the cascade down-right from its bottom-right corner instead,
## so cards never pile into the round header on the clamp.
const TOP_LIMIT := 64.0


func _slot(i: int, anchor: Rect2) -> Vector2:
	var vp := get_viewport_rect().size
	var need := CARD_H + 6.0 + absf(STEP.y) * float(BADGES.size() - 1)
	var up := anchor.position.y - need >= TOP_LIMIT
	var p: Vector2
	if up:
		p = Vector2(anchor.end.x - CARD_W * 0.5, anchor.position.y - CARD_H - 6.0) + STEP * float(i)
	else:
		p = Vector2(anchor.end.x - CARD_W * 0.5, anchor.end.y + 6.0) + Vector2(STEP.x, -STEP.y) * float(i)
	p.x = clampf(p.x, 8.0, vp.x - CARD_W - 8.0)
	p.y = clampf(p.y, TOP_LIMIT, vp.y - CARD_H - 8.0)
	return p


func _place(card: Control, i: int, anchor: Rect2, animate: bool) -> void:
	var rest := _slot(i, anchor)
	if not animate:
		card.position = rest
		return
	## Out of the menu's corner to its slot, so each Advance visibly LEAVES a card behind.
	card.position = Vector2(rest.x, anchor.position.y if rest.y < anchor.position.y else anchor.end.y - CARD_H)
	card.modulate.a = 0.0
	var t := card.create_tween()
	t.set_parallel(true)
	t.tween_property(card, "position", rest, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(card, "modulate:a", 1.0, 0.10)


func _pop(card: Control, animate: bool) -> void:
	if not is_instance_valid(card):
		return
	if not animate:
		card.queue_free()
		return
	var t := card.create_tween()
	t.set_parallel(true)
	t.tween_property(card, "position:y", card.position.y - 14.0, 0.12)
	t.tween_property(card, "modulate:a", 0.0, 0.12)
	t.chain().tween_callback(card.queue_free)


func _make_card(i: int, info: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.15, 0.62)
	style.border_color = Color(0.85, 0.7, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 6
	card.add_theme_stylebox_override("panel", style)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	var badge := Label.new()
	badge.text = BADGES[mini(i, BADGES.size() - 1)]
	_style_label(badge, Color(1.0, 0.85, 0.3))
	h.add_child(badge)
	if info.get("icon") is Texture2D:
		var icon := TextureRect.new()
		icon.texture = info["icon"]
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(icon)
	var text := Label.new()
	text.name = "Text"
	var target := str(info.get("target", ""))
	text.text = str(info.get("name", "?")) + ("  → " + target if target != "" else "")
	text.clip_text = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(text, Color.WHITE)
	h.add_child(text)
	return card


static func _style_label(l: Label, color: Color) -> void:
	l.add_theme_font_size_override("font_size", TextScale.scaled(12))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
