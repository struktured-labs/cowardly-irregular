extends Control
class_name RebalanceHistoryPanel

## RebalanceHistoryPanel — read-only diegetic surface for the daemon's
## applied[] history. Per the directive memo: "the player can see
## what the AI changed for me last hour" — that transparency IS the
## innovation, not hidden auto-tuning.
##
## Shows all proposals that have left pending[]:
##   - status='applied'           → auto-applied (or force-applied)
##   - status='applied_no_change' → LLM said curve looks fine
##   - status='dismissed'         → player reviewed and rejected
##   - status='rejected'          → daemon refused (unsafe constant)
##
## Read-only. The review panel (tick 49) handles new proposals; this
## is the audit trail.

signal closed()

const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)
const PANEL_COLOR := Color(0.12, 0.12, 0.18)
const BORDER_LIGHT := Color(0.6, 0.6, 0.7)
const BORDER_SHADOW := Color(0.08, 0.08, 0.12)
const TEXT_COLOR := Color(0.95, 0.95, 0.95)
const HEADER_COLOR := Color(0.85, 0.75, 0.40)
const DIM_COLOR := Color(0.65, 0.65, 0.70)
const APPLIED_COLOR := Color(0.45, 0.85, 0.50)
const DISMISSED_COLOR := Color(0.85, 0.55, 0.45)
const NEUTRAL_COLOR := Color(0.7, 0.7, 0.75)
const REJECTED_COLOR := Color(0.95, 0.45, 0.40)

var _list_label: RichTextLabel
var _empty_label: Label
var _modifiers_label: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_render_history()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vp: Vector2 = get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		vp = Vector2(1280, 720)
	var panel_w: float = min(720.0, vp.x - 80)
	var panel_h: float = min(520.0, vp.y - 80)
	var panel_x: float = (vp.x - panel_w) / 2.0
	var panel_y: float = (vp.y - panel_h) / 2.0

	var border_light := ColorRect.new()
	border_light.color = BORDER_LIGHT
	border_light.position = Vector2(panel_x - 3, panel_y - 3)
	border_light.size = Vector2(panel_w + 6, panel_h + 6)
	add_child(border_light)
	var border_shadow := ColorRect.new()
	border_shadow.color = BORDER_SHADOW
	border_shadow.position = Vector2(panel_x - 1, panel_y - 1)
	border_shadow.size = Vector2(panel_w + 4, panel_h + 4)
	add_child(border_shadow)
	var panel_bg := ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.position = Vector2(panel_x, panel_y)
	panel_bg.size = Vector2(panel_w, panel_h)
	add_child(panel_bg)

	var header := Label.new()
	header.text = "REBALANCE HISTORY"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", HEADER_COLOR)
	header.position = Vector2(panel_x + 20, panel_y + 16)
	header.size = Vector2(panel_w - 40, 28)
	add_child(header)

	var note := Label.new()
	note.text = "What the daemon has proposed since you started — most recent first."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", DIM_COLOR)
	note.position = Vector2(panel_x + 20, panel_y + 46)
	note.size = Vector2(panel_w - 40, 18)
	add_child(note)

	# tick 56: "Currently Active" snapshot section. Shows game_constants
	# that diverged from their daemon-applied defaults (1.0). Without
	# this, the player sees the history of CHANGES but not the current
	# steady-state of MULTIPLIERS in effect.
	_modifiers_label = RichTextLabel.new()
	_modifiers_label.bbcode_enabled = true
	_modifiers_label.add_theme_color_override("default_color", TEXT_COLOR)
	_modifiers_label.add_theme_font_size_override("normal_font_size", 12)
	_modifiers_label.position = Vector2(panel_x + 24, panel_y + 76)
	_modifiers_label.size = Vector2(panel_w - 48, 56)
	_modifiers_label.scroll_active = false
	_modifiers_label.fit_content = false
	add_child(_modifiers_label)

	_list_label = RichTextLabel.new()
	_list_label.bbcode_enabled = true
	_list_label.add_theme_color_override("default_color", TEXT_COLOR)
	_list_label.add_theme_font_size_override("normal_font_size", 13)
	_list_label.position = Vector2(panel_x + 24, panel_y + 138)
	_list_label.size = Vector2(panel_w - 48, panel_h - 186)
	_list_label.scroll_active = true
	_list_label.fit_content = false
	add_child(_list_label)

	_empty_label = Label.new()
	_empty_label.text = "No applied history yet. Defeat a boss or wipe a few times (with auto-rebalance ON) to start seeing entries here."
	_empty_label.add_theme_font_size_override("font_size", 13)
	_empty_label.add_theme_color_override("font_color", DIM_COLOR)
	_empty_label.position = Vector2(panel_x + 40, panel_y + (panel_h / 2.0) - 20)
	_empty_label.size = Vector2(panel_w - 80, 40)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty_label)

	var hint := Label.new()
	hint.text = "[B/Esc] Close"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", TEXT_COLOR)
	hint.position = Vector2(panel_x + 24, panel_y + panel_h - 28)
	hint.size = Vector2(panel_w - 48, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)


func _render_history() -> void:
	_render_active_modifiers()
	var daemon = _get_daemon()
	if daemon == null:
		_list_label.visible = false
		_empty_label.text = "(no rebalance daemon found)"
		_empty_label.visible = true
		return
	var applied: Array = daemon.applied
	if applied.is_empty():
		_list_label.visible = false
		_empty_label.visible = true
		return
	_list_label.visible = true
	_empty_label.visible = false

	var lines: Array[String] = []
	# Most recent first — reverse iterate.
	for i in range(applied.size() - 1, -1, -1):
		var entry: Dictionary = applied[i]
		lines.append(_format_entry(entry, daemon))
	_list_label.text = "\n\n".join(lines)


## Render a single applied[] entry. Format:
##   [tag] <when>: <summary>
##   verdict / confidence / forced? — secondary line
##
## Color the [tag] by status so the audit trail reads at a glance.
func _format_entry(entry: Dictionary, daemon) -> String:
	var status: String = str(entry.get("status", "?"))
	var ts: int = int(entry.get("ts", 0))
	var trigger: String = str(entry.get("trigger", "?"))
	var verdict: String = str(entry.get("verdict", ""))
	var confidence: float = float(entry.get("confidence", 0.0))
	var force_applied: bool = bool(entry.get("force_applied", false))

	var tag: String
	var color: Color
	match status:
		"applied":
			tag = "[APPLIED]"
			color = APPLIED_COLOR
			if force_applied:
				tag = "[APPLIED-MANUAL]"
		"applied_no_change":
			tag = "[NO-CHANGE]"
			color = NEUTRAL_COLOR
		"dismissed":
			tag = "[DISMISSED]"
			color = DISMISSED_COLOR
		"rejected":
			tag = "[REJECTED]"
			color = REJECTED_COLOR
		_:
			tag = "[%s]" % status.to_upper()
			color = DIM_COLOR

	var when_str: String = _format_when(ts)
	var summary: String = ""
	if daemon.has_method("summarize_applied"):
		summary = daemon.summarize_applied(entry)
	if summary == "":
		summary = "(no summary)"

	var line1: String = "[color=#%s]%s[/color] %s  •  trigger=%s" % [
		color.to_html(false),
		tag,
		when_str,
		trigger]
	var line2: String = "  %s" % summary
	var line3: String = ""
	if verdict != "":
		line3 = "  verdict=%s  confidence=%.0f%%" % [verdict, confidence * 100.0]
	return "\n".join([line1, line2, line3] if line3 != "" else [line1, line2])


## Render the active-modifiers snapshot. Reads GameState.game_constants
## directly so the header is always live — even constants that were
## modified outside the daemon (Scriptweaver, debug edits) surface here.
func _render_active_modifiers() -> void:
	if _modifiers_label == null:
		return
	var daemon = _get_daemon()
	var watch_list: Array = ["exp_multiplier", "gold_multiplier", "encounter_rate"]
	if daemon != null and "ALLOWED_CONSTANTS" in daemon:
		watch_list = daemon.ALLOWED_CONSTANTS
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not ("game_constants" in gs):
		_modifiers_label.text = "[color=#%s]Currently Active:[/color] (GameState not available)" % HEADER_COLOR.to_html(false)
		return
	var parts: Array[String] = []
	for c in watch_list:
		if not gs.game_constants.has(c):
			continue
		var v: float = float(gs.game_constants[c])
		# Only surface DIVERGENT values — 1.0 is the default, no clutter.
		if abs(v - 1.0) < 0.001:
			continue
		var pct: int = int(round((v - 1.0) * 100.0))
		var sign: String = "+" if pct >= 0 else ""
		var color: Color = APPLIED_COLOR if pct >= 0 else DISMISSED_COLOR
		parts.append("[color=#%s]%s %s%d%%[/color]" % [
			color.to_html(false), str(c), sign, pct])
	var header: String = "[color=#%s]Currently Active:[/color] " % HEADER_COLOR.to_html(false)
	if parts.is_empty():
		_modifiers_label.text = header + "[color=#%s](all defaults)[/color]" % DIM_COLOR.to_html(false)
	else:
		_modifiers_label.text = header + "    ".join(parts)


func _format_when(ts: int) -> String:
	if ts <= 0:
		return "(unknown when)"
	var now: int = int(Time.get_unix_time_from_system())
	var delta: int = now - ts
	if delta < 60:
		return "%d sec ago" % delta
	elif delta < 3600:
		return "%d min ago" % (delta / 60)
	elif delta < 86400:
		return "%d hr ago" % (delta / 3600)
	else:
		return "%d days ago" % (delta / 86400)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()


func _get_daemon():
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return null
	if not ("rebalance_daemon" in gs):
		return null
	return gs.rebalance_daemon
