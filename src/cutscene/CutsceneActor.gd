extends Node2D
class_name CutsceneActor

## Staged-cutscene puppet: a director-owned sprite that walks/faces/emotes
## in the live world (Chrono Trigger style). Built from the 4x4 overworld
## sheets (party jobs + NPC archetypes); procedural placeholder fallback.

## Sheet row order matches WanderingNPC/overworld.png layout, NOT OverworldNPC's enum.
enum Dir { DOWN = 0, LEFT = 1, RIGHT = 2, UP = 3 }

const FRAME_SIZE: int = 32
const BUBBLE_MAX_WIDTH: float = 128.0
const WALK_FRAMES: int = 4
## Seconds per walk frame AT THE DEFAULT SPEED. Kept as the anchor rather than the rule: the rule is
## the stride below, and this is the number that makes today's default-speed walks unchanged.
const ANIM_SPEED: float = 0.12
## ⛔ A FIXED frame time makes the STRIDE track the authored speed, so a faster walk skates.
## Measured 2026-09-16 (px of travel per animation frame, the thing that makes feet look planted):
##   this actor, fixed 0.12s   default 120 -> 14.4 px    ·   authored 160 -> 19.2 px
##   OverworldPlayer, SAME sheets, same 4-frame cycle    ->  19.2 px at ANY speed, because it
##                                                           divides its frame time by the speed
## Two different gaits for one character, and 12 authored walks split 10/2 across them. The stride is
## now invariant here too, anchored at DEFAULT_WALK_SPEED so the 10 default walks are untouched and
## only the two authored-160 walks change (they stop out-striding the other ten).
## 📌 Anchoring at the PLAYER's 19.2 instead would leave those two alone and liven the other ten —
## same mechanism, opposite subset. That is a look call and it is struktured's, not mine.
const STRIDE_PER_FRAME_PX: float = DEFAULT_WALK_SPEED * ANIM_SPEED
const DEFAULT_WALK_SPEED: float = 120.0
## Safe monochrome glyphs only — no emoji font fallback exists (recon: tofu risk).
const EMOTE_GLYPHS: Dictionary = {
	"exclaim": "!", "question": "?", "double_exclaim": "‼",
	"ellipsis": "…", "heart": "♥", "note": "♪",
	"anger": "‼", "sweat": "…",
}

var actor_id: String = ""
var _sprite: Sprite2D
var _frames: Dictionary = {}
## The frame this actor's sheet was actually cut at. FRAME_SIZE is the convention; a sheet may differ,
## and the slicer now measures it — so everything positioned off "the frame" must read THIS, not the
## constant. Without it my own slicer fix left two halves disagreeing: the cut derived, the emote
## guessed, so a 48px sheet would be sliced correctly and then have its emote 8px inside its head.
var _frame_px: int = FRAME_SIZE
var _facing: int = Dir.DOWN
var _anim_time: float = 0.0
var _anim_frame: int = 0
var _walking: bool = false
## The speed the current walk is running at; the animation divides by it so the stride stays put.
var _walk_speed: float = DEFAULT_WALK_SPEED
## Fast-forward rate for the CURRENT walk. It scales the tween and the cycle TOGETHER — a
## speed-scaled tween covers more ground per second and the legs have to cover it too.
var _walk_rate: float = 1.0
var _walk_tween: Tween = null
var _walk_target: Vector2 = Vector2.INF
var _emote_label: Label = null
var _bubble: Control = null
var _shake_tween: Tween = null


## spec: {kind:"party"|"npc", job|archetype:String, facing:String}
static func build(id: String, spec: Dictionary) -> CutsceneActor:
	var a := CutsceneActor.new()
	a.actor_id = id
	a.name = "CutsceneActor_%s" % id
	a._sprite = Sprite2D.new()
	a._sprite.name = "Sprite"
	a.add_child(a._sprite)
	var sheet_path: String = ""
	if str(spec.get("kind", "npc")) == "party":
		# Party puppets wear the current world's form, same resolution as the live player.
		# (All staged scenes are W1 today; the post-battle cache caveat is filed against
		# the shelved puppet-ending and bites nothing that exists.)
		sheet_path = HybridSpriteLoader.job_asset_path(
			str(spec.get("job", "fighter")), "overworld", HybridSpriteLoader.current_world_suffix())
	else:
		sheet_path = HybridSpriteLoader.npc_overworld_path(str(spec.get("archetype", "young_man")))
	if not a._load_sheet(sheet_path):
		# The fallback fills the SAME _frames dict a real load does, so nothing
		# downstream can tell a missing sheet from a present one — the scene
		# plays with a flat coloured box standing in for the character. Say so.
		push_warning("[cutscene] actor '%s' has no sheet at %s — rendering a PLACEHOLDER box, not the character" % [id, sheet_path])
		a._build_placeholder()
	a.set_facing_name(str(spec.get("facing", "down")))
	a.z_index = 5
	return a


## Slice a 4-row x WALK_FRAMES grid into AtlasTextures keyed "row_col". The frame size is DERIVED
## from the sheet, not assumed: FRAME_SIZE is the convention (159 of 159 overworld sheets are 128x128
## at 32px today) and a 48px sheet sliced at 32 would have shown a quarter of a figure, silently,
## because the guard above only required the sheet to be BIG ENOUGH. Same class as cowir-sprites'
## per-sheet `fps` (2026-09-16): the manifest declares per sheet and the consumer assumed a constant.
func _load_sheet(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var tex: Texture2D = load(path)
	if tex == null:
		return false
	var frame: int = frame_size_of(tex)
	if frame <= 0:
		return false
	_frame_px = frame
	for row in 4:
		for col in WALK_FRAMES:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(col * frame, row * frame, frame, frame)
			_frames["%d_%d" % [row, col]] = at
	_apply_frame()
	return true


## The square frame this sheet is cut into: 4 rows of WALK_FRAMES columns. 0 when the sheet cannot be
## a grid of square frames at all — a sheet that is merely the WRONG size is refused rather than
## mis-sliced, which is what the old "big enough" test allowed.
static func frame_size_of(tex: Texture2D) -> int:
	if tex == null:
		return 0
	var h: int = tex.get_height()
	var w: int = tex.get_width()
	if h <= 0 or w <= 0 or h % 4 != 0:
		return 0
	var frame: int = h / 4
	if frame <= 0 or w < frame * WALK_FRAMES:
		return 0
	return frame


## Headless/unknown-id fallback so a bad spec never crashes a cutscene.
func _build_placeholder() -> void:
	_frame_px = FRAME_SIZE  # the placeholder IS the convention, so say so rather than inherit a stale one
	var img := Image.create(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.55, 0.8, 0.9))
	var t := ImageTexture.create_from_image(img)
	for row in 4:
		for col in WALK_FRAMES:
			_frames["%d_%d" % [row, col]] = t
	_apply_frame()


func _apply_frame() -> void:
	if _sprite and _frames.has("%d_%d" % [_facing, _anim_frame]):
		_sprite.texture = _frames["%d_%d" % [_facing, _anim_frame]]


func _process(delta: float) -> void:
	if not _walking:
		return
	_anim_time += delta
	if _anim_time >= frame_time_for(_walk_speed * _walk_rate):
		_anim_time = 0.0
		_anim_frame = (_anim_frame + 1) % WALK_FRAMES
		_apply_frame()


## Awaited walk in GLOBAL space: faces the motion vector, animates the cycle.
func walk_to(target_global: Vector2, speed: float = DEFAULT_WALK_SPEED) -> void:
	var delta_v := target_global - global_position
	if delta_v.length() < 1.0 or speed <= 0.0 or not is_inside_tree():
		global_position = target_global
		stand()
		return
	face_vector(delta_v)
	_walking = true
	_walk_speed = speed
	_walk_rate = 1.0  # a new walk starts at normal rate; a button held through the last one must not carry
	_walk_target = target_global
	_walk_tween = create_tween()
	_walk_tween.tween_property(self, "global_position", target_global, delta_v.length() / speed)
	# Polled, not `await tween.finished`: a snap_walk (skip) or a freed target must release this, never hang it.
	while _walking and is_instance_valid(_walk_tween) and _walk_tween.is_valid() and _walk_tween.is_running():
		await get_tree().process_frame
	stand()


## Skip contract: land on the mark now and release the walk_to that is polling.
func snap_walk() -> void:
	if is_instance_valid(_walk_tween) and _walk_tween.is_valid():
		_walk_tween.kill()
	_walk_tween = null
	if _walk_target != Vector2.INF and is_inside_tree():
		global_position = _walk_target
	_walk_target = Vector2.INF
	stand()


func stand() -> void:
	_walking = false
	_anim_frame = 0
	_apply_frame()


func face_vector(v: Vector2) -> void:
	if absf(v.x) > absf(v.y):
		_facing = Dir.RIGHT if v.x > 0 else Dir.LEFT
	else:
		_facing = Dir.DOWN if v.y > 0 else Dir.UP
	_apply_frame()


func set_facing_name(dir_name: String) -> void:
	match dir_name:
		"up": _facing = Dir.UP
		"left": _facing = Dir.LEFT
		"right": _facing = Dir.RIGHT
		_: _facing = Dir.DOWN
	_apply_frame()


## `world_pos` is GLOBAL (authored [x,y] marks and other puppets' global_position both are) — subtracting the local `position` faced the wrong way on any offset stage.
func face_toward(world_pos: Vector2) -> void:
	face_vector(world_pos - global_position)


## Hurry (or slow) the walk in flight. The director calls this from its poll loop so a held confirm
## speeds a staged walk the same way it speeds every other hold — and because the cycle divides by
## `speed * rate`, the legs keep up instead of skating at 4x.
func set_walk_rate(rate: float) -> void:
	_walk_rate = maxf(0.01, rate)
	if _walk_tween and is_instance_valid(_walk_tween) and _walk_tween.is_valid():
		_walk_tween.set_speed_scale(_walk_rate)


## Seconds per walk frame at `speed`, so travel-per-frame is STRIDE_PER_FRAME_PX whatever the speed.
## A non-positive speed keeps the anchor rather than dividing by it.
static func frame_time_for(speed: float) -> float:
	if speed <= 0.0:
		return ANIM_SPEED
	return STRIDE_PER_FRAME_PX / speed


## Classic above-head emote glyph (quest-marker Label pattern: wide + centered).
func show_emote(kind: String, duration: float = 1.0) -> void:
	clear_emote()
	_emote_label = Label.new()
	_emote_label.text = EMOTE_GLYPHS.get(kind, str(kind))
	_emote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emote_label.position = Vector2(-40, -float(_frame_px) * scale.y * 0.5 - 22.0)
	_emote_label.size = Vector2(80, 22)
	_emote_label.add_theme_font_size_override("font_size", 18)
	_emote_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	_emote_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_emote_label.add_theme_constant_override("shadow_offset_x", 1)
	_emote_label.add_theme_constant_override("shadow_offset_y", 1)
	_emote_label.z_index = 20
	add_child(_emote_label)
	if duration > 0.0 and is_inside_tree():
		var tween := create_tween()
		tween.tween_property(_emote_label, "position:y", _emote_label.position.y - 6.0, 0.15)
		tween.tween_interval(maxf(0.0, duration - 0.15))
		tween.tween_callback(clear_emote)


func clear_emote() -> void:
	if _emote_label and is_instance_valid(_emote_label):
		_emote_label.queue_free()
	_emote_label = null


## CT-style line over the head — an aside while the scene keeps moving; the panel stays the voice for lines that matter.
func say(text: String, duration: float = 1.5) -> void:
	clear_bubble()
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	sb.border_color = Color(0.95, 0.95, 0.75, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(minf(BUBBLE_MAX_WIDTH, maxf(36.0, text.length() * 5.5)), 0)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_constant_override("line_spacing", -6)  # the fallback font chain inflates line height; pull wrapped lines together
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	panel.add_child(label)
	panel.z_index = 21
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.size = panel.get_combined_minimum_size()
	var head_y := -float(_frame_px) * scale.y * 0.5 - 8.0
	panel.position = Vector2(-panel.size.x * 0.5, head_y - panel.size.y)
	_bubble = panel
	if duration > 0.0 and is_inside_tree():
		var tween := create_tween()
		tween.tween_interval(duration)
		tween.tween_callback(clear_bubble)


func clear_bubble() -> void:
	if _bubble and is_instance_valid(_bubble):
		_bubble.queue_free()
	_bubble = null


## CT-style shudder — fear, cold, laughter. Jitters the SPRITE's offset, never `position`, so a walk in flight is not fought; self-clears. Instant no-op off-tree.
func shake(duration: float = 0.4, intensity: float = 2.0) -> void:
	stop_shake()
	if not is_inside_tree() or _sprite == null or duration <= 0.0:
		return
	var tween := create_tween()
	for i in maxi(1, int(duration / 0.04)):
		tween.tween_property(_sprite, "offset", Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity)), 0.04)
	tween.tween_property(_sprite, "offset", Vector2.ZERO, 0.04)
	tween.tween_callback(stop_shake)
	_shake_tween = tween


func is_shaking() -> bool:
	return _shake_tween != null and is_instance_valid(_shake_tween) and _shake_tween.is_valid() and _shake_tween.is_running()


## Ends a shudder now (a skip, or a scene teardown) and puts the sprite back exactly where it was.
func stop_shake() -> void:
	if _shake_tween and is_instance_valid(_shake_tween) and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	if _sprite and is_instance_valid(_sprite):
		_sprite.offset = Vector2.ZERO


## Small surprise-hop; awaited. Instant no-op off-tree (headless). `duration` is per-hop cycle time (default 0.2s = 0.1 up + 0.1 down); prior signature ignored JSON `duration` silently (cadence-8 audit finding).
func hop(times: int = 1, duration: float = 0.2) -> void:
	if not is_inside_tree():
		return
	var half: float = maxf(0.05, duration * 0.5)
	var tween := create_tween()
	for i in maxi(1, times):
		tween.tween_property(self, "position:y", position.y - 6.0, half)
		tween.tween_property(self, "position:y", position.y, half)
	# Polled for the same reason as walk_to: a freed puppet must release the awaiting step, never hang it.
	while is_instance_valid(tween) and tween.is_valid() and tween.is_running():
		await get_tree().process_frame
