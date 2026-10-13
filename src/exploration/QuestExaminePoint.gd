extends Area2D
class_name QuestExaminePoint

## A custom quest objective advances ONLY through QuestSystem.notify_flag — notify_talk
## skips type "custom" — so a step with no emitter strands the quest permanently.

const TILE_SIZE: int = 32
const WORDS_PER_SECOND := 4.0   ## a relaxed 240 wpm
const MIN_HOLD_SECONDS := 1.2   ## keeps a short idle_text feeling like a toast
const MAX_HOLD_SECONDS := 10.0  ## stops a pathological row pinning a label on screen
const FADE_SECONDS := 1.2
const TOAST_WIDTH := 300.0
const TOAST_FONT_SIZE := 11
const TOAST_MIN_HEIGHT := 36.0  ## the authored two-line box, now a FLOOR rather than the whole rect
const TOAST_BASELINE_Y := -58.0  ## where the authored rect's top sat; the bottom edge is held here

@export var quest_id: String = ""
@export var flag: String = ""
@export var indicator_text: String = "%s Examine" % InputProfileManager.hint_for_action("ui_accept")
@export var examine_text: String = ""
@export var idle_text: String = ""
@export var glyph_color: Color = Color(0.85, 0.78, 0.5)
## Group mode: 1-based index within a set that must ALL be examined before `flag` fires. 0 = single point.
@export var member_index: int = 0
@export var group_size: int = 0

var _sprite: Sprite2D
var _indicator: Label
var _player_in_zone: bool = false
var _busy: bool = false
var _pulse_t: float = 0.0


func _ready() -> void:
	add_to_group("interactables")
	_setup_sprite()
	_setup_collision()
	_setup_indicator()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _sprite and _is_live():
		_pulse_t += delta * 2.2
		_sprite.modulate.a = 0.72 + 0.28 * abs(sin(_pulse_t))


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "ExamineGlyph"
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var edge := glyph_color.darkened(0.35)
	for a in range(24):
		var t: float = a * TAU / 24.0
		var px: int = 16 + int(round(9.0 * cos(t)))
		var py: int = 16 + int(round(9.0 * sin(t)))
		if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
			img.set_pixel(px, py, edge)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if abs(dx) + abs(dy) <= 4:
				img.set_pixel(16 + dx, 16 + dy, glyph_color if (dx + dy) % 2 == 0 else edge)
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	_sprite.offset = Vector2(0, -4)
	add_child(_sprite)


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 52.0
	col.shape = shape
	col.scale = Vector2(1.0, 1.6)
	add_child(col)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = indicator_text
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-72, -40)
	_indicator.size = Vector2(144, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_indicator.visible = false
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Mode7Prompt.style_interact_prompt(_indicator)
	add_child(_indicator)


## Live only while THIS flag is the current objective's requirement — setting it on a
## later step would consume the notify the step actually needs and strand the quest again.
func _is_live() -> bool:
	var qs = get_node_or_null("/root/QuestSystem")
	if qs == null or quest_id == "" or flag == "":
		return false
	if qs.get_state(quest_id) != "active":
		return false
	# get_objective_index clamps only when objectives is NON-empty, and this runs every frame from _process
	var objectives: Array = qs.get_quest(quest_id).get("objectives", [])
	var idx: int = qs.get_objective_index(quest_id)
	if idx < 0 or idx >= objectives.size():
		return false
	var obj: Dictionary = objectives[idx]
	return obj.get("type", "") == "custom" and obj.get("required_flag", "") == flag


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.has_method("set_can_move"):
		_player_in_zone = true
		_indicator.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body.has_method("set_can_move"):
		_player_in_zone = false
		_indicator.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if TutorialHint.is_any_active():
		return
	var ilm = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm and ilm.is_locked():
		return
	if _player_in_zone and not _busy and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_busy = true
		_examine()
		_busy = false


func _examine() -> void:
	if not _is_live():
		if SoundManager:
			SoundManager.play_ui("menu_error")
		_toast(idle_text)
		return
	var qs = get_node_or_null("/root/QuestSystem")
	if SoundManager:
		SoundManager.play_ui("secret_found")
	var job_line := _job_variant_text(qs)
	if group_size > 0 and member_index > 0 and not _group_complete_after_marking():
		_toast("%s\n\n(%d of %d documented)" % [examine_text, _group_done(), group_size])
		return
	GameState.set_story_flag(flag)
	qs.notify_flag(flag)
	_toast(examine_text if job_line == "" else examine_text + "\n\n" + job_line)


## Marks THIS member and reports whether the whole set is now done.
func _group_complete_after_marking() -> bool:
	GameState.set_story_flag("%s_%d" % [flag, member_index])
	return _group_done() >= group_size


func _group_done() -> int:
	var n: int = 0
	for i in range(1, group_size + 1):
		if GameState.is_story_flag_set("%s_%d" % [flag, i]):
			n += 1
	return n


## The lead job's authored read of THIS point, or "". 16 of these sat in quest data
## rendered by nothing until struktured's "wire / rewrite" ruling.
func _job_variant_text(qs: Node) -> String:
	if qs == null or not qs.has_method("_leader_job_id"):
		return ""
	var job: String = str(qs._leader_job_id())
	if job == "":
		return ""
	var variant = qs.get_quest(quest_id).get("rewards", {}).get("job_variants", {}).get(job, {})
	if not (variant is Dictionary):
		return ""
	## examine_flag scopes the beat to ONE point — a quest with several points would
	## otherwise show its single job read at whichever the player reached first.
	if str(variant.get("examine_flag", "")) != flag:
		return ""
	return str(variant.get("examine_text", ""))


## Seconds a toast stays at full opacity for a line of `word_count` words. A STATIC seam rather
## than an inline expression so a guard can call it with the pack's real word counts instead of
## pinning the spelling of a literal.
static func toast_hold_for(word_count: int) -> float:
	return clampf(float(word_count) / WORDS_PER_SECOND, MIN_HOLD_SECONDS, MAX_HOLD_SECONDS)


## Height the wrapped block needs at TOAST_WIDTH and TOAST_FONT_SIZE, floored at the authored
## two-line box. A STATIC seam so a guard can ask for the real strings' heights without building a
## scene; it takes the font from a throwaway Label because that is where the theme default lives.
static func toast_height_for(text: String) -> float:
	var probe := Label.new()
	var font: Font = probe.get_theme_font("font")
	var h: float = TOAST_MIN_HEIGHT
	if font != null:
		h = maxf(font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_CENTER, TOAST_WIDTH, TOAST_FONT_SIZE).y, TOAST_MIN_HEIGHT)
	probe.free()
	return h


## Where the label's top-left goes. Paired with toast_height_for so the BOTTOM edge lands on the
## authored baseline for every string — a longer line rises away from the player rather than
## covering them. A seam so a guard can assert that pairing against the SHIPPED arithmetic instead
## of re-deriving it (a test that recomputes the formula cannot fail).
static func toast_position_for(text: String) -> Vector2:
	return Vector2(-TOAST_WIDTH / 2.0, TOAST_BASELINE_Y - (toast_height_for(text) - TOAST_MIN_HEIGHT))


func _toast_height(text: String) -> float:
	return toast_height_for(text)


func _toast(text: String) -> void:
	if text == "":
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	## ⛔ FONT OVERRIDE BEFORE `size`, AND `size` BEFORE `add_child`. The height below is measured
	## from the font, so the override has to be in place first or it is measured at the theme
	## default — and a wrapping Label that enters the tree before its width wraps one character per
	## line and caches a minimum the assignment can no longer get under (@cowir-adhoc's JOBS panel).
	lbl.add_theme_font_size_override("font_size", TOAST_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	## ⛔ THE RECT WAS A LIE AND THE PROSE DREW OVER THE WORLD. It was a flat `Vector2(300, 36)` —
	## two lines — while the longest string that reaches here measures 296x80px at this width and
	## font, five lines, +44px past the rect. A Label does not clip by default, so the overflow drew
	## DOWNWARD from y=-58 over the prop being examined and over the player beside it.
	##
	## 🔑 The block is measured and the label GROWS UPWARD: the bottom edge stays where it was
	## authored, so a longer line rises away from the player instead of covering them.
	var height: float = _toast_height(text)
	lbl.size = Vector2(TOAST_WIDTH, height)
	lbl.position = toast_position_for(text)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	## ⛔ THE HOLD IS DERIVED FROM THE TEXT. It was a flat 2.2s with the fade starting at 1.0s, so a
	## toast was gone 3.2s after the press — and the strings that reach here run to 43 words, about
	## 10s of reading at 250 wpm. The player got 1-2.5s of it.
	##
	## ⚠️ THE POPULATION IS THE QUEST EXAMINE POINTS, not the authored pack. I first wrote "35 of the
	## 45 authored examines" here and it was wrong: `data/examine_texts.json` is placed as
	## `ReadableProp` — a paged panel the player dismisses — by BOTH `BaseVillage:904` and
	## `BaseInterior`, so none of those 45 rows ever reaches this renderer. Measured from the live
	## tree: 24 prose strings across 6 maps arrive here, through `examine_text` and `idle_text`.
	##
	## 🔑 4 words/sec is a relaxed 240 wpm. The floor keeps short idle_text feeling like a toast; the
	## ceiling stops a pathological row pinning a label on screen. Nothing is gated on this label
	## (MOUSE_FILTER_IGNORE, no input lock), so a long hold costs the player nothing but a readable
	## line that drifts away on its own.
	var hold: float = toast_hold_for(text.split(" ", false).size())
	var fade: float = FADE_SECONDS
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 20.0, hold + fade)
	tw.tween_property(lbl, "modulate:a", 0.0, fade).set_delay(hold)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
