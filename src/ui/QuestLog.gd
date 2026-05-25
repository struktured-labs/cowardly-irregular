extends Control
class_name QuestLog

## QuestLog — full-screen submenu showing story progress.
## Grouped by world chapter with completed/active/upcoming objectives.
## Opened from OverworldMenu.

signal closed()

const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = RetroPanel.BORDER_LIGHT
const BORDER_SHADOW = RetroPanel.BORDER_SHADOW
const HEADER_COLOR = Color(0.85, 0.78, 0.45)
const ACTIVE_COLOR = Color(0.95, 0.9, 0.5)
const COMPLETE_COLOR = Color(0.45, 0.8, 0.45)
const LOCKED_COLOR = Color(0.35, 0.35, 0.4)
const TEXT_COLOR = Color(0.9, 0.9, 0.9)

## World chapters with objective progression
const CHAPTERS: Array = [
	{
		"title": "Chapter 1 — The Medieval Realm",
		"world_flag": "",
		"objectives": [
			{"flag": "", "text": "Explore Harmonia Village to the west"},
			{"flag": "prologue_complete", "text": "Speak with Elder Theron in Harmonia"},
			{"flag": "chapter1_complete", "text": "Investigate the Whispering Cave"},
			{"flag": "chapter2_complete", "text": "Descend deeper into the Whispering Cave"},
			{"flag": "chapter3_complete", "text": "Defeat the Cave Rat King"},
			{"flag": "rat_king_defeated", "text": "Find the portal to the next world"},
			{"flag": "w1_boss_defeated", "text": "Enter the Mundane Sprawl"},
		]
	},
	{
		"title": "Chapter 2 — The Mundane Sprawl",
		"world_flag": "w2_entered",
		"objectives": [
			{"flag": "w2_entered", "text": "Explore the suburban neighborhood"},
			{"flag": "w2_boss_defeated", "text": "Find the portal to the Clockwork Dominion"},
		]
	},
	{
		"title": "Chapter 3 — The Clockwork Dominion",
		"world_flag": "w3_entered",
		"objectives": [
			{"flag": "w3_entered", "text": "Explore the steampunk city"},
			{"flag": "w3_boss_defeated", "text": "Find the portal to the Assembly Line"},
		]
	},
	{
		"title": "Chapter 4 — The Assembly Line",
		"world_flag": "w4_entered",
		"objectives": [
			{"flag": "w4_entered", "text": "Navigate the industrial complex"},
			{"flag": "w4_boss_defeated", "text": "Find the portal to the Source Layer"},
		]
	},
	{
		"title": "Chapter 5 — The Source Layer",
		"world_flag": "w5_entered",
		"objectives": [
			{"flag": "w5_entered", "text": "Explore the digital realm"},
			{"flag": "w5_boss_defeated", "text": "Find the portal to the Remainder"},
		]
	},
	{
		"title": "Chapter 6 — The Remainder",
		"world_flag": "w6_entered",
		"objectives": [
			{"flag": "w6_entered", "text": "Reach the Vertex"},
		]
	},
]

var _scroll_offset: int = 0
var _max_visible_lines: int = 0
var _total_lines: int = 0
## Set true after the first _build_ui run so subsequent rebuilds (triggered
## by scroll-key input) honor the user's manual scroll instead of snapping
## back to the active objective every keypress.
var _initial_scroll_applied: bool = false


func _ready() -> void:
	call_deferred("_build_ui")


func setup() -> void:
	pass


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0:
		vp_size = Vector2(640, 480)

	# Background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Title bar
	var title = Label.new()
	title.text = "QUEST LOG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 12)
	title.size = Vector2(vp_size.x, 30)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	add_child(title)

	# Separator line
	var sep = ColorRect.new()
	sep.color = BORDER_LIGHT
	sep.position = Vector2(20, 44)
	sep.size = Vector2(vp_size.x - 40, 1)
	add_child(sep)

	# "Next:" banner — surface the active objective right at the top so
	# players don't have to scroll past completed chapters to figure out
	# what to do next. Addresses user feedback "I can't figure out what
	# the hell to actually do." Falls back gracefully if all chapters are
	# complete or none are unlocked.
	var next_text = _find_active_objective_text()
	var banner_h: float = 0.0
	if next_text != "":
		var next_bg = ColorRect.new()
		next_bg.name = "NextBannerBG"
		next_bg.color = Color(0.14, 0.16, 0.22, 0.92)
		next_bg.position = Vector2(20, 52)
		next_bg.size = Vector2(vp_size.x - 40, 28)
		add_child(next_bg)
		var next_label = Label.new()
		next_label.name = "NextBanner"
		next_label.text = "▶ Next: " + next_text
		next_label.position = Vector2(32, 56)
		next_label.size = Vector2(vp_size.x - 64, 20)
		next_label.add_theme_font_size_override("font_size", 13)
		next_label.add_theme_color_override("font_color", ACTIVE_COLOR)
		add_child(next_label)
		banner_h = 36.0

	# Quest content area
	var content_y: float = 56.0 + banner_h
	var content_h: float = vp_size.y - 100.0 - banner_h
	var line_height: float = 20.0
	_max_visible_lines = int(content_h / line_height)

	var lines: Array = _build_quest_lines()
	_total_lines = lines.size()

	# On first open, snap the scroll viewport so the active objective lands
	# near the top — saves the player from scrolling past completed chapters
	# in late-game runs. Subsequent rebuilds (driven by scroll input) skip
	# this so the user's manual scroll position is preserved.
	if not _initial_scroll_applied:
		var active_idx = _find_active_line_index(lines)
		if active_idx > -1:
			# Leave ~2 lines of context above the active objective so the
			# chapter header is still visible.
			_scroll_offset = maxi(0, active_idx - 2)
		_initial_scroll_applied = true

	# Clamp scroll
	_scroll_offset = clampi(_scroll_offset, 0, maxi(0, _total_lines - _max_visible_lines))

	# Render visible lines
	var y = content_y
	for i in range(_scroll_offset, mini(_scroll_offset + _max_visible_lines, lines.size())):
		var line = lines[i]
		var lbl = Label.new()
		lbl.text = line["text"]
		lbl.position = Vector2(line["indent"], y)
		lbl.size = Vector2(vp_size.x - line["indent"] - 20, line_height)
		lbl.add_theme_font_size_override("font_size", line["size"])
		lbl.add_theme_color_override("font_color", line["color"])
		lbl.clip_text = true
		add_child(lbl)
		y += line_height

	# Scroll indicators
	if _scroll_offset > 0:
		var up_arrow = Label.new()
		up_arrow.text = "▲ More"
		up_arrow.position = Vector2(vp_size.x - 80, content_y - 2)
		up_arrow.add_theme_font_size_override("font_size", 10)
		up_arrow.add_theme_color_override("font_color", LOCKED_COLOR)
		add_child(up_arrow)

	if _scroll_offset + _max_visible_lines < _total_lines:
		var dn_arrow = Label.new()
		dn_arrow.text = "▼ More"
		dn_arrow.position = Vector2(vp_size.x - 80, vp_size.y - 44)
		dn_arrow.add_theme_font_size_override("font_size", 10)
		dn_arrow.add_theme_color_override("font_color", LOCKED_COLOR)
		add_child(dn_arrow)

	# Footer
	var footer = Label.new()
	footer.text = "↑↓ / Wheel: Scroll    B / RClick: Close"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.position = Vector2(0, vp_size.y - 28)
	footer.size = Vector2(vp_size.x, 20)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", LOCKED_COLOR)
	add_child(footer)

	# Mouse: right-click to close. Added LAST so it sits on top of all
	# previously-added children (PASS lets clicks bubble to interactive
	# items; right-click consumed here).
	MenuMouseHelper.add_right_click_cancel(self, func() -> void:
		closed.emit()
		queue_free())


func _build_quest_lines() -> Array:
	var lines: Array = []
	var found_active: bool = false

	for ch_idx in range(CHAPTERS.size()):
		var chapter = CHAPTERS[ch_idx]
		var world_flag = chapter["world_flag"]
		var chapter_unlocked = (world_flag == "" or GameState.get_story_flag(world_flag))

		# Chapter header
		if chapter_unlocked:
			var all_complete = _is_chapter_complete(chapter)
			var header_color = COMPLETE_COLOR if all_complete else HEADER_COLOR
			var prefix = "✓ " if all_complete else ""
			lines.append({
				"text": prefix + chapter["title"],
				"indent": 24.0,
				"size": 15,
				"color": header_color,
			})

			# Objectives
			for obj in chapter["objectives"]:
				var flag = obj["flag"]
				var is_complete = (flag == "" and ch_idx == 0) or (flag != "" and GameState.get_story_flag(flag))

				if is_complete:
					lines.append({
						"text": "  ✓  " + obj["text"],
						"indent": 40.0,
						"size": 13,
						"color": COMPLETE_COLOR,
					})
				elif not found_active:
					# First incomplete = active
					found_active = true
					lines.append({
						"text": "  ►  " + obj["text"],
						"indent": 40.0,
						"size": 14,
						"color": ACTIVE_COLOR,
					})
				else:
					lines.append({
						"text": "  ·  " + obj["text"],
						"indent": 40.0,
						"size": 13,
						"color": LOCKED_COLOR,
					})

			# Spacer between chapters
			lines.append({"text": "", "indent": 0.0, "size": 10, "color": LOCKED_COLOR})
		else:
			# Locked chapter
			lines.append({
				"text": "? " + chapter["title"],
				"indent": 24.0,
				"size": 15,
				"color": LOCKED_COLOR,
			})
			lines.append({"text": "", "indent": 0.0, "size": 10, "color": LOCKED_COLOR})

	return lines


func _is_chapter_complete(chapter: Dictionary) -> bool:
	for obj in chapter["objectives"]:
		if obj["flag"] != "" and not GameState.get_story_flag(obj["flag"]):
			return false
	return true


func _find_active_line_index(lines: Array) -> int:
	## Returns the index of the first line painted in ACTIVE_COLOR (the "►"
	## current-objective line), or -1 if every objective is complete or
	## locked. Used by _build_ui to auto-scroll the viewport on initial open.
	for i in range(lines.size()):
		if lines[i].get("color") == ACTIVE_COLOR:
			return i
	return -1


func _find_active_objective_text() -> String:
	## Walks the chapter list in story order and returns the first
	## incomplete objective in an unlocked chapter — the "current"
	## objective the player should be pursuing. Empty string if the
	## game is fully complete or no chapter is yet unlocked.
	for chapter in CHAPTERS:
		var world_flag = chapter["world_flag"]
		var chapter_unlocked = (world_flag == "" or GameState.get_story_flag(world_flag))
		if not chapter_unlocked:
			continue
		for obj in chapter["objectives"]:
			var flag = obj["flag"]
			# Chapter-1 first objective has empty flag and is always "complete"
			# (it's the implicit starting state), so skip it here.
			if flag == "":
				continue
			if not GameState.get_story_flag(flag):
				return str(obj["text"])
	return ""


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Bug fix (2026-04-30): removed ui_accept from the close-conditions
	# (non-standard — Enter is usually confirm, not close). Holding cancel
	# and accept are both echo-guarded so we don't rebuild the UI / play
	# the close cue at echo rate.
	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_back")) and not event.is_echo():
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("ui_up") and not event.is_echo():
		if _scroll_offset > 0:
			_scroll_offset -= 3
			_build_ui()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") and not event.is_echo():
		if _scroll_offset + _max_visible_lines < _total_lines:
			_scroll_offset += 3
			_build_ui()
		get_viewport().set_input_as_handled()
	# Mouse wheel scrolling
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _scroll_offset > 0:
				_scroll_offset = maxi(0, _scroll_offset - 3)
				_build_ui()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _scroll_offset + _max_visible_lines < _total_lines:
				_scroll_offset += 3
				_build_ui()
			get_viewport().set_input_as_handled()
