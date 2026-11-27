extends Control
class_name RadialPicker

## Ring selector for the autobattle / autogrind grid editors (struktured 2026-07-28:
## "consider a ring like selector for the different abilities in autobattle/autogrind menus").
##
## Why a ring beats a list HERE specifically: this project is controller-first, and on a d-pad a
## list is O(n) presses to reach item n while a ring is a DIRECTION — you point at what you want.
## That only holds while every option is simultaneously visible, so the ring pages at RING_CAPACITY
## rather than cramming; a 30-entry ring would be slower than the list it replaced.
##
## Deliberately takes the SAME spec Dictionary as AutobattleGridEditor._open_option_picker
## ({title, kind, options:[{id,label}], selected, action_ctx}) so it drops in beside the list
## picker instead of forcing a rewrite, and either can be swapped without touching call sites.

signal option_chosen(option_id: String, spec: Dictionary)
signal cancelled()

## Past this, spokes crowd and the direction→item mapping stops being readable. Ring pages instead.
const RING_CAPACITY := 10
const RADIUS := 132.0
const NODE_RADIUS := 26.0
const DEADZONE := 0.45

const BG_DIM := Color(0.0, 0.0, 0.0, 0.72)
const RING_COLOR := Color(0.28, 0.30, 0.42)
const NODE_BG := Color(0.10, 0.11, 0.17)
const NODE_SEL := Color(0.24, 0.38, 0.62)
const TEXT := Color(0.94, 0.94, 1.0)
const DIM_TEXT := Color(0.52, 0.54, 0.64)
const ACCENT := Color(1.0, 0.84, 0.36)

var spec: Dictionary = {}

var _options: Array = []
var _selected: int = 0
var _page: int = 0
var _center: Vector2 = Vector2.ZERO
var _anim: float = 0.0


func setup(picker_spec: Dictionary) -> void:
	spec = picker_spec
	_options = spec.get("options", [])
	_selected = clampi(int(spec.get("selected", 0)), 0, maxi(0, _options.size() - 1))
	_page = _selected / RING_CAPACITY


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The option icons are 16px pixel art drawn at 2x; linear filtering would smear them.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Right-click closes the ring, matching the 33 other screens. SAFE because of the line above:
	# STOP means the ring CONSUMES the click, so it cannot leak to the editor's own background
	# right-click-cancel underneath and close the whole editor. Derived from the filter, the child
	# order (the ring is added after the bg) and this file having zero prior right-click handlers —
	# not measured by a click, because gui_input needs real GUI picking and a SubViewport harness
	# does not perform it.
	MenuMouseHelper.add_right_click_cancel(self, func() -> void:
		cancelled.emit()
		queue_free())
	set_process(true)
	set_process_unhandled_input(true)


func _process(delta: float) -> void:
	_anim += delta
	queue_redraw()


# ── geometry ────────────────────────────────────────────────────────

func _page_count() -> int:
	return maxi(1, int(ceil(float(_options.size()) / float(RING_CAPACITY))))


func _page_slice() -> Array:
	var start := _page * RING_CAPACITY
	return _options.slice(start, mini(start + RING_CAPACITY, _options.size()))


## Angle for slot i of n, starting at 12 o'clock and running clockwise so "up" is always
## the first entry — a stable anchor matters more than balanced spacing when paging.
func _slot_angle(i: int, n: int) -> float:
	return -PI / 2.0 + TAU * float(i) / float(maxi(1, n))


func _slot_pos(i: int, n: int) -> Vector2:
	var a := _slot_angle(i, n)
	return _center + Vector2(cos(a), sin(a)) * RADIUS


# ── input ───────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# A new input consumer arrives UNGATED by default — a hint dismiss must not also pick
	if TutorialHint.is_any_active():
		return

	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		cancelled.emit()
		queue_free()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_accept") and not event.is_echo():
		_confirm()
		get_viewport().set_input_as_handled()
		return

	# Shoulders page — same L1/R1 convention MenuPaging uses for long lists.
	if event.is_action_pressed("battle_advance") and not event.is_echo():
		_turn_page(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("battle_defer") and not event.is_echo():
		_turn_page(-1)
		get_viewport().set_input_as_handled()
		return

	# Direction → slot. This is the whole point of the ring, so it takes the raw
	# vector rather than stepping, letting a diagonal land directly on a diagonal spoke.
	var dir := _input_direction(event)
	if dir != Vector2.ZERO:
		_select_toward(dir)
		get_viewport().set_input_as_handled()


func _input_direction(event: InputEvent) -> Vector2:
	if event is InputEventJoypadMotion:
		var v := Vector2(
			Input.get_joy_axis(event.device, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(event.device, JOY_AXIS_LEFT_Y))
		return v if v.length() > DEADZONE else Vector2.ZERO
	if event.is_echo():
		return Vector2.ZERO
	var d := Vector2.ZERO
	if event.is_action_pressed("ui_up"):    d += Vector2.UP
	if event.is_action_pressed("ui_down"):  d += Vector2.DOWN
	if event.is_action_pressed("ui_left"):  d += Vector2.LEFT
	if event.is_action_pressed("ui_right"): d += Vector2.RIGHT
	return d


## Picks the slot whose angle best matches the pushed direction.
func _select_toward(dir: Vector2) -> void:
	var slice := _page_slice()
	if slice.is_empty():
		return
	var want := dir.angle()
	var best := 0
	var best_delta := TAU
	for i in range(slice.size()):
		var delta: float = absf(wrapf(_slot_angle(i, slice.size()) - want, -PI, PI))
		if delta < best_delta:
			best_delta = delta
			best = i
	var target := _page * RING_CAPACITY + best
	if target != _selected:
		_selected = target
		if SoundManager:
			SoundManager.play_ui("menu_move")
	queue_redraw()


func _turn_page(delta: int) -> void:
	if _page_count() <= 1:
		return
	_page = wrapi(_page + delta, 0, _page_count())
	_selected = clampi(_page * RING_CAPACITY, 0, _options.size() - 1)
	if SoundManager:
		SoundManager.play_ui("menu_move")
	queue_redraw()


func _confirm() -> void:
	if _selected < 0 or _selected >= _options.size():
		return
	var opt = _options[_selected]
	var oid := str(opt.get("id", "")) if opt is Dictionary else str(opt)
	if SoundManager:
		SoundManager.play_ui("menu_select")
	option_chosen.emit(oid, spec)
	queue_free()


# ── drawing ─────────────────────────────────────────────────────────

func _draw() -> void:
	_center = size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), BG_DIM)

	var slice := _page_slice()
	var n := slice.size()
	if n == 0:
		return

	draw_arc(_center, RADIUS, 0.0, TAU, 96, RING_COLOR, 2.0, true)

	var sel_local := _selected - _page * RING_CAPACITY
	for i in range(n):
		var p := _slot_pos(i, n)
		var is_sel := i == sel_local
		# A spoke to the selected node makes the direction→item mapping legible at a glance.
		if is_sel:
			draw_line(_center, p, ACCENT, 2.0, true)
		draw_circle(p, NODE_RADIUS + (3.0 if is_sel else 0.0), NODE_SEL if is_sel else NODE_BG)
		draw_arc(p, NODE_RADIUS + (3.0 if is_sel else 0.0), 0.0, TAU, 32,
			ACCENT if is_sel else RING_COLOR, 2.0, true)
		var tex := icon_for(slice[i])
		if tex:
			draw_texture_rect(tex, Rect2(p - Vector2(16, 16), Vector2(32, 32)), false)

		var label := _label_of(slice[i])
		var font := ring_font()
		var lr := label_rect(i, n, label)
		draw_string(font, Vector2(lr.position.x, lr.position.y + font.get_ascent(_px(10))), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, _px(10), TEXT if is_sel else DIM_TEXT)

	_draw_center()


func _draw_center() -> void:
	var font := ring_font()
	for line in centre_layout():
		draw_string(font, Vector2(line["rect"].position.x, line["rect"].position.y + font.get_ascent(line["px"])), line["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, line["px"], line["color"])
	var hint := "[Dir] Aim   %s Confirm   %s Back" % [InputProfileManager.hint_for_action("ui_accept"), InputProfileManager.hint_for_action("ui_cancel")]
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(10)).x
	draw_string(font, Vector2(_center.x - hw * 0.5, size.y - 24.0 * _k()), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, _px(10), DIM_TEXT)


# ── layout (shared by _draw and the Text Size guard) ────────────────

## The face the ring draws and measures with: one font, so a measured rect is the drawn one.
func ring_font() -> Font:
	return UiFont.of(self)


## Every ring string follows Text Size; 100% is the authored 10 / 13 / 15 px.
func _px(base: int) -> int:
	return TextScale.scaled(base)


func _k() -> float:
	return float(_px(100)) / 100.0


## Where slot i of n draws its label: outside its node, pushed radially, anchored by the side it sits on.
func label_rect(i: int, n: int, label: String) -> Rect2:
	_center = size * 0.5
	var font := ring_font()
	var fs := _px(10)
	var p := _slot_pos(i, n)
	var out := (p - _center).normalized()
	var lp := p + out * (NODE_RADIUS + 12.0)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if out.x < -0.2:
		lp.x -= w
	elif absf(out.x) <= 0.2:
		lp.x -= w * 0.5
	var base := lp.y + 4.0
	return Rect2(lp.x, base - font.get_ascent(fs), w, font.get_height(fs))


## The centre lines' room: a circle that clears every node's inner edge, so no centre text can touch a node.
func centre_radius() -> float:
	return RADIUS - NODE_RADIUS - 6.0


## Title, selection and page line on their authored baselines while they fit the centre circle; else stacked and wrapped
## to it (the selection may end in "…", its outer label stays whole); the title moves above the ring when even that fails.
func centre_layout() -> Array:
	_center = size * 0.5
	var blocks := _centre_blocks()
	var authored := _place_authored(blocks)
	if _inside(authored):
		return authored
	var packed := _pack(blocks)
	if _inside(packed):
		return packed
	return _title_above(blocks[0]) + _pack(blocks.slice(1))


func _centre_blocks() -> Array:
	var font := ring_font()
	var blocks: Array = [{"text": str(spec.get("title", "Select")), "px": _px(13), "base": -18.0, "color": DIM_TEXT, "cut": false}]
	if _selected >= 0 and _selected < _options.size():
		blocks.append({"text": _label_of(_options[_selected]), "px": _px(15), "base": 4.0, "color": ACCENT, "cut": true})
	if _page_count() > 1:
		var pg := "%d / %d   [%s/%s]" % [_page + 1, _page_count(),
			InputProfileManager.hint_for_action("battle_defer"),
			InputProfileManager.hint_for_action("battle_advance")]
		var pw := font.get_string_size(pg, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(10)).x
		blocks.append({"text": pg, "px": _px(10), "base": 24.0, "color": DIM_TEXT, "cut": false, "w": pw})
	return blocks


func _line(text: String, px: int, color: Color, top: float, where: String) -> Dictionary:
	var font := ring_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	return {"text": text, "px": px, "color": color, "where": where, "rect": Rect2(_center.x - w * 0.5, top, w, font.get_height(px))}


func _place_authored(blocks: Array) -> Array:
	var out: Array = []
	for b in blocks:
		out.append(_line(str(b["text"]), int(b["px"]), b["color"], _center.y + float(b["base"]) * _k() - ring_font().get_ascent(int(b["px"])), "centre"))
	return out


## Every centre line inside the centre circle and below the line before it.
func _inside(lines: Array) -> bool:
	var prev := -INF
	var cr := centre_radius() + 0.5
	for l in lines:
		if l["where"] != "centre":
			continue
		var r: Rect2 = l["rect"]
		if r.position.y < prev - 0.5:
			return false
		prev = r.end.y
		for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
			if (c - _center).length() > cr:
				return false
	return true


## The width the centre circle leaves for a line spanning top..bottom.
func _chord(top: float, bottom: float) -> float:
	var cr := centre_radius()
	var d := maxf(absf(top - _center.y), absf(bottom - _center.y))
	return 2.0 * sqrt(maxf(0.0, cr * cr - d * d)) if d < cr else 0.0


## The blocks stacked as one column centred in the circle, each line wrapped to the chord at its own height.
func _pack(blocks: Array) -> Array:
	var font := ring_font()
	var lines: Array = []
	var height := 0.0
	for b in blocks:
		height += font.get_height(int(b["px"]))
	for _pass in 6:
		lines = []
		var top := _center.y - height * 0.5
		for b in blocks:
			var px: int = b["px"]
			var h := font.get_height(px)
			var words: PackedStringArray = str(b["text"]).split(" ", false)
			var used := 0
			var k := 0
			while k < words.size():
				var room := _chord(top, top + h)
				var cur := words[k]
				k += 1
				while k < words.size() and font.get_string_size(cur + " " + words[k], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= room:
					cur += " " + words[k]
					k += 1
				used += 1
				if b["cut"] and used == 2 and k < words.size():
					for rest in range(k, words.size()):
						cur += " " + words[rest]
					k = words.size()
				if b["cut"]:
					cur = _ellipsize(font, cur, px, room)
				lines.append(_line(cur, px, b["color"], top, "centre"))
				top += h
		var got := 0.0
		for l in lines:
			got += (l["rect"] as Rect2).size.y
		if absf(got - height) < 0.5:
			break
		height = got
	return lines


## The title as whole lines above the ring's top label, when the centre cannot hold it beside the selection.
func _title_above(b: Dictionary) -> Array:
	var font := ring_font()
	var px: int = b["px"]
	var h := font.get_height(px)
	var words: PackedStringArray = str(b["text"]).split(" ", false)
	var rows: Array = []
	var cur := ""
	for wd in words:
		var trial := wd if cur == "" else cur + " " + wd
		if cur != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > size.x - 32.0:
			rows.append(cur)
			cur = wd
		else:
			cur = trial
	rows.append(cur)
	var slice := _page_slice()
	var top_label: Rect2 = label_rect(0, slice.size(), _label_of(slice[0])) if not slice.is_empty() else Rect2(_center - Vector2(0, RADIUS + NODE_RADIUS), Vector2.ZERO)
	var top := top_label.position.y - 6.0 * _k() - h * rows.size()
	var out: Array = []
	for r in rows:
		out.append(_line(r, px, b["color"], top, "above"))
		top += h
	return out


func _ellipsize(font: Font, text: String, px: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= width:
		return text
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
		t = t.left(t.length() - 1)
	return t.strip_edges() + "…"


## The icon an option draws inside its node: abilities and items have one, every other ring kind none.
func icon_for(opt) -> Texture2D:
	var id := str(opt.get("id", "")) if opt is Dictionary else str(opt)
	if id == "":
		return null
	match str(spec.get("kind", "")):
		"ability_id":
			return AbilityIcons.tinted(id)
		"item_id":
			return ItemIcons.tinted(id)
	return null


func _label_of(opt) -> String:
	if opt is Dictionary:
		return str(opt.get("label", opt.get("id", "?")))
	return str(opt)
