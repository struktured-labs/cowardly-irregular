extends PanelContainer
class_name TrustTurnPill

## The trusted-turn window's on-screen offer (cowir-main 2026-11-05): "<cancel> Take this turn" over the trusted
## member, with a bar draining for the window. The window was announced by one battle-log line only, and since
## .770 it lasts 1.0 WALL second, so a line in a scrolling log was easy to miss.
##
## ⛔ THE BAR DRAINS ON THE WINDOW'S OWN TIMER (BattleManager.trust_window_time_left): battle time emptied it 4x late at
## 0.25, and a private wall-clock deadline drifted from the window whenever frames ran off real time (Movie Maker).

const BASE_FONT_SIZE := 12
## Over the speech bubbles (95), under the target highlight (99) and the command menu (100).
const Z := 96
const GAP := 6.0
const EDGE := 4.0

var label: Label
var _bar: ProgressBar
var _deadline_ms: int = 0
var _total_ms: int = 1
## Returns the window's seconds left (negative once closed). Unset only for a pill built outside a battle.
var _time_left_source: Callable = Callable()


## Builds the pill under `parent`, above `head` (scene coordinates), clear of every rect in `keep_out`.
static func show_over(parent: Node, head: Vector2, token: String, seconds: float, keep_out: Array, time_left_source: Callable = Callable()) -> TrustTurnPill:
	var p := TrustTurnPill.new()
	p.setup(token, seconds, time_left_source)
	parent.add_child(p)
	var vp: Vector2 = (parent as CanvasItem).get_viewport_rect().size if parent is CanvasItem else Vector2(1280, 720)
	var size_now: Vector2 = p.get_combined_minimum_size()
	p.size = size_now
	p.global_position = placed_rect(head, size_now, keep_out, vp).position
	return p


func setup(token: String, seconds: float, time_left_source: Callable = Callable()) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = Z
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	label = Label.new()
	label.text = "%s Take this turn" % token
	label.add_theme_font_size_override("font_size", TextScale.scaled(BASE_FONT_SIZE))
	box.add_child(label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.value = 1.0
	_bar.custom_minimum_size = Vector2(0, 4)
	box.add_child(_bar)
	_total_ms = maxi(1, int(round(seconds * 1000.0)))
	_deadline_ms = Time.get_ticks_msec() + _total_ms
	_time_left_source = time_left_source


func _process(_delta: float) -> void:
	if _bar:
		_bar.value = remaining_fraction()


## The share of the window still open: off the window's own timer when it has one, else off the wall clock.
func remaining_fraction() -> float:
	if _time_left_source.is_valid():
		return clampf(float(_time_left_source.call()) * 1000.0 / float(_total_ms), 0.0, 1.0)
	return clampf(float(_deadline_ms - Time.get_ticks_msec()) / float(_total_ms), 0.0, 1.0)


## Where a pill of `size` goes for a head at `head`: centred above it, stepped up over anything in `keep_out` it
## would cover, then kept on screen. Pure, so placement is testable without a battle. Keep-out rects are UI
## (screen) rects and the pill is in the scene canvas: equal unless a camera push is live, the bubbles' assumption too.
static func placed_rect(head: Vector2, size: Vector2, keep_out: Array, vp: Vector2) -> Rect2:
	var x := clampf(head.x - size.x * 0.5, EDGE, maxf(EDGE, vp.x - size.x - EDGE))
	var r := Rect2(x, head.y - size.y - GAP, size.x, size.y)
	for _pass in keep_out.size():
		var moved := false
		for k in keep_out:
			if k is Rect2 and r.intersects(k):
				r.position.y = (k as Rect2).position.y - size.y - GAP
				moved = true
		if not moved:
			break
	r.position.y = clampf(r.position.y, EDGE, maxf(EDGE, vp.y - size.y - EDGE))
	# A rect reaching the top (a tall command menu) leaves no room above, and the clamp put the pill back ON it:
	# go below that rect instead (cowir-battle review, 2026-11-05).
	for k in keep_out:
		if k is Rect2 and r.intersects(k):
			r.position.y = clampf((k as Rect2).end.y + GAP, EDGE, maxf(EDGE, vp.y - size.y - EDGE))
	return r
