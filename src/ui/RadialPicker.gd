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

		var label := _label_of(slice[i])
		var font := ThemeDB.fallback_font
		var fs := 10
		# Ring labels sit OUTSIDE their node, pushed radially, so long ability names
		# never overlap the node art or each other near the top and bottom of the ring.
		var out := (p - _center).normalized()
		var lp := p + out * (NODE_RADIUS + 12.0)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if out.x < -0.2:
			lp.x -= w
		elif absf(out.x) <= 0.2:
			lp.x -= w * 0.5
		draw_string(font, lp + Vector2(0, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			TEXT if is_sel else DIM_TEXT)

	_draw_center()


func _draw_center() -> void:
	var font := ThemeDB.fallback_font
	var title := str(spec.get("title", "Select"))
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, _center + Vector2(-tw * 0.5, -18), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM_TEXT)

	if _selected >= 0 and _selected < _options.size():
		var label := _label_of(_options[_selected])
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, _center + Vector2(-lw * 0.5, 4), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ACCENT)

	if _page_count() > 1:
		var pg := "%d / %d   [L1/R1]" % [_page + 1, _page_count()]
		var pw := font.get_string_size(pg, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, _center + Vector2(-pw * 0.5, 24), pg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM_TEXT)

	var hint := "[Dir] Aim   [A] Confirm   [B] Back"
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(_center.x - hw * 0.5, size.y - 24), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM_TEXT)


func _label_of(opt) -> String:
	if opt is Dictionary:
		return str(opt.get("label", opt.get("id", "?")))
	return str(opt)
