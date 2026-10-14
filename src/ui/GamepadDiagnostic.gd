extends Control
class_name GamepadDiagnostic

var _label: RichTextLabel
var _active: bool = false

## ⛔ WAS A RAW `18`, THE ONLY RAW RichTextLabel FONT LEFT IN `src/ui`. This overlay is advertised to
## the player in the F1 controls reference and in ControlsMenu, so a player who turned Text Size up
## reached the one screen that ignored the setting.
##
## ⛔ AND SCALING ALONE WOULD HAVE MADE IT WORSE, which is why `scroll_active` changes with it. The
## label is PRESET_FULL_RECT with scrolling OFF, so anything past the viewport was simply not drawn
## — no scrollbar, no clipping indicator, nothing. Content is a title, 5 lines per connected pad,
## and one row per joypad-bound action (16 in project.godot, plus whatever engine-default ui_*
## actions the live InputMap carries), so at the default it sits within ~100px of a 720px viewport
## with ONE pad — and a second pad, or any Text Size above 100%, pushes rows off the bottom where
## nothing could reach them. The action list is the whole point of the screen.
const BASE_FONT_SIZE := 18

## Scroll step, in lines of the CURRENT font — so the step grows with the text rather than becoming
## a crawl at 200%. Three keeps a d-pad hold responsive without skipping a device block.
const SCROLL_LINES := 3


## Every action the PROJECT declares, not a hardcoded six. The old list showed 6 of 14 and two of
## those six are dead (camera_rotate_*, no handler anywhere), so a tester chasing "my A button does
## nothing" got no ui_accept row at all — on a pad whose whole failure mode is mode switches moving
## button indices. Parsed once and cached; this runs every frame while the overlay is open.
static var _cached_actions: Array[String] = []


## Actions a gamepad can actually press. Read from InputMap, never from project.godot: the
## exporter packs the project file as `project.binary`, so `res://project.godot` is ABSENT from
## every pack and this returned EMPTY in all shipped builds while being correct in the editor.
##
## ⛔ RETURNS THE LIVE STATIC, NOT A COPY — TREAT IT AS READ-ONLY. An Array is a reference, so
## `project_actions().sort()` or `.append(...)` mutates process-wide state that nothing ever
## invalidates, and no assignment exists anywhere for the next person to grep. Both callers today
## only iterate or read `.size()`.
##
## ⚠️ NOT `.duplicate()`, DELIBERATELY: `_process` calls this EVERY FRAME while the overlay is
## open, and avoiding that allocation is the entire reason the cache exists. Where a copy would
## defeat the design, this note is the only protection there is — which is why it sits at the
## definition rather than beside the one caller that happens to be safe.
static func project_actions() -> Array[String]:
	if not _cached_actions.is_empty():
		return _cached_actions
	for action in InputMap.get_actions():
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				_cached_actions.append(String(action))
				break
	_cached_actions.sort()
	return _cached_actions


func _ready() -> void:
	visible = false
	z_index = 100
	set_anchors_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	_label = RichTextLabel.new()
	_label.set_anchors_preset(PRESET_FULL_RECT)
	_label.bbcode_enabled = true
	_label.scroll_active = true
	_label.add_theme_font_size_override("normal_font_size", TextScale.scaled(BASE_FONT_SIZE))
	add_child(_label)


## ⚠️ THE SCROLL READ IS `MenuNav.step`, NOT a raw `is_action_pressed`: ui_up/ui_down bind the left
## stick's Y axis, an axis carries no echo flag, and every value change on one push reads as pressed
## — measured elsewhere as five steps for one nudge. Buttons pass through unlatched.
##
## 📌 CONSUMED ONLY WHEN IT SCROLLS. The F11 toggle deliberately does not consume, as before; and
## while the overlay is closed this handler touches nothing, so it cannot steal a direction from the
## game underneath.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		_active = not _active
		visible = _active
		return

	if not _active:
		return
	var nav: String = MenuNav.step(event)
	if nav == "ui_down":
		_scroll_by(SCROLL_LINES)
		get_viewport().set_input_as_handled()
	elif nav == "ui_up":
		_scroll_by(-SCROLL_LINES)
		get_viewport().set_input_as_handled()


## Clamped to the last full page, not to max_value: scrolling into empty space below the content
## reads as a broken screen.
func _scroll_by(lines: int) -> void:
	if _label == null or not is_instance_valid(_label):
		return
	var sb := _label.get_v_scroll_bar()
	if sb == null:
		return
	var step: float = float(lines * TextScale.scaled(BASE_FONT_SIZE))
	sb.value = clampf(sb.value + step, sb.min_value, max(sb.min_value, sb.max_value - sb.page))


## ⛔ GATED ON `_active`, WHICH `_process` ALREADY WAS AND THIS WAS NOT. GameLoop adds this overlay
## to EVERY session (`:401`, unconditional), so these prints ran in every shipped build whether or
## not anyone opened the overlay. Measured in struktured's 2026-10-12 session: 1,889 `[GAMEPAD]`
## lines — a line per unhandled pad button, per stick sample past 0.1, per mouse move past 5px.
##
## ⚠️ THE COST IS HIS CRASH TRACE, NOT DISK. `user://logs` is a 5-file FIFO, so a session that
## spends ~12% of its lines on input telemetry crowds out the thing the fleet mines those logs for.
## Every `print` persists regardless of the file-logging setting.
##
## 📌 WHAT THIS TRADES, SAID RATHER THAN HIDDEN: a tester who hits a pad problem and only THEN
## presses F11 no longer has the preceding events in the log. Nothing documented that as the intent
## — `_process` guards and this did not, which is an asymmetry rather than a design — but if the
## retroactive capture WAS the point, reverse this with that reason recorded.
func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventJoypadMotion:
		var e = event as InputEventJoypadMotion
		if abs(e.axis_value) > 0.1:
			print("[GAMEPAD] JoyMotion dev=%d axis=%d val=%.3f" % [e.device, e.axis, e.axis_value])
	elif event is InputEventJoypadButton and event.pressed:
		var e = event as InputEventJoypadButton
		print("[GAMEPAD] JoyButton dev=%d btn=%d" % [e.device, e.button_index])
	elif event is InputEventMouseMotion:
		var e = event as InputEventMouseMotion
		if e.relative.length() > 5.0:
			print("[GAMEPAD] MouseMotion rel=%s" % str(e.relative))


func _process(_delta: float) -> void:
	if not _active:
		return

	## ⚠️ NAMES NO FACE LETTER, DELIBERATELY. "D-pad" and "arrows" are family-neutral, so this caption
	## cannot invert on an Xbox or PlayStation pad the way a hardcoded A/B does — the failure that put
	## six wrong glyphs in shipped captions between .308 and .332. A derived glyph is not available
	## here anyway: ui_up/ui_down are not in REMAPPABLE_ACTIONS, so hint_for_action cannot reach them.
	var text = "[b][color=yellow]GAMEPAD DIAGNOSTIC (F11 to close · D-pad/arrows scroll)[/color][/b]\n\n"

	for dev in Input.get_connected_joypads():
		var name = Input.get_joy_name(dev)
		var guid = Input.get_joy_guid(dev)
		var known = Input.is_joy_known(dev)
		text += "[color=cyan]Device %d: %s[/color]\n" % [dev, name]
		text += "  GUID: %s  Known: %s\n" % [guid, "YES" if known else "NO"]

		text += "  [color=lime]Axes:[/color] "
		for ax in range(8):
			var val = Input.get_joy_axis(dev, ax)
			if abs(val) > 0.05:
				text += "[color=white]%d=%.2f[/color] " % [ax, val]
			else:
				text += "[color=gray]%d=%.2f[/color] " % [ax, val]
		text += "\n"

		text += "  [color=lime]Buttons:[/color] "
		for btn in range(20):
			if Input.is_joy_button_pressed(dev, btn):
				text += "[color=yellow]%d[/color] " % btn
		text += "\n\n"

	text += "[color=cyan]Input Actions:[/color]\n"
	for action in project_actions():
		if InputMap.has_action(action):
			var strength = Input.get_action_strength(action)
			var color = "yellow" if strength > 0.1 else "gray"
			text += "  [color=%s]%s: %.2f[/color]\n" % [color, action, strength]

	text += "\n[color=cyan]Mouse velocity:[/color] %s\n" % str(Input.get_last_mouse_velocity())

	## ⚠️ HOLDS THE READING POSITION ACROSS A PER-FRAME REWRITE, and the reason is narrow: assigning
	## `text` PRESERVES the scroll value for a same-height body and CLAMPS it to 0 when the body
	## SHRINKS, and the clamp is not undone when it grows back (measured in HowToPlayOverlay). Line
	## COUNT here is fixed, so the default case is stable — but at large Text Size a value changing
	## width ("0=0.00" -> "0=-1.00") can rewrap a row and shrink the height for one frame.
	##
	## ⛔ NO GUARD ARM COVERS THESE TWO LINES, DELIBERATELY: headless has no pad and no mouse motion,
	## so the rebuilt text is byte-identical every frame and the clamp cannot occur. An arm asserting
	## the position survives would pass whether or not this code exists, which reads as cover.
	var sb := _label.get_v_scroll_bar()
	var keep: float = sb.value if sb else 0.0
	_label.text = text
	if sb:
		sb.value = keep
