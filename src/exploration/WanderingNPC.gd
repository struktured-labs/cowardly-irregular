extends Area2D
class_name WanderingNPC

## WanderingNPC — ambient NPC that walks a short patrol path on the overworld.
## Shows one line of dialogue when the player is nearby.
## Makes the world feel lived-in between towns.

const TILE_SIZE: int = 32
const WANDER_SPEED: float = 40.0
const PAUSE_MIN: float = 2.0
const PAUSE_MAX: float = 5.0
const ANIM_FPS: float = 4.0

@export var npc_name: String = "Traveler"
@export var dialogue: String = "The road stretches on..."
@export var sprite_color: Color = Color(0.6, 0.5, 0.4)
## Optional sprite archetype override. If empty, the NPC uses procedural
## 1-frame chibi (tinted by sprite_color). Available archetype sheets:
## old_man, old_woman, young_man, young_woman, child, guard, merchant, scholar.
@export var sprite_archetype: String = ""

## Story-aware dialogue hints — checked in order, last matching flag wins.
## Format: [{"flag": "story_flag", "text": "dialogue"}, ...]
## If empty, falls back to static dialogue.
var dialogue_hints: Array = []

var _sprite: Sprite2D
var _label: Label
var _player_nearby: bool = false
var _npc_dialogue: Node = null  # NPCDialogue instance for proper dialogue boxes
var _dynamic_conv: DynamicConversation = null  # LLM-driven conversation, lazy-init
var _in_conversation: bool = false

## NPC theme/portrait for dialogue boxes (defaults to "mysterious")
@export var dialogue_theme: String = "mysterious"
@export var dialogue_portrait: String = "mysterious"

## LLM dynamic dialogue opt-in (per docs/llm-integration-design.md:157).
## Mirrors OverworldNPC: only NPCs with `dynamic = true` AND a non-empty
## `persona` participate in the LLM-driven DynamicConversation path.
## Default OFF — ambient wanderers stay on the static single-line path.
@export var dynamic: bool = false
@export_multiline var persona: String = ""

# Patrol state
var _patrol_points: Array[Vector2] = []
var _current_target: int = 0
var _paused: bool = false
var _pause_timer: float = 0.0
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _facing_right: bool = true

## Cache of (direction, frame) → texture for archetype sprites.
## Direction: 0=down, 1=left, 2=right, 3=up (sheet row order).
## Frame: 0..3 (4-frame walk cycle).
var _archetype_frames: Dictionary = {}
var _current_dir: int = 0  # last computed direction (for sheet row pick)
const ARCHETYPE_FRAME_W: int = 32
const ARCHETYPE_FRAME_H: int = 32


func _ready() -> void:
	_setup_sprite()
	_setup_collision()
	_setup_label()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func set_patrol(points: Array[Vector2]) -> void:
	_patrol_points = points
	if _patrol_points.size() > 0:
		global_position = _patrol_points[0]


func _process(delta: float) -> void:
	if _patrol_points.size() < 2:
		return

	if _paused:
		_pause_timer -= delta
		if _pause_timer <= 0:
			_paused = false
			_current_target = (_current_target + 1) % _patrol_points.size()
		return

	var target = _patrol_points[_current_target]
	var dir = (target - global_position)
	var dist = dir.length()

	if dist < 4.0:
		# Reached target — pause
		_paused = true
		_pause_timer = randf_range(PAUSE_MIN, PAUSE_MAX)
		return

	dir = dir.normalized()
	global_position += dir * WANDER_SPEED * delta
	_facing_right = dir.x > 0

	# Pick the dominant axis to set sheet row (0=down, 1=left, 2=right, 3=up).
	if abs(dir.x) > abs(dir.y):
		_current_dir = 2 if dir.x > 0 else 1
	else:
		_current_dir = 0 if dir.y > 0 else 3

	# Walk animation
	_anim_timer += delta * ANIM_FPS
	if _anim_timer >= 1.0:
		_anim_timer -= 1.0
		# 4-frame cycle for archetype path, 2-frame "bob" for procedural.
		var cycle = 4 if not _archetype_frames.is_empty() else 2
		_anim_frame = (_anim_frame + 1) % cycle
		if _archetype_frames.is_empty():
			# Procedural path: original behavior — flip_h on facing + alpha bob.
			_sprite.flip_h = not _facing_right
			_sprite.modulate.a = 0.95 if _anim_frame == 0 else 1.0
		else:
			_update_archetype_frame()


## Returns the sprite scale for our current scene context.
## Open overworlds use Mode 7 perspective — characters need to be visible
## at distance, so they render at 3x. Interior scenes (villages, dungeons,
## taverns) don't use Mode 7 and use 1x to match the stationary OverworldNPCs
## they share the scene with.
##
## (User feedback 2026-05-03: 653eae1 dropped scale 3.0 → 1.0 to fix wandering
## NPCs being too big in HarmoniaVillage, but that broke the overworld where
## 1x reads as tiny. Differentiate by parent-name keyword scan.)
func _get_context_scale() -> Vector2:
	var p = get_parent()
	if p:
		var pname = p.name.to_lower()
		# Ancestors covering the 6 overworld scenes (OverworldScene,
		# SuburbanOverworld, IndustrialOverworld, SteampunkOverworld,
		# FuturisticOverworld, AbstractOverworld). Each scene root contains
		# "overworld" in its node name.
		if "overworld" in pname:
			return Vector2(3.0, 3.0)
		# Walk up one more level (NPCs are sometimes parented to a
		# `Wanderers` Node2D which is a child of the overworld scene).
		var gp = p.get_parent()
		if gp and "overworld" in gp.name.to_lower():
			return Vector2(3.0, 3.0)
	return Vector2.ONE


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	var ctx_scale := _get_context_scale()
	# Try archetype sheet first.
	if sprite_archetype != "" and _try_load_archetype():
		_sprite.centered = true
		_sprite.scale = ctx_scale
		add_child(_sprite)
		_update_archetype_frame()
		return
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)

	var body = sprite_color
	var dark = sprite_color.darkened(0.3)
	var skin = Color(0.85, 0.7, 0.55)
	var hair = sprite_color.darkened(0.4)

	# Simple chibi figure
	# Head
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dy * dy <= 5:
				img.set_pixel(16 + dx, 8 + dy, skin)
	# Hair
	for dx in range(-2, 3):
		img.set_pixel(16 + dx, 6, hair)
		img.set_pixel(16 + dx, 7, hair)
	# Body
	for y in range(12, 22):
		for x in range(13, 20):
			img.set_pixel(x, y, body if (x + y) % 3 != 0 else dark)
	# Legs
	for y in range(22, 28):
		img.set_pixel(14, y, dark)
		img.set_pixel(15, y, dark)
		img.set_pixel(17, y, dark)
		img.set_pixel(18, y, dark)
	# Feet
	img.set_pixel(13, 28, dark)
	img.set_pixel(14, 28, dark)
	img.set_pixel(18, 28, dark)
	img.set_pixel(19, 28, dark)

	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true
	_sprite.scale = ctx_scale
	add_child(_sprite)


## Slice the archetype sheet into a (direction, frame) cache.
## Returns true on success, false if asset missing/malformed.
func _try_load_archetype() -> bool:
	var path = "res://assets/sprites/npcs/%s/overworld.png" % sprite_archetype
	if not ResourceLoader.exists(path):
		return false
	var tex = load(path) as Texture2D
	if not tex:
		return false
	var img = tex.get_image()
	if not img or img.get_width() < 128 or img.get_height() < 128:
		return false
	# 4×4 grid, 32x32 frames. Sheet rows: 0=down, 1=left, 2=right, 3=up.
	for row in range(4):
		for col in range(4):
			var region = Rect2i(col * ARCHETYPE_FRAME_W, row * ARCHETYPE_FRAME_H,
				ARCHETYPE_FRAME_W, ARCHETYPE_FRAME_H)
			var frame_img = img.get_region(region)
			_archetype_frames["%d_%d" % [row, col]] = ImageTexture.create_from_image(frame_img)
	return true


## Pick the right (direction, frame) from the archetype cache and apply.
## Direction is derived from current motion (or last facing if paused).
func _update_archetype_frame() -> void:
	if _archetype_frames.is_empty():
		return
	var key = "%d_%d" % [_current_dir, _anim_frame % 4]
	if _archetype_frames.has(key):
		_sprite.texture = _archetype_frames[key]
		# Disable the procedural-path flip_h since archetype rows already
		# encode left/right separately.
		_sprite.flip_h = false


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true

	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	# Collision radius matches context: 128 in open overworld (Mode 7
	# billboard scale), 40 in interiors (matches OverworldNPC interior
	# default). Without this scaling, village wanderers had a 128-radius
	# zone but only 1x sprite, so the player got "interaction available"
	# prompts from way too far away. Audit-fix 2026-05-04.
	var ctx_scale := _get_context_scale()
	if ctx_scale.x >= 2.0:
		shape.radius = 128.0
		col.scale = Vector2(1.0, 1.67)  # Y-stretch: matches Mode 7 billboard Y:X ratio
	else:
		shape.radius = 40.0
		col.scale = Vector2.ONE
	col.shape = shape
	col.position = Vector2(0, 0)
	add_child(col)


func _setup_label() -> void:
	_label = Label.new()
	_label.text = "%s: \"%s\"" % [npc_name, dialogue]
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-100, -60)
	_label.size = Vector2(200, 40)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _get_current_dialogue() -> String:
	if dialogue_hints.is_empty():
		return dialogue
	var best = dialogue
	for hint in dialogue_hints:
		var flag: String = hint.get("flag", "")
		# Tick 280: dual-namespace check (matches QuestLog._is_quest_flag_set).
		# Pre-fix only get_story_flag fired — every bare-name flag that
		# actually lives in game_constants ("chapter1_complete" →
		# "cutscene_flag_chapter1_complete") silently never matched, so
		# wanderer hints stayed on the default text forever.
		if flag == "" or _flag_set(flag):
			best = hint.get("text", dialogue)
	return best


func _flag_set(flag: String) -> bool:
	return GameState.get_story_flag(flag) \
		or GameState.game_constants.get("cutscene_flag_" + flag, false) \
		or GameState.game_constants.get(flag, false)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_nearby = true
		_label.text = "[A] %s" % npc_name
		_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move") or body.is_in_group("player"):
		_player_nearby = false
		_label.visible = false


func _input(event: InputEvent) -> void:
	if not _player_nearby or _in_conversation:
		return

	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		# Defer conversation start to avoid await inside _input
		call_deferred("_start_conversation")


func _start_conversation() -> void:
	"""Open a proper dialogue box for this NPC."""
	_in_conversation = true
	_label.visible = false

	var player = _get_player()

	# ── LLM-driven path: use DynamicConversation when LLMService is available
	# AND this wanderer is opt-in for dynamic dialogue. Per design doc :157,
	# only the showcase set takes this branch. Ambient wanderers default
	# `dynamic = false` and continue through the single-line NPCDialogue
	# pipeline below. ───────────────────────────────────────────────────────
	if dynamic and persona != "" and _llm_conversation_available():
		await _run_dynamic_conversation(player)
		_in_conversation = false
		if _player_nearby:
			_label.text = "[A] %s" % npc_name
			_label.visible = true
		return

	# ── Static path: single-line NPCDialogue box. ──
	# Freeze player during conversation
	if player and player.has_method("set_can_move"):
		player.set_can_move(false)

	# Create NPCDialogue if needed
	if not _npc_dialogue or not is_instance_valid(_npc_dialogue):
		var NPCDialogueClass = load("res://src/cutscene/NPCDialogue.gd")
		_npc_dialogue = NPCDialogueClass.new()
		add_child(_npc_dialogue)

	var text = _get_current_dialogue()
	await _npc_dialogue.say(npc_name, text, dialogue_theme, dialogue_portrait)

	# Unfreeze player
	if player and player.has_method("set_can_move"):
		player.set_can_move(true)

	_in_conversation = false
	if _player_nearby:
		_label.text = "[A] %s" % npc_name
		_label.visible = true


func _get_player() -> Node:
	"""Find the player node."""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	# Try MapSystem autoload (Engine.has_singleton is ALWAYS FALSE for autoloads
	# in Godot 4 — look up via the scene tree root).
	var ms: Node = get_node_or_null("/root/MapSystem")
	if ms != null and ms.has_method("get_player"):
		return ms.get_player()
	return null


func _llm_conversation_available() -> bool:
	"""Returns true when LLMService is present and reporting availability."""
	var svc: Node = get_node_or_null("/root/LLMService")
	return svc != null and svc.is_available()


func _run_dynamic_conversation(player: Node) -> void:
	"""Spin up (or reuse) a DynamicConversation and run a full LLM-driven exchange."""
	if not _dynamic_conv or not is_instance_valid(_dynamic_conv):
		_dynamic_conv = DynamicConversation.new()
		_dynamic_conv.name = "DynamicConversation"
		add_child(_dynamic_conv)

	# Resolve EventLog from the GameState autoload via the scene tree root
	# (Engine.has_singleton is ALWAYS FALSE for autoloads in Godot 4).
	var event_log: EventLog = null
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and "event_log" in gs:
		event_log = gs.event_log

	# Resolve location name from parent scene.
	var location: String = _resolve_location_name()

	# WanderingNPCs have a single dialogue line — wrap it as the fallback array.
	var fallback_lines: Array = [_get_current_dialogue()]

	# Use the authored @export persona directly. The caller (`_start_conversation`)
	# already gated on `dynamic and persona != ""`, so the fake-persona
	# derivation from dialogue_theme is no longer needed (and was misleading
	# anyway — dialogue_theme is a portrait key, not a character description).
	_dynamic_conv.setup(npc_name, persona, location, event_log, fallback_lines)
	await _dynamic_conv.run(player)


func _resolve_location_name() -> String:
	var p = get_parent()
	if p:
		var n: String = p.name
		if n != "" and n != "Node":
			return n
		var gp = p.get_parent()
		if gp:
			var gn: String = gp.name
			if gn != "" and gn != "Node":
				return gn
	return "Unknown Land"
