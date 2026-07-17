extends Node2D
class_name CutsceneActor

## Staged-cutscene puppet: a director-owned sprite that walks/faces/emotes
## in the live world (Chrono Trigger style). Built from the 4x4 overworld
## sheets (party jobs + NPC archetypes); procedural placeholder fallback.

## Sheet row order matches WanderingNPC/overworld.png layout, NOT OverworldNPC's enum.
enum Dir { DOWN = 0, LEFT = 1, RIGHT = 2, UP = 3 }

const FRAME_SIZE: int = 32
const WALK_FRAMES: int = 4
const ANIM_SPEED: float = 0.12
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
var _facing: int = Dir.DOWN
var _anim_time: float = 0.0
var _anim_frame: int = 0
var _walking: bool = false
var _emote_label: Label = null


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
		sheet_path = "res://assets/sprites/jobs/%s/overworld.png" % str(spec.get("job", "fighter"))
	else:
		sheet_path = "res://assets/sprites/npcs/%s/overworld.png" % str(spec.get("archetype", "young_man"))
	if not a._load_sheet(sheet_path):
		a._build_placeholder()
	a.set_facing_name(str(spec.get("facing", "down")))
	a.z_index = 5
	return a


## Slice the 128x128 4x4 grid into 16 AtlasTextures keyed "row_col".
func _load_sheet(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var tex: Texture2D = load(path)
	if tex == null or tex.get_width() < FRAME_SIZE * WALK_FRAMES or tex.get_height() < FRAME_SIZE * 4:
		return false
	for row in 4:
		for col in WALK_FRAMES:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(col * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
			_frames["%d_%d" % [row, col]] = at
	_apply_frame()
	return true


## Headless/unknown-id fallback so a bad spec never crashes a cutscene.
func _build_placeholder() -> void:
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
	if _anim_time >= ANIM_SPEED:
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
	var tween := create_tween()
	tween.tween_property(self, "global_position", target_global, delta_v.length() / speed)
	await tween.finished
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


func face_toward(world_pos: Vector2) -> void:
	face_vector(world_pos - position)


## Classic above-head emote glyph (quest-marker Label pattern: wide + centered).
func show_emote(kind: String, duration: float = 1.0) -> void:
	clear_emote()
	_emote_label = Label.new()
	_emote_label.text = EMOTE_GLYPHS.get(kind, str(kind))
	_emote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emote_label.position = Vector2(-40, -float(FRAME_SIZE) * scale.y * 0.5 - 22.0)
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


## Small surprise-hop; awaited. Instant no-op off-tree (headless). `duration` is per-hop cycle time (default 0.2s = 0.1 up + 0.1 down); prior signature ignored JSON `duration` silently (cadence-8 audit finding).
func hop(times: int = 1, duration: float = 0.2) -> void:
	if not is_inside_tree():
		return
	var half: float = maxf(0.05, duration * 0.5)
	var tween := create_tween()
	for i in maxi(1, times):
		tween.tween_property(self, "position:y", position.y - 6.0, half)
		tween.tween_property(self, "position:y", position.y, half)
	await tween.finished
