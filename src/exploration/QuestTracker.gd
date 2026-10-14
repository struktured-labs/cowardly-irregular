extends Node
class_name QuestTracker

## QuestTracker — one-line objective text at top-left of screen.
## Driven by story flags in GameState. Shows current goal.
## Updates automatically when story flags change.

var _canvas: CanvasLayer
var _label: Label
var _side_label: Label
var _bg: ColorRect
var _current_objective: String = ""
var _poll_timer: float = 0.0
const POLL_INTERVAL: float = 2.0  # Check for flag changes every 2 seconds

## Objective definitions: flag → objective text (checked in order, first match wins)
## Later entries override earlier ones (progression order).
## Tick 281: 5 dead flag references replaced with their real forms
## (same bug class as ticks 271/278/280). _update_objective does
## dual-namespace lookup (story_flags OR cutscene_flag_X game_constants)
## so bare forms like `world1_mordaine_defeated` resolve via the
## cutscene_flag_ prefix path.
const OBJECTIVES: Array = [
	# W1 Medieval progression
	{"flag": "", "text": "Explore Harmonia Village to the west"},
	{"flag": "prologue_complete", "text": "Speak with Elder Theron in Harmonia"},
	{"flag": "chapter1_complete", "text": "Investigate the Whispering Cave (northwest)"},
	{"flag": "chapter2_complete", "text": "Descend deeper into the Whispering Cave"},
	{"flag": "chapter3_complete", "text": "Defeat the Cave Rat King"},
	# 2026-09-06: the portal line here predated the spine gate — post-Rat-King the real goal
	# is the four dragon seals, and the portal only exists after Mordaine anyway.
	{"flag": "rat_king_defeated", "text": "Break the four dragon seals to open Castle Harmonia"},
	# Last-match wins, so this sits after the seals line and before Mordaine. Rat King alone
	# still says "break the seals"; all four dragons (the castle's real gate) replace it.
	# Same strings the quest log already uses, so the banner and the log name one goal.
	{"all_flags": ["rat_king_defeated", "fire_dragon_defeated", "ice_dragon_defeated", "lightning_dragon_defeated", "shadow_dragon_defeated"], "text": "Defeat the Chancellor's Warden"},
	{"flag": "castle_warden_defeated", "text": "Confront Chancellor Mordaine in Castle Harmonia"},
	# Tick 281: w1_boss_defeated had no writers — Mordaine's real flag.
	{"flag": "world1_mordaine_defeated", "text": "Enter the portal to the Mundane Sprawl"},
	# W2 Suburban
	{"flag": "w2_entered", "text": "Explore the Mundane Sprawl"},
	# Tick 281: w2_dungeon_cleared had no writers — world2_complete is the real clear flag.
	{"flag": "world2_complete", "text": "Find the portal to the Clockwork Dominion"},
	# W3 Steampunk
	{"flag": "w3_entered", "text": "Explore the Clockwork Dominion"},
	{"flag": "world3_complete", "text": "Find the portal to the Assembly Line"},
	# W4 Industrial
	{"flag": "w4_entered", "text": "Explore the Assembly Line"},
	{"flag": "world4_complete", "text": "Find the portal to the Source Layer"},
	# W5 Digital
	{"flag": "w5_entered", "text": "Explore the Source Layer"},
	{"flag": "world5_complete", "text": "Find the portal to the Remainder"},
	# W6 Abstract
	{"flag": "w6_entered", "text": "Reach the Vertex"},
]


func setup(parent: Node) -> void:
	add_to_group(OverworldMinimap.HUD_GROUP)
	_canvas = CanvasLayer.new()
	_canvas.name = "QuestTracker"
	_canvas.layer = 85
	parent.add_child(_canvas)

	_bg = ColorRect.new()
	_bg.color = Color(0.0, 0.0, 0.0, 0.35)
	_bg.anchor_left = 0.0
	_bg.anchor_right = 0.0
	_bg.anchor_top = 0.0
	_bg.anchor_bottom = 0.0
	_bg.offset_left = 12
	_bg.offset_top = 12
	_bg.offset_right = 350
	_bg.offset_bottom = 36
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_bg)

	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_right = 0.0
	_label.anchor_top = 0.0
	_label.anchor_bottom = 0.0
	_label.offset_left = 16
	_label.offset_top = 13
	_label.offset_right = 346
	_label.offset_bottom = 35
	_label.add_theme_font_size_override("font_size", TextScale.scaled(MAIN_FONT_SIZE))
	_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	_label.clip_text = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_label)

	# Side-quest line below the main objective (first active side quest).
	_side_label = Label.new()
	_side_label.anchor_left = 0.0
	_side_label.anchor_right = 0.0
	_side_label.anchor_top = 0.0
	_side_label.anchor_bottom = 0.0
	_side_label.offset_left = 16
	_side_label.offset_top = 37
	_side_label.offset_right = 346
	_side_label.offset_bottom = 57
	_side_label.add_theme_font_size_override("font_size", TextScale.scaled(SIDE_FONT_SIZE))
	_side_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_side_label.clip_text = false
	## ⛔ WRAPS rather than ELLIPSIZES, and the choice is forced by a shipped guard, not preference.
	## `test_quest_chicken_regression:167-169` asserts `_side_label.text` CONTAINS "[3/7]" and that
	## the count precedes "Corner all seven" — because QuestLog CLIPS the same string and the tally
	## must survive being cut. Wrapping is visual and leaves `.text` untouched; ellipsizing or
	## inserting a newline would red it (@cowir-autogrind lost a fix to exactly that contiguity break).
	_side_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side_label.visible = false
	_canvas.add_child(_side_label)

	_update_objective()

	# Signal-driven quest feedback (2026-07-02): objective_advanced /
	# quest_state_changed had NO feedback consumer — mid-quest talk
	# steps (Phil) advanced invisibly and the 2s poll caught up in
	# silence. Now: instant refresh + side-line pulse + soft chime.
	var qs = get_node_or_null("/root/QuestSystem")
	if qs != null:
		qs.objective_advanced.connect(_on_quest_progress)
		qs.quest_state_changed.connect(_on_quest_progress)


func _on_quest_progress(_a = null, _b = null) -> void:
	if _label == null:
		return
	_update_objective()
	if SoundManager:
		# str() guards against int (objective_advanced sends int idx); only quest_state_changed sends "complete" (cowir-sfx msg 2160)
		SoundManager.play_ui("quest_complete" if str(_b) == "complete" else "soft_chime")
	if _side_label != null and _side_label.visible:
		_side_label.modulate = Color(1.6, 1.4, 0.6)
		var tw := create_tween()
		tw.tween_property(_side_label, "modulate", Color.WHITE, 0.6)


## ⛔ 424px OF QUEST PROSE DREW OVER THE WORLD WITH NO PLATE, AT THE SHIPPED DEFAULT. Measured on the
## built node with the chicken quest at 3/7 (the worst authored line, and the only objective that
## receives BOTH runtime annotations):
##
##   side label   box 330   built rect 668.0 x 20.0   font 11   122 chars   +338px PAST ITS BOX
##   bg plate     x 12..260 (248 wide, shrink-wrapped to the MAIN line at _update_objective)
##   side text spans x=16..684, its plate ends at x=260  ->  424px unbacked
##
## ⚠️ AND IDENTICAL AT ALL FIVE PRESETS — font 12/11 at 80% through 200% — so there were TWO defects
## here and only one was the Text Size census item: the overflow is a DEFAULT-SETTING defect.
##
## 🔑 THE PLATE MECHANISM WAS ALREADY RIGHT AND ALREADY FONT-AWARE. `_update_objective` derives
## `offset_right` from the main line's MEASURED text at its ACTUAL font size, so the main line is
## self-correcting once scaled. The defect is that it considered ONLY `_label`. This extends that
## derivation to the wider of the two lines rather than replacing it.
const LABEL_LEFT := 16.0
const LABEL_RIGHT := 346.0          ## both labels' authored right edge
const WRAP_W := LABEL_RIGHT - LABEL_LEFT   ## 330 — the side line's bounded wrap width
const PLATE_LEFT := 12.0
const PLATE_PAD := 20.0             ## the authored right margin inside the plate
const MAIN_FONT_SIZE := 12
const SIDE_FONT_SIZE := 11
const MAIN_TOP := 13.0
const SIDE_TOP := 37.0
const PLATE_BOTTOM_COLLAPSED := 36.0
const PLATE_BOTTOM_PAD := 1.0       ## 58 - (37 + 20) at the authored two-line size
## WORD_SMART's own break rule. @cowir-autogrind measured that the DEFAULT flags
## (MANDATORY|WORD_BOUND) count fewer lines than a WORD_SMART label draws, because ADAPTIVE is what
## splits a token too wide for its box — so a height derived with the default can be too small.
const WRAP_FLAGS := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE


## The plate's right edge and bottom, and the side line's wrapped height. STATIC so a guard can ask
## for the arithmetic over the real authored strings without building the HUD.
##
## Collapsed (no side quest) returns the authored numbers unchanged at the authored font, so the
## main-line-only state — the one a player sees most — does not move at 100%.
static func plate_metrics(main_text: String, side_text: String, side_shown: bool,
		main_px: int, side_px: int) -> Dictionary:
	var font: Font = ThemeDB.fallback_font
	var out: Dictionary = {
		"plate_right": PLATE_LEFT + WRAP_W + PLATE_PAD,
		"plate_bottom": PLATE_BOTTOM_COLLAPSED,
		"side_h": SIDE_TOP + 20.0 - SIDE_TOP,
	}
	if font == null:
		return out
	var main_w: float = font.get_string_size(main_text, HORIZONTAL_ALIGNMENT_LEFT, -1, main_px).x
	var right: float = LABEL_LEFT + main_w + PLATE_PAD
	if not side_shown:
		out["plate_right"] = right
		out["plate_bottom"] = PLATE_BOTTOM_COLLAPSED
		out["side_h"] = 0.0
		return out
	## The side line WRAPS, so its width is bounded and its height is what grows. Measured with the
	## flags the node actually draws with, not the default.
	var side_h: float = font.get_multiline_string_size(
		side_text, HORIZONTAL_ALIGNMENT_LEFT, WRAP_W, side_px, -1, WRAP_FLAGS).y
	out["side_h"] = maxf(20.0, side_h)
	## The plate covers the WIDER of the two lines: the main line's measured text, or the side
	## line's bounded wrap width. Never narrower than the authored collapsed plate.
	out["plate_right"] = maxf(right, LABEL_LEFT + WRAP_W + PLATE_PAD)
	out["plate_bottom"] = SIDE_TOP + float(out["side_h"]) + PLATE_BOTTOM_PAD
	return out


func _update_objective() -> void:
	var best_text = OBJECTIVES[0]["text"]  # Default objective

	for entry in OBJECTIVES:
		if _entry_reached(entry):
			best_text = entry["text"]

	if best_text != _current_objective:
		_current_objective = best_text
		_label.text = "> " + best_text

	_update_side_quest_line()
	_apply_plate()


## One place that sizes the plate, from both lines. The old derivation lived inline in
## `_update_objective` and ran ONLY when the main text changed — so a side line appearing or growing
## never resized the plate at all.
func _apply_plate() -> void:
	if _bg == null or _label == null or _side_label == null:
		return
	var m: Dictionary = plate_metrics(_label.text, _side_label.text, _side_label.visible,
		_label.get_theme_font_size("font_size"), _side_label.get_theme_font_size("font_size"))
	_bg.offset_right = float(m["plate_right"])
	_bg.offset_bottom = float(m["plate_bottom"])
	_side_label.size.y = float(m["side_h"])


## First active side quest's current objective, shown under the main line.
func _update_side_quest_line() -> void:
	if _side_label == null:
		return
	var qs = get_node_or_null("/root/QuestSystem")
	if qs == null:
		_side_label.visible = false
		return
	var active: Array = qs.get_active()
	if active.is_empty():
		_side_label.visible = false
		return
	var qid: String = _pick_tracked_quest(active, str(qs.last_progressed_quest_id))
	var q: Dictionary = qs.get_quest(qid)
	var idx: int = qs.get_objective_index(qid)
	var objectives: Array = q.get("objectives", [])
	var desc: String = ""
	if idx < objectives.size():
		desc = objectives[idx].get("description", "")
		if qs.has_method("fetch_progress"):
			var fp: Vector2i = qs.fetch_progress(objectives[idx])
			if fp.y > 0:
				desc += "  [%d/%d]" % [fp.x, fp.y]
		# Same saved tally as the quest log, in front of the description so the fixed-width HUD keeps it.
		desc = QuestChicken.annotate_objective(desc, objectives[idx])
	_side_label.text = "* %s — %s" % [q.get("title", qid), desc]
	_side_label.visible = true


## The quest the player most recently touched wins the tracker line;
## pre-fix it pinned active[0] (file-load order), so accepting a
## second quest never changed the HUD until the first completed.
static func _pick_tracked_quest(active: Array, last_progressed: String) -> String:
	if last_progressed != "" and last_progressed in active:
		return last_progressed
	return str(active[0])


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		_update_objective()


func update() -> void:
	_update_objective()


## A single flag, or every flag in all_flags. Empty all_flags never matches, so a blank list cannot skip the spine.
func _entry_reached(entry: Dictionary) -> bool:
	var all_flags: Variant = entry.get("all_flags", null)
	if all_flags is Array:
		if (all_flags as Array).is_empty():
			return false
		for flag in all_flags:
			if not _is_flag_set(str(flag)):
				return false
		return true
	var flag := str(entry.get("flag", ""))
	if flag == "":
		return true
	return _is_flag_set(flag)


## Tick 336: delegate to GameState.is_story_flag_set (canonical
## dual-namespace helper added in tick 335). Pre-fix this file had
## an inline 2-way OR check (story_flags + cutscene_flag_<bare>) that
## missed the bare-name-in-game_constants case the QuestLog and
## WanderingNPC variants both covered. So a flag set ONLY in
## game_constants[bare] (legacy / debug toggle) made this tracker
## stay on the prior objective text even when QuestLog / WanderingNPC
## already advanced. The delegation pulls all three dual checks onto
## the GameState helper for a single source of truth.
func _is_flag_set(flag: String) -> bool:
	if flag == "":
		return false
	if GameState.has_method("is_story_flag_set"):
		return GameState.is_story_flag_set(flag)
	return GameState.get_story_flag(flag) \
		or GameState.game_constants.get("cutscene_flag_" + flag, false) \
		or GameState.game_constants.get(flag, false)


## The block the tracker draws in (both lines), for HUD that must keep off it (TutorialHint, ObjectiveArrow).
func reserved_rect() -> Rect2:
	if _canvas == null or not _canvas.visible or _bg == null or not _bg.is_visible_in_tree():
		return Rect2()
	var r := _bg.get_rect()
	if _side_label != null and _side_label.is_visible_in_tree() and _side_label.text != "":
		r = r.merge(_side_label.get_rect())
	return r
