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


## -- Execution: the same cards while an Advance RUNS ------------------------------------------------
## Beside the acting PC, facing the battlefield: the current action lit, each done one peeling away with
## the target it ACTUALLY hit (a retarget shows), and any that never fired marked "held". Fed by
## BattleManager's action_executing (type advance) and the per-step action_executed, so a menu Advance
## and an autobattle plan show alike.

var _run_index := -1
var _run_planned: Array[String] = []
## The action dicts the run was built from: BattleManager emits these SAME dicts per step, so a step is
## matched by identity, not by count. A held step (a heal/Raise nobody needs) emits nothing.
var _run_actions: Array = []


## A BattleManager action ({type, ability_id/item_id, target/targets}) as a card reads it.
static func describe_action(action: Dictionary) -> Dictionary:
	var out := {"name": "?", "target": "", "icon": null}
	var aid := str(action.get("ability_id", ""))
	var iid := str(action.get("item_id", ""))
	if aid != "":
		out["name"] = AbilityIcons.name_of(aid)
		out["icon"] = AbilityIcons.tinted(aid)
	elif iid != "":
		out["name"] = str(ItemSystem.get_item(iid).get("name", iid.capitalize())) if ItemSystem else iid.capitalize()
		out["icon"] = ItemIcons.tinted(iid)
	elif str(action.get("type", "")) == "attack":
		out["name"] = "Attack"
	else:
		out["name"] = str(action.get("type", "?")).capitalize()
	out["target"] = names_of(_action_targets(action))
	return out


static func _action_targets(action: Dictionary) -> Array:
	var ts: Array = []
	if action.get("target") != null:
		ts.append(action.get("target"))
	for t in action.get("targets", []):
		if not ts.has(t):
			ts.append(t)
	return ts


static func names_of(targets: Array) -> String:
	var names: PackedStringArray = []
	for t in targets:
		if is_instance_valid(t) and "combatant_name" in t:
			names.append(str(t.combatant_name))
	if names.size() > 2:
		return "%d targets" % names.size()
	return ", ".join(names)


func run_begin(actions: Array, beside: Rect2, animate: bool) -> void:
	clear(false)
	_run_planned.clear()
	_run_actions = actions.duplicate()
	var vp := get_viewport_rect().size
	for i in actions.size():
		var info := describe_action(actions[i])
		_run_planned.append(str(info["target"]))
		var card := _make_card(i, info)
		add_child(card)
		_cards.append(card)
		_keys.append("run%d" % i)
		var p := Vector2(beside.position.x - CARD_W - 12.0 - 10.0 * i, beside.position.y + i * (CARD_H + 4.0))
		p.x = clampf(p.x, 8.0, vp.x - CARD_W - 8.0)
		p.y = clampf(p.y, TOP_LIMIT, vp.y - CARD_H - 8.0)
		card.position = p
		card.modulate.a = 0.55
	_run_index = 0
	_light(0, animate)


## A step resolved against `targets`: name who it actually hit, peel it, light the next. `action` is the
## emitted dict; steps passed over before it never fired (held at execution) and say so.
func run_step(targets: Array, animate: bool, action = null) -> void:
	if _run_index < 0 or _run_index >= _cards.size():
		return
	if action != null:
		var at := -1
		for j in range(_run_index, _run_actions.size()):
			if is_same(_run_actions[j], action):
				at = j
				break
		if at < 0:
			return  # not one of this run's steps
		while _run_index < at:
			_mark_held(_run_index)
			_peel(_cards[_run_index], animate)
			_run_index += 1
	var i := _run_index
	var hit := names_of(targets)
	var l: Label = _cards[i].find_child("Text", true, false)
	if l and hit != "" and hit != _run_planned[i]:
		l.text = l.text.split("  → ")[0] + "  → " + hit + " (retarget)"
	elif l and hit != "":
		l.text = l.text.split("  → ")[0] + "  → " + hit
	_peel(_cards[i], animate)
	_run_index += 1
	if _run_index < _cards.size():
		_light(_run_index, animate)


## The Advance stopped (its actor fell, the battle ended): what never fired says so, then all fade.
func run_end(animate: bool) -> void:
	if _run_index < 0:
		return
	for i in range(maxi(0, _run_index), _cards.size()):
		_mark_held(i)
	_run_index = -1
	for c in _cards:
		_peel(c, animate)
	_cards.clear()
	_keys.clear()


## A step is still to fire.
func _mark_held(i: int) -> void:
	if i < 0 or i >= _cards.size() or not is_instance_valid(_cards[i]):
		return
	var l: Label = _cards[i].find_child("Text", true, false)
	if l:
		l.text = l.text.split("  → ")[0] + "  — held"
		l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))


func is_running() -> bool:
	return _run_index >= 0 and _run_index < _cards.size()


func _light(i: int, animate: bool) -> void:
	if i < 0 or i >= _cards.size():
		return
	var c := _cards[i]
	c.modulate.a = 1.0
	var st := c.get_theme_stylebox("panel") as StyleBoxFlat
	if st:
		st.border_color = Color(1.0, 0.95, 0.5)
		st.set_border_width_all(2)
	if animate:
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(1.08, 1.08)
		c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.12)


func _peel(card: Control, animate: bool) -> void:
	if not is_instance_valid(card):
		return
	if not animate:
		card.queue_free()
		return
	var t := card.create_tween()
	t.tween_interval(0.25)
	t.tween_property(card, "position:x", card.position.x - 40.0, 0.18)
	t.parallel().tween_property(card, "modulate:a", 0.0, 0.18)
	t.tween_callback(card.queue_free)
