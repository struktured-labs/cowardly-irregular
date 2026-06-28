extends Node
class_name QuestTracker

## QuestTracker — one-line objective text at top-left of screen.
## Driven by story flags in GameState. Shows current goal.
## Updates automatically when story flags change.

var _canvas: CanvasLayer
var _label: Label
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
	{"flag": "rat_king_defeated", "text": "Find the portal to the next world (south)"},
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
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	_label.clip_text = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_label)

	_update_objective()


func _update_objective() -> void:
	var best_text = OBJECTIVES[0]["text"]  # Default objective

	for entry in OBJECTIVES:
		var flag = entry["flag"]
		if flag == "":
			best_text = entry["text"]
		elif _is_flag_set(flag):
			best_text = entry["text"]

	if best_text != _current_objective:
		_current_objective = best_text
		_label.text = "► " + best_text
		# Resize background to fit text
		_bg.offset_right = _label.offset_left + _label.get_theme_font("font").get_string_size(
			_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			_label.get_theme_font_size("font_size")).x + 20 if _label.get_theme_font("font") else 350


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		_update_objective()


func update() -> void:
	_update_objective()


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
