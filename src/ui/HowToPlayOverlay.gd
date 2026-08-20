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
## pad reads "Ⓑ Button — Confirm" rather than the hardcoded Xbox lettering.

signal closed()

const HELP_SCROLL_STEP_PX: float = 48.0

var _scroll_target: RichTextLabel = null


## The reference body. Static so a test can pin the VALUE without building a scene tree,
## and so callers can render it into their own container if they'd rather not use ours.
static func build_text() -> String:
	# Guarded because test bootstrap and very early init can reach here before the
	# autoload exists; the fallback letters are only ever seen in that window.
	var g_ok: String = "A"
	var g_no: String = "B"
	if InputProfileManager:
		g_ok = InputProfileManager.glyph_for_action("ui_accept")
		g_no = InputProfileManager.glyph_for_action("ui_cancel")
	return TitleScreen.build_confirm_cancel_rows(g_ok, g_no) + """
L Shoulder        L Key             —                Defer / Party Chat
R Shoulder        R Key             —                Advance (queue action)
Start (Plus)      F5                —                Open Autobattle Editor
Back (Minus)      F6                —                Toggle Autobattle
                  F2                —                Quick Save
                  F3                —                Quick Load
                  F12               —                Screenshot
                  ─                 Wheel            Scroll lists / change selection

[b][color=yellow]BATTLE SYSTEM (CTB)[/color][/b]
Each turn you choose: [color=lime]Attack[/color], use [color=cyan]Magic[/color], or strategize with AP.

[color=white]AP (Action Points)[/color] range from -4 to +4.
  [color=lime]Defer (L)[/color]: Skip your turn. Gain +1 AP, take less damage.
  [color=cyan]Advance (R)[/color]: Queue extra actions. Each costs 1 AP.
    Queue up to 4 actions, then they all execute at once!

[b][color=yellow]AUTOBATTLE[/color][/b]
This game is designed to be automated!
Open the [color=lime]Autobattle Editor[/color] (Start/F5) to write rules:
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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 50
	var vp: Vector2 = get_viewport_rect().size

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.1, 0.96)
	add_child(bg)

	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.position = Vector2(60, 35)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	add_child(title)

	var content := RichTextLabel.new()
	content.bbcode_enabled = true
	content.scroll_active = true
	content.position = Vector2(60, 75)
	content.size = Vector2(vp.x - 120, vp.y - 120)
	content.add_theme_font_size_override("normal_font_size", 13)
	content.add_theme_font_size_override("bold_font_size", 14)
	content.add_theme_color_override("default_color", Color(0.9, 0.9, 0.95))
	content.text = build_text() + "\n[color=gray]%s / Escape to close[/color]" % _close_glyph()
	add_child(content)
	_scroll_target = content

	grab_focus()


static func _close_glyph() -> String:
	if InputProfileManager:
		return InputProfileManager.glyph_for_action("ui_cancel")
	return "B"


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
	var dy: float = 0.0
	if event.is_action_pressed("ui_down"):
		dy = HELP_SCROLL_STEP_PX
	elif event.is_action_pressed("ui_up"):
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
