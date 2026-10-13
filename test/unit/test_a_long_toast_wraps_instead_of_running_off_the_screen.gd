extends GutTest

## `Toast.show` built its label with NO `autowrap_mode` at all and assigned
## `size = Vector2(vp_size.x, 40)` BEFORE `add_child`, so every message rendered as one
## unwrapped line at content width and the ends fell off both screen edges.
##
## Reachability is not hypothetical and is not bounded by this repo. `GameLoop`'s bug-report
## toast interpolates an ABSOLUTE path on purpose — its own comment is "the toast prints the
## ABSOLUTE path because a tester cannot act on 'user://'" — so the message length is the
## player's home directory. On the box this was written on that message is 127 characters;
## a longer username pushes it off the screen with nothing in the game having changed.
##
## Fixing the clip creates the second half: a wrapped message is TALLER than one row, and
## `stack_offset` was a COUNT times a fixed 48px stride, so the next toast in the stack would
## print straight through it. That is the same fixed-stride defect as `PartyStatusScreen`'s
## `cy += 44` against a two-line weapon description, and the arms below cover both halves.
##
## ⚠️ THE INSTRUMENT HAS TO RESPECT `autowrap_mode`. Asking the font for a size with a width
## limit reports a WRAPPED result for a label that does not wrap, which would make every arm
## here pass on the unwrapped code. `_rendered()` passes width -1 when autowrap is off, so it
## reports what was actually drawn on either tree.
##
## ⚠️ `Label.size` is NOT text height, and the gap is not small: sizing the label after
## add_child gives a correct 2-line draw inside a 3892px rect, because the minimum size cached
## while the width was still zero wraps one character per line. Line count comes from
## `get_line_count()`, which is what the Label actually draws; the rect is never the instrument.

const T := preload("res://src/ui/Toast.gd")
const FONT_SIZE := 20

## The bug-report shape with a username long enough to clip on the unwrapped label.
##
## MEASURED at font size 20 in Open Sans SemiBold, which is what the Label resolves to: this
## shape reaches the 1280px viewport width once the username is 9 characters. The box this was
## written on has a 10-character username and renders 1282px — clipped by 2px, live today. The
## length below is well past that rather than at it, so the arms do not turn on 2px of font
## metrics; 1-char usernames are not what this guards.
const CLIPPING_USERNAME_LEN := 16

var _host: Control = null


func before_each() -> void:
	_clear_stack()
	_host = Control.new()
	_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(_host)


func after_each() -> void:
	_clear_stack()
	_host = null


## `_active_layers` is a STATIC on the class, so a leftover layer from one arm shifts the next
## arm's stack offset and leaks into every other suite in the process.
func _clear_stack() -> void:
	for l in T._active_layers:
		if is_instance_valid(l):
			l.queue_free()
	T._active_layers = []


func _viewport_width() -> float:
	return _host.get_viewport().get_visible_rect().size.x


## The live toast layers, oldest first — which is also the stack order.
##
## ⚠️ Deliberately NOT a flat walk of every Label under the host. Sorted by y, the second
## entry of such a list is the FIRST toast's drop shadow (it sits 2px lower), not the second
## toast's label, so the stack arm would have compared a toast against its own shadow and red
## on correct code. The pairing has to be per layer.
func _layers() -> Array:
	return T._active_layers.filter(func(l): return is_instance_valid(l))


## One toast's two labels as [label, shadow]. Within a layer the shadow is unambiguously the
## lower of the two, so this does not depend on the order they were added in.
func _pair(layer: Node) -> Array:
	var out: Array = []
	for c in layer.get_children():
		if c is Label:
			out.append(c)
	out.sort_custom(func(a, b): return a.position.y < b.position.y)
	return out


## What the label actually draws: line count from the Label itself, widest line and height from
## the font.
##
## ⚠️ The width limit passed to the font MUST be -1 when the label does not wrap. Asking for a
## size with a limit reports a WRAPPED result for a label that draws one line, which would make
## every arm here pass on the unwrapped code — the guard would agree with the bug.
func _rendered(l: Label) -> Dictionary:
	var font: Font = l.get_theme_font("font")
	if font == null:
		return {}
	var limit: float = -1.0
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		limit = l.size.x
	var lines: int = maxi(1, l.get_line_count())
	return {
		"w": font.get_multiline_string_size(
			l.text, HORIZONTAL_ALIGNMENT_CENTER, limit, FONT_SIZE).x,
		"h": float(lines) * font.get_height(FONT_SIZE),
		"lines": lines,
	}


func _long_bug_report_message() -> String:
	return "Bug report saved to /home/%s/.local/share/godot/app_userdata/Cowardly Irregular/feedback/report_2026-10-12_23-55-01.zip" % [
		"u".repeat(CLIPPING_USERNAME_LEN)]


func test_control_the_viewport_is_the_size_every_other_arm_bounds_against() -> void:
	## Without this a zero or tiny viewport would make every "fits on screen" arm below pass
	## for the wrong reason.
	assert_not_null(_host.get_viewport(), "CONTROL: the host must be in a viewport")
	assert_gt(_viewport_width(), 320.0,
		"CONTROL: the viewport must be wide enough for the bounds arms to mean something, got %.0f" % [_viewport_width()])


func test_control_a_short_message_still_renders_on_one_centred_line() -> void:
	## The fix must not wrap text that was never too wide. This is the arm that reds if the
	## side gutter is set absurdly narrow or the band is forced multi-line.
	T.show(_host, "Game Saved ✓")
	var ls: Array = _layers()
	assert_eq(ls.size(), 1, "one toast must register exactly one live layer, got %d" % [ls.size()])
	if ls.is_empty():
		return
	var r: Dictionary = _rendered(_pair(ls[0])[0])
	assert_false(r.is_empty(), "CONTROL: the label must have a theme font to measure")
	if r.is_empty():
		return
	assert_eq(r["lines"], 1, "a short message must stay on one line, got %d" % [r["lines"]])
	assert_lt(r["w"], _viewport_width(),
		"and it must be narrower than the screen: %.0f px of %.0f" % [r["w"], _viewport_width()])


func test_a_long_message_wraps_rather_than_rendering_as_one_line() -> void:
	## THE ORIGINAL DEFECT. The label carried no autowrap_mode, so a message of ANY length was
	## drawn as a single line. This arm is independent of the exact pixel budget: on the
	## unwrapped label the line count is 1 whatever the text, so it reds for the right reason.
	var msg: String = _long_bug_report_message()
	T.show(_host, msg)
	var ls: Array = _layers()
	assert_eq(ls.size(), 1, "one toast must register exactly one live layer, got %d" % [ls.size()])
	if ls.is_empty():
		return
	var r: Dictionary = _rendered(_pair(ls[0])[0])
	if r.is_empty():
		assert_true(false, "CONTROL: the label must have a theme font to measure")
		return
	assert_gt(r["lines"], 1,
		"a %d-char message must wrap, not render as one line (got %d line(s), %.0f px wide)" % [
			msg.length(), r["lines"], r["w"]])


func test_a_long_message_stays_inside_the_screen() -> void:
	## The half the player sees. Two things have to hold together: no drawn line may be wider
	## than the label's box, and the box itself must sit inside the viewport — a box that fits
	## at x=-200 is not on screen.
	var msg: String = _long_bug_report_message()
	T.show(_host, msg)
	var ls: Array = _layers()
	if ls.is_empty():
		assert_true(false, "a toast must register a live layer")
		return
	var l: Label = _pair(ls[0])[0]
	var r: Dictionary = _rendered(l)
	if r.is_empty():
		assert_true(false, "CONTROL: the label must have a theme font to measure")
		return
	var vp_w: float = _viewport_width()
	assert_lte(l.position.x + l.size.x, vp_w,
		"the label box must end on screen: ends at %.0f of %.0f" % [l.position.x + l.size.x, vp_w])
	assert_gte(l.position.x, 0.0, "and must start on screen, starts at %.0f" % [l.position.x])
	assert_lte(r["w"], l.size.x,
		"and no drawn line may overflow it: widest line %.0f px in a %.0f px box" % [r["w"], l.size.x])


func test_the_toast_below_a_wrapped_one_is_not_printed_through_it() -> void:
	## The fixed-stride half. `stack_offset` was `_active_layers.size() * 48`, which is correct
	## only while every toast is exactly one row tall. Reds if the stack goes back to counting
	## rows instead of summing the heights they used.
	T.show(_host, _long_bug_report_message())
	T.show(_host, "Game Saved ✓")
	var ls: Array = _layers()
	assert_eq(ls.size(), 2, "two toasts must register two live layers, got %d" % [ls.size()])
	if ls.size() < 2:
		return
	var first: Label = _pair(ls[0])[0]
	var r: Dictionary = _rendered(first)
	if r.is_empty():
		assert_true(false, "CONTROL: the label must have a theme font to measure")
		return
	## Measured text bottom, not the Control rect — the rect is not text height.
	var text_bottom: float = first.position.y + r["h"]
	var second_top: float = _pair(ls[1])[0].position.y
	assert_gte(second_top, text_bottom,
		"the next toast must start below the wrapped one's last line: starts %.0f, that line ends %.0f (%d lines)" % [
			second_top, text_bottom, r["lines"]])


func test_the_drop_shadow_follows_the_label_it_shadows() -> void:
	## Two labels per toast, offset by exactly (2, 2). Reds if a future margin change moves one
	## and not the other, which detaches the shadow instead of failing loudly.
	T.show(_host, _long_bug_report_message())
	var ls: Array = _layers()
	if ls.is_empty():
		assert_true(false, "a toast must register a live layer")
		return
	var pair: Array = _pair(ls[0])
	assert_eq(pair.size(), 2, "a toast is a shadow plus a label, got %d label(s)" % [pair.size()])
	if pair.size() != 2:
		return
	## The shadow is the lower of the two by 2px.
	var label: Label = pair[0]
	var shadow: Label = pair[1]
	assert_almost_eq(shadow.position.x - label.position.x, 2.0, 0.01,
		"the shadow must sit 2px right of the label")
	assert_almost_eq(shadow.position.y - label.position.y, 2.0, 0.01,
		"the shadow must sit 2px below the label")
	assert_almost_eq(shadow.size.x, label.size.x, 0.01,
		"and must be the same width, or the two centred texts drift apart")
	assert_eq(shadow.autowrap_mode, label.autowrap_mode,
		"and must wrap the same way, or the shadow renders a different number of lines")
