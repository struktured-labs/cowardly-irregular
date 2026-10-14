extends Control
class_name HowToPlayOverlay

## The full controls-and-systems reference, reachable from anywhere.
##
## The content used to live inside TitleScreen._show_help_overlay(), which made it
## unreachable once a player pressed NEW GAME — the one screen that explains the controls
## was gone for the entire session. Extracted here so the title screen, the Controls menu
## and the pause menu can all show the same text without duplicating it.
##
## Button names resolve against the ATTACHED pad at build time, so a Nintendo-convention
## pad reads "Ⓑ Button — Confirm" rather than the hardcoded Xbox lettering. The autogrind
## block comes from AutogrindInputHelper.grind_reference_rows() for the same reason.
##
## ✅ EVERY FACE CELL IS NOW DERIVED (2026-10-12). Three were Nintendo-only letters -- Battle
## speed "X (top face)", Repeat and Dash "Y (west face)" -- and because the two faces trade letters
## between the families (Nintendo north Ⓧ / west Ⓨ; Xbox north Ⓨ / west Ⓧ) an Xbox player following
## those rows pressed the OTHER of the two controls, in both directions. Speed and Repeat have no
## InputMap action, so they go through `_face_cell_for_index`; Dash has one and uses `_face_cell`.
##
## ⚠️ WHAT IS STILL WRITTEN BY HAND, and is correct that way: "Start / Plus / Options" and
## "Back / Select / Minus / Share" NAME EVERY FAMILY rather than picking one, and the two stick-click
## rows describe a press no family letters. Those need no derivation. The note that used to sit here
## called Start/Back "Nintendo-only" after they had been widened, and attributed "Y (west face)" to a
## north-face button when both its users were WEST -- so the caption census it warned about would
## have been aimed at the wrong rows by the warning itself.
##
## ⚠️ The body is one returned multi-line string, which is why every caption census in the
## fleet skipped this file as a docstring. A guard that reads it must call `build_text()`, not scan
## the source: `test_the_reference_does_not_invert_the_face_buttons` does, per ROW.

signal closed()

const HELP_SCROLL_STEP_PX: float = 48.0

## The authored sizes, named so the Text Size guard can assert they are SCALED rather than raw.
const TITLE_PX: int = 24
const BODY_PX: int = 13
const BODY_BOLD_PX: int = 14
## The shipped content top, kept as a floor so 100% renders exactly as before.
const BASE_CONTENT_Y: float = 75.0
## 6.0 is the gap the authored 75 ENCODES, recovered by measurement: the title measures 34px at
## 100%, so 35 + 34 + 6 == 75. A 9 here put the derived value at 78 and moved every shipped F1
## screenshot down 3px -- caught by the arm that pins the 100% layout, not by reading the diff.
const TITLE_TO_CONTENT_GAP: float = 6.0

var _scroll_target: RichTextLabel = null


## Every key bound to an action, as the reference prints it. The rows below were hand-written
## letters and went INVERSE of the truth when the keyboard moved to the emulator layout
## (2026-09-29) and the shoulders to Q/W (2026-09-25): "L Key — Defer" sent the player to the
## party chat for ten days, and nothing caught it because every controls guard sweeps ACTIONS.
static func _keys(action: String, fallback: String) -> String:
	return TitleScreen.keys_cell(action, fallback)


## The rows whose buttons are BOUND, so they follow a rebind. The field-menu row is first because
## it is the control a new player needs first, and it was named on no screen at all until now.
## Defer and Party Chat get a row each: they share the pad's L shoulder but no longer share a KEY
## (Q vs L), so one row naming one key taught the wrong one for whichever half you were reading.
static func _bound_rows() -> String:
	return "%-17s %-17s R-Click          [color=lime]Open the menu — party, items, quests, save[/color]\n" % [
		_face_cell(OverworldMenu.FIELD_MENU_ACTION, "North"),
		"%s / Escape" % _keys(OverworldMenu.FIELD_MENU_ACTION, OS.get_keycode_string(OverworldMenu.TOGGLE_KEY))] \
		+ "%-17s %-17s —                [color=lime]Run — hold to move 1.7x faster[/color]\n" % [
			_face_cell("dash", "West"), _keys("dash", "Shift")] \
		+ "L Shoulder        %-17s —                Defer (in battle)\n" % _keys("battle_defer", "Q") \
		+ "L Shoulder        %-17s —                Party Chat (in the field)\n" % _keys("party_chat", "L") \
		+ "R Shoulder        %-17s —                Advance (queue action)" % _keys("battle_advance", "W")


## The reference body. Static so a test can pin the VALUE without building a scene tree,
## and so callers can render it into their own container if they'd rather not use ours.
static func build_text() -> String:
	# Guarded because test bootstrap and very early init can reach here before the
	# autoload exists; the fallback letters are only ever seen in that window.
	return TitleScreen.build_confirm_cancel_rows(
		_face_cell("ui_accept", "East"), _face_cell("ui_cancel", "South")) + "\n" + _bound_rows() + """
Start / Plus / Options F5           —                Open Autobattle Editor
Back / Select / Minus / Share F6    —                Toggle Autobattle
%-17s ` (backtick)      —                Battle speed
%-17s Y                 —                [color=lime]Repeat last turn's actions — in battle[/color]
                  F                 —                Cycle party formation (also in the command menu)
L3 Stick Click    L                 —                Battle log: open the full log in battle (also the log panel's button)
R3 Stick Click    F1                —                [color=lime]This screen — from anywhere[/color]
                  F2                —                Quick Save
                  F3                —                Quick Load
                  F12               —                Screenshot
                  F11               —                Live pad readout — button + axis numbers
                  F8                —                [color=lime]Bug report — screenshot + log + save in one file[/color]
                  ─                 Wheel            Scroll lists / change selection

[b][color=yellow]WHILE AUTOGRINDING[/color][/b]
[color=gray]Gamepad          Keyboard          Description[/color]
""" % [_face_cell_for_index(JOY_BUTTON_Y, "North"), _face_cell_for_index(JOY_BUTTON_X, "West")] + AutogrindInputHelper.grind_reference_rows() + """
[b][color=yellow]BATTLE SYSTEM (CTB)[/color][/b]
Each turn you choose: [color=lime]Attack[/color], use [color=cyan]Magic[/color], or strategize with AP.

[color=white]AP (Action Points)[/color] range from -4 to +4.
  [color=lime]Defer (""" + _keys("battle_defer", "Q") + """)[/color]: Skip your turn. Gain +1 AP, take less damage.
  [color=cyan]Advance (""" + _keys("battle_advance", "W") + """)[/color]: Queue extra actions. Each costs 1 AP.
    Queue up to """ + str(BattleManager.ADVANCE_CAP) + """ actions, or """ + str(BattleManager.FULL_BANK_ACTIONS) + """ at a full bank (+""" + str(BattleManager.FULL_BANK_AP) + """ AP) — the last one is free.
    Press Confirm to commit the queue; they all execute at once!

[b][color=yellow]AUTOBATTLE[/color][/b]
This game is designed to be automated!
Open the [color=lime]Autobattle Editor[/color] (Start/Plus/Options, or F5) to write rules:
  IF [condition] THEN [action]
Rules are checked top-to-bottom. First match wins.
Toggle autobattle per character with Select/F6.

[b][color=yellow]PARTY CHAT[/color][/b]
Press [color=lime]L[/color] during exploration when the indicator appears to access
optional story conversations. These are flavor, not required.

[b][color=yellow]TIPS[/color][/b]
- Deferring builds AP for powerful multi-action turns later
- Queue multiple heals or attacks with Advance for burst plays
- Autobattle scripts run automatically — master them to win!
- Visit inns to heal and save your progress
- Check the Bestiary and World Map from the pause menu
"""


func _ready() -> void:
	# set_anchors_preset sets ANCHORS ONLY — under the F1 CanvasLayer the offsets never resolve
	# and the whole overlay measured (0,0), so the backdrop vanished and the text drew naked
	# over live battles (struktured 2026-09-02: "F1 is unreadable ... in battles"). It worked on
	# the title screen because the parent was a sized Control; the port changed the parent type.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vp: Vector2 = get_viewport_rect().size
	size = vp
	z_index = 50

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.1, 0.96)
	add_child(bg)

	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.position = Vector2(60, 35)
	title.add_theme_font_size_override("font_size", TextScale.scaled(TITLE_PX))
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	add_child(title)

	var content := RichTextLabel.new()
	content.bbcode_enabled = true
	content.scroll_active = true
	## ⛔ DERIVED, because a literal 75 collides with the title it sits under. The title is a
	## Label with no size, so its height tracks its font: ~31px at 100% and ~62px at 200% from a
	## y of 35, which reaches 97 and draws across a content top pinned at 75. `maxf` keeps the
	## shipped 100% layout exactly -- at that scale the derived value is below 75 and 75 wins.
	content.position = Vector2(60, maxf(BASE_CONTENT_Y,
		title.position.y + title.get_combined_minimum_size().y + TITLE_TO_CONTENT_GAP))
	content.size = Vector2(vp.x - 120, vp.y - content.position.y - 45)
	content.add_theme_font_size_override("normal_font_size", TextScale.scaled(BODY_PX))
	content.add_theme_font_size_override("bold_font_size", TextScale.scaled(BODY_BOLD_PX))
	content.add_theme_color_override("default_color", Color(0.9, 0.9, 0.95))
	content.text = _content_text()
	add_child(content)
	_scroll_target = content

	## ⛔ EVERY CELL IN THIS OVERLAY BRANCHES ON WHETHER A PAD IS ATTACHED, AND IT WAS BUILT ONCE.
	## `_face_cell` prints "S face" with no pad and "Ⓐ Button" with one; `_close_glyph` swaps a key
	## for a glyph. So a player who opens HOW TO PLAY *because they cannot work out the controls*
	## and then plugs a controller in is left reading the keyboard vocabulary — on the one screen
	## whose entire job is telling them which button to press. Reachable from the title screen,
	## ControlsMenu and GameLoop's F1.
	Input.joy_connection_changed.connect(_on_pad_changed)
	# No grab_focus(): this Control is FOCUS_NONE so it was always refused; input arrives via _input.


## The whole body, in ONE place, so the build and the rebuild cannot print different things.
func _content_text() -> String:
	return build_text() + "\n[color=gray]%s / Escape to close[/color]" % _close_glyph()


## ⚠️ KEEPS THE READING POSITION, AND THE REASON IS NARROWER THAN I FIRST WROTE. I claimed
## "reassigning `text` resets a RichTextLabel to the top" and then measured it:
##     same-length body    value 440 -> 440   preserved, across four frames
##     SHORTER body        value 440 -> 0     max_value shrank and the value CLAMPED
##     back to full        value 0            the clamp is NOT undone when it grows again
## A caption swap ("S face" -> "Ⓐ Button") changes the body's length, so a reader near the bottom
## can be clamped to the top and stay there. Two lines to hold the position is worth it; the
## sweeping claim was not true.
##
## ⛔ NO GUARD ARM COVERS THIS, DELIBERATELY. Headless has no pad, so the rebuilt text is IDENTICAL
## and the clamp cannot occur — an arm asserting the position survives passes whether or not these
## two lines exist. Measured: removing them left the file 6/6 green. An arm that cannot fail is
## worse than no arm, because it reads as cover.
func _on_pad_changed(_device: int, _connected: bool) -> void:
	if not is_inside_tree() or _scroll_target == null or not is_instance_valid(_scroll_target):
		return
	var sb := _scroll_target.get_v_scroll_bar()
	var keep: float = sb.value if sb else 0.0
	_scroll_target.text = _content_text()
	if sb:
		sb.value = keep


## With a pad, the glyph printed on it; with none, the FACE — never one family's letter, which
## is what glyph_for_action returns on an empty device name.
static func _face_cell(action: String, fallback_face: String) -> String:
	if not InputProfileManager:
		return "%s face" % fallback_face
	if Input.get_connected_joypads().is_empty():
		var pos: String = InputProfileManager.face_position_for_action(action)
		return "%s face" % (pos if pos != "" else fallback_face)
	return "%s Button" % InputProfileManager.glyph_for_action(action)


## The INDEX-keyed sibling of _face_cell, for the two controls that have no InputMap action at all:
## battle speed is raw JOY_BUTTON_Y and Repeat is raw JOY_BUTTON_X, so hint_for_action cannot reach
## either. Without this the only way to fill those cells is a hardcoded letter, which is how they
## came to read "X (top face)" and "Y (west face)" -- correct on a Nintendo pad and INVERTED on an
## Xbox one, on the single screen whose job is telling the player which button to press.
static func _face_cell_for_index(button_index: int, fallback_face: String) -> String:
	if not InputProfileManager:
		return "%s face" % fallback_face
	if Input.get_connected_joypads().is_empty():
		return "%s face" % InputProfileManager.FACE_POSITIONS.get(button_index, fallback_face)
	var g: String = InputProfileManager.face_glyph_for_index(button_index)
	if g == "?" or g == "":
		return "%s face" % fallback_face
	return "%s Button" % g


static func _close_glyph() -> String:
	if InputProfileManager:
		return InputProfileManager.hint_for_action("ui_cancel")
	return "X"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_close()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return
	# Help overlay intercept — up/down scroll the long content via controller.
	# Ported verbatim from TitleScreen when this moved out of it: the clamp is a
	# regression fix (gamepad users could scroll past the end), so it travels WITH
	# the behaviour rather than being re-derived here.
	# MenuNav, not a raw read: ui_up/ui_down bind the stick's Y axis and an axis carries no echo
	# flag, so one push scrolled five steps. Measured: dpad 48 px, odd ramp 240, even ramp 192.
	var nav: String = MenuNav.step(event)
	var dy: float = 0.0
	if nav == "ui_down":
		dy = HELP_SCROLL_STEP_PX
	elif nav == "ui_up":
		dy = -HELP_SCROLL_STEP_PX
	if dy != 0.0:
		_scroll_help(dy)
		get_viewport().set_input_as_handled()


func _scroll_help(dy: float) -> void:
	if _scroll_target == null or not is_instance_valid(_scroll_target):
		return
	var sb := _scroll_target.get_v_scroll_bar()
	if sb == null:
		return
	sb.value = clampf(sb.value + dy, sb.min_value, max(sb.min_value, sb.max_value - sb.page))


func _close() -> void:
	# Deliberately silent: the overlay played no close sound before it was extracted from
	# TitleScreen, and adding one would be an unasked change to shipped feel. (The first
	# draft used "menu_back", which resolves in neither the manifest nor SOUNDS — it would
	# have been silence with a broken key behind it. test_sfx_key_orphan_audit caught it.)
	closed.emit()
	queue_free()
