extends Area2D
class_name RoamingMonster

## RoamingMonster - Visible wandering enemy on the overworld
## Sprite sheet: 128x128, 4 rows x 4 cols, 32x32 per frame
## Row 0=walk_down, 1=walk_left, 2=walk_right, 3=walk_up

## is_elite travels with the touch because ELITE IS A PROPERTY OF THE SPAWN, not of the
## species. Five of six worlds promote an ORDINARY monster to elite duty, so a species-level
## flag would turn every routine encounter with that species into an elite fight.
signal touched(monster_id: String, monster_types: Array, is_elite: bool)

const FRAME_W: int = 32
const FRAME_H: int = 32
const SHEET_COLS: int = 4
const WANDER_SPEED: float = 90.0
const CHASE_SPEED: float = 115.0
const CHASE_RADIUS: float = 96.0
const WANDER_RADIUS: float = 160.0
const RESPAWN_TIME_MIN: float = 30.0
const RESPAWN_TIME_MAX: float = 60.0
const ANIM_FPS: float = 6.0
const FLEE_SPEED: float = 130.0
const ANGRY_SPEED: float = 145.0
## Spotted at CHASE_RADIUS, but a mood is decided BEFORE the pounce: the alerted beat is
## what makes a chase read as a reaction instead of a magnet.
const ALERT_RADIUS: float = 150.0
const ALERT_DURATION: float = 0.55
## A monster this far below the party's average level is ELIGIBLE to flee.
const AFRAID_LEVEL_GAP: int = 4
## ...and this fraction of eligible monsters actually does. struktured 2026-09-06 asked that
## "SOME monsters should be angry or alerted or afraid", a MIX. The level gap alone is an
## absolute threshold, so it swallows the whole roster as the party levels: measured
## 2026-09-09, at party level 10 every monster in W1, W2 and W3 flees, and by 20 every monster
## in every world does. You outlevel a world before you leave it, so "some are afraid" became
## "everything runs away" for most of the game, and every encounter became a chase (the player
## moves at 240 against a flee speed of 130 -- it is a chore, not an escape).
## Per MONSTER, not per frame: a disposition it is born with, so it never flickers mid-chase.
const TIMID_FRACTION: float = 0.5

## Mood, distinct from _state (which is locomotion). struktured 2026-09-06: "some monsters
## should be angry or alerted or afraid on overworld etc, not just wandering aimlessly, but
## that can be a default until you're spotted."
enum Mood { CALM, ALERTED, ANGRY, AFRAID }

@export var monster_id: String = "slime"
@export var monster_types: Array = []
## Field elite (BD2-style rare): sits still, radiates, never chases, and asks before it
## fights. Everything about the ordinary roamer path stays byte-identical when false.
@export var elite: bool = false

var _spawn_origin: Vector2 = Vector2.ZERO
var _active: bool = true
var _player_ref: Node2D = null

var _sprite: Sprite2D
var _sheet: Texture2D
var _sheet_loaded: bool = false

var _dir: Vector2 = Vector2.ZERO
var _state: int = 0  # 0=wander, 1=pause, 2=chase
var _state_timer: float = 0.0
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _row: int = 0  # sprite sheet row

var _mood: int = Mood.CALM
var _mood_timer: float = 0.0
var _tell: Label = null
var _aura: Node2D = null
var _aura_phase: float = 0.0
var _prompt_open: bool = false

var _respawn_timer: float = 0.0
var _fading: bool = false
var _fade_timer: float = 0.0
const FADE_DURATION: float = 0.5

var _collision: CollisionShape2D


func _ready() -> void:
	_spawn_origin = global_position
	if monster_types.is_empty():
		monster_types = [monster_id]

	_setup_sprite()
	_setup_collision()
	body_entered.connect(_on_body_entered)

	_setup_tell()
	if elite:
		_setup_aura()
		_state = 1           # pause: an elite never picks a wander direction
		_dir = Vector2.ZERO
		return

	# Start with a short random offset so monsters don't all move in sync
	_state_timer = randf_range(0.0, 2.0)
	_pick_wander_dir()


## The mood tell. One Label, retargeted per mood, rather than three nodes -- a monster is
## only ever in one mood, and three hidden nodes is three things to forget to hide.
func _setup_tell() -> void:
	_tell = Label.new()
	_tell.name = "MoodTell"
	_tell.position = Vector2(-8, -34)
	_tell.add_theme_font_size_override("font_size", 16)
	_tell.z_index = 2
	_tell.visible = false
	add_child(_tell)


## Procedural radiating aura -- no art dependency, and it is the elite's whole read at a
## distance. Gated on reduce_flashes: the setting exists because pulsing hurts some players,
## so the aura holds a STEADY ring instead of vanishing (the monster must stay legible).
func _setup_aura() -> void:
	_aura = Node2D.new()
	_aura.name = "EliteAura"
	_aura.z_index = -1
	_aura.draw.connect(_draw_aura)
	add_child(_aura)


func _reduce_flashes() -> bool:
	var gs: Node = get_tree().root.get_node_or_null("GameState") if is_inside_tree() else null
	return gs != null and gs.get("reduce_flashes") == true


func _draw_aura() -> void:
	var pulse: float = 0.0 if _reduce_flashes() else sin(_aura_phase * 2.2) * 0.5 + 0.5
	var base: float = 26.0 + pulse * 6.0
	var col := Color(0.85, 0.25, 1.0)
	for i in range(3):
		var r: float = base + float(i) * 5.0
		var a: float = (0.30 - float(i) * 0.08) * (0.65 + pulse * 0.35)
		_aura.draw_circle(Vector2.ZERO, r, Color(col.r, col.g, col.b, a))


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = true
	add_child(_sprite)

	var path = "res://assets/sprites/monsters/overworld/%s.png" % monster_id
	if ResourceLoader.exists(path):
		_sheet = load(path)
		_sheet_loaded = true
		_sprite.texture = _sheet
		_sprite.region_enabled = true
		_apply_frame(0, 0)
	else:
		_draw_fallback_sprite()


func _draw_fallback_sprite() -> void:
	# Placeholder until overworld art lands — hue-hashed per monster_id so species are
	# distinguishable (was a single red box, which read as "all the same" for art-less worlds).
	var img = Image.create(FRAME_W, FRAME_H, false, Image.FORMAT_RGBA8)
	img.fill(_placeholder_color(monster_id))
	for x in range(FRAME_W):
		img.set_pixel(x, 0, Color.BLACK)
		img.set_pixel(x, FRAME_H - 1, Color.BLACK)
	for y in range(FRAME_H):
		img.set_pixel(0, y, Color.BLACK)
		img.set_pixel(FRAME_W - 1, y, Color.BLACK)
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.region_enabled = false


func _placeholder_color(id: String) -> Color:
	var h := 0
	for i in id.length():
		h = (h * 31 + id.unicode_at(i)) & 0xFFFFFF
	return Color.from_hsv(float(h % 360) / 360.0, 0.6, 0.85, 0.95)


func _apply_frame(row: int, col: int) -> void:
	if not _sheet_loaded:
		return
	_sprite.region_rect = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)


## Touch radius tuned to ~1.4x the 32px sprite half-width — encounter fires only on actual sprite overlap.
const TOUCH_RADIUS_PX: float = 48.0


func _setup_collision() -> void:
	_collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = TOUCH_RADIUS_PX
	_collision.shape = shape
	add_child(_collision)

	collision_layer = 8
	collision_mask = 2
	monitoring = true
	monitorable = true


func _process(delta: float) -> void:
	if not _active:
		_tick_respawn(delta)
		return

	if _fading:
		_tick_fade(delta)
		return

	if elite:
		_aura_phase += delta
		if _aura:
			_aura.queue_redraw()
		_tick_elite_watch()
		_tick_anim(delta)
		return       # never wanders, never chases, never flees

	_tick_anim(delta)
	_tick_mood(delta)
	_tick_state(delta)
	_move(delta)


## Mood is decided from distance and relative strength; locomotion (_state) then obeys it.
## Kept separate because the same CHASE state means different things -- an angry monster
## closing and a frightened one bolting are both "moving", and only mood knows which.
func _tick_mood(delta: float) -> void:
	if _mood == Mood.ALERTED:
		_mood_timer -= delta
		if _mood_timer > 0.0:
			return
		_mood = Mood.AFRAID if _is_outmatched() else Mood.ANGRY
		_show_tell()
		return

	if not _player_ref or not is_instance_valid(_player_ref):
		if _mood != Mood.CALM:
			_mood = Mood.CALM
			_show_tell()
		return

	var dist := global_position.distance_to(_player_ref.global_position)
	if _mood == Mood.CALM and dist <= ALERT_RADIUS:
		_mood = Mood.ALERTED
		_mood_timer = ALERT_DURATION
		_dir = Vector2.ZERO
		_face_player()
		_show_tell()
	elif _mood != Mood.CALM and dist > ALERT_RADIUS * 1.6:
		_mood = Mood.CALM
		_show_tell()


## Afraid is for monsters much weaker than the party, per the ask. Reads the party's average
## level from GameState; absent that (tests, early boot) nothing is outmatched and every
## monster is simply angry -- the pre-mood behaviour.
## Deterministic from the spawn, so the same monster always has the same nerve and two runs of
## the same seed agree. Nothing about it changes while the player is looking.
func _is_timid() -> bool:
	var h: int = (int(_spawn_origin.x) * 73856093) ^ (int(_spawn_origin.y) * 19349663) ^ monster_id.hash()
	return float(absi(h) % 1000) / 1000.0 < TIMID_FRACTION


func _is_outmatched() -> bool:
	if not _is_timid():
		return false
	var gs: Node = get_tree().root.get_node_or_null("GameState") if is_inside_tree() else null
	if gs == null:
		return false
	var party = gs.get("player_party")
	if party == null or not (party is Array) or party.is_empty():
		return false
	var total := 0.0
	var n := 0
	for c in party:
		var lv = c.get("job_level") if c != null and "job_level" in c else null
		if lv != null:
			total += float(lv)
			n += 1
	if n == 0:
		return false
	var mine := float(_monster_level())
	return (total / float(n)) - mine >= float(AFRAID_LEVEL_GAP)


func _monster_level() -> int:
	# Same defect as _is_field_elite: BestiarySystem is a class_name with static functions,
	# so the node lookup was always null and EVERY monster read as level 1. AFRAID compares
	# the party average against this, so "afraid, for monsters much weaker than the party"
	# was really "afraid, for every monster once the party passes level 5".
	return int(BestiarySystem.get_monster_data(monster_id).get("level", 1))


func _face_player() -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		return
	_update_row_from_move_dir((_player_ref.global_position - global_position).normalized())
	_apply_frame(_row, 0)


func _show_tell() -> void:
	if _tell == null:
		return
	match _mood:
		Mood.ALERTED:
			_tell.text = "!"
			_tell.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
			_tell.visible = true
		Mood.ANGRY:
			_tell.text = "!!"
			_tell.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
			_tell.visible = true
		Mood.AFRAID:
			_tell.text = "~"
			_tell.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
			_tell.visible = true
		_:
			_tell.visible = false


func _tick_anim(delta: float) -> void:
	_anim_timer += delta
	if _anim_timer >= 1.0 / ANIM_FPS:
		_anim_timer -= 1.0 / ANIM_FPS
		if _dir != Vector2.ZERO or _state == 2:
			_anim_frame = (_anim_frame + 1) % SHEET_COLS
		else:
			_anim_frame = 0
		_apply_frame(_row, _anim_frame)


func _tick_state(delta: float) -> void:
	# Alerted is a beat, not a pursuit: hold position for ALERT_DURATION so the "!" reads.
	if _mood == Mood.ALERTED:
		_state = 1
		_dir = Vector2.ZERO
		return

	if _player_ref and is_instance_valid(_player_ref):
		var dist = global_position.distance_to(_player_ref.global_position)
		# An afraid monster is still in state 2 -- _move reverses it, so fleeing reuses the
		# chase plumbing (bounds, animation, row) instead of duplicating it.
		if dist <= CHASE_RADIUS and _state != 2:
			_state = 2
			_state_timer = 0.0
			return

	if _state == 2:
		if not _player_ref or not is_instance_valid(_player_ref):
			_state = 0
			_pick_wander_dir()
			return
		var dist = global_position.distance_to(_player_ref.global_position)
		if dist > CHASE_RADIUS * 1.5:
			_state = 0
			_pick_wander_dir()
		return

	_state_timer -= delta
	if _state_timer <= 0.0:
		if _state == 0:
			_state = 1
			_state_timer = randf_range(1.0, 3.0)
			_dir = Vector2.ZERO
		else:
			_state = 0
			_pick_wander_dir()


func _pick_wander_dir() -> void:
	var dirs = [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
	_dir = dirs[randi() % dirs.size()]
	_state_timer = randf_range(0.8, 2.0)
	_update_row_from_dir()


func _update_row_from_dir() -> void:
	if _dir == Vector2.DOWN:
		_row = 0
	elif _dir == Vector2.LEFT:
		_row = 1
	elif _dir == Vector2.RIGHT:
		_row = 2
	elif _dir == Vector2.UP:
		_row = 3


func _move(delta: float) -> void:
	if _state == 1:
		return

	var move_dir: Vector2
	var speed: float

	if _state == 2 and _player_ref and is_instance_valid(_player_ref):
		move_dir = ((_player_ref.global_position - global_position).normalized())
		speed = CHASE_SPEED
		if _mood == Mood.AFRAID:
			move_dir = -move_dir       # same plumbing, opposite sign
			speed = FLEE_SPEED
		elif _mood == Mood.ANGRY:
			speed = ANGRY_SPEED
		_update_row_from_move_dir(move_dir)
	else:
		move_dir = _dir
		speed = WANDER_SPEED

	if move_dir == Vector2.ZERO:
		return

	var next_pos = global_position + move_dir * speed * delta
	var dist_from_spawn = next_pos.distance_to(_spawn_origin)
	# A frightened monster gets a longer leash: turning it back at WANDER_RADIUS would walk
	# it into the player it is running from, which reads as broken rather than as fear.
	var leash := WANDER_RADIUS * (2.0 if _mood == Mood.AFRAID else 1.0)
	if dist_from_spawn > leash:
		_dir = (_spawn_origin - global_position).normalized().round()
		if _dir == Vector2.ZERO:
			_dir = Vector2.DOWN
		_update_row_from_dir()
		return

	global_position = next_pos


func _update_row_from_move_dir(move_dir: Vector2) -> void:
	if abs(move_dir.x) > abs(move_dir.y):
		_row = 2 if move_dir.x > 0 else 1
	else:
		_row = 0 if move_dir.y > 0 else 3


func _tick_fade(delta: float) -> void:
	_fade_timer += delta
	var t = clampf(_fade_timer / FADE_DURATION, 0.0, 1.0)
	_sprite.modulate.a = 1.0 - t
	if _fade_timer >= FADE_DURATION:
		_active = false
		_fading = false
		_sprite.visible = false
		_collision.disabled = true
		_respawn_timer = randf_range(RESPAWN_TIME_MIN, RESPAWN_TIME_MAX)


func _tick_respawn(delta: float) -> void:
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn()


func _respawn() -> void:
	global_position = _spawn_origin
	_active = true
	_fading = false
	_fade_timer = 0.0
	_sprite.visible = true
	_sprite.modulate.a = 1.0
	_collision.disabled = false
	_mood = Mood.CALM
	_show_tell()
	if elite:
		_state = 1
		_dir = Vector2.ZERO
		return
	_state = 0
	_pick_wander_dir()


func _on_body_entered(body: Node2D) -> void:
	if not _active or _fading:
		return
	if body.has_method("set_can_move"):
		if elite:
			# An elite asks first. Deferred because this runs inside the physics query flush
			# and the prompt awaits — same reason deactivate() defers its collision change.
			if not _prompt_open:
				_prompt_open = true
				call_deferred("_ask_then_fight")
			return
		_emit_touch_and_maybe_fade()


## The spider-wedge sequence, extracted so the elite's confirmed fight runs the IDENTICAL
## path rather than a second copy that can drift from it. Behaviour is unchanged for the
## ordinary roamer; test_spider_wedge_regression pins it by calling _on_body_entered.
func _emit_touch_and_maybe_fade() -> void:
	# 2026-09-06 spider wedge: fading BEFORE the emit spent the monster even when GameLoop
	# BLOCKED the battle (leaked commence latch) — monsters silently vanished with no fight.
	# Emit first (the whole chain up to GameLoop's first await runs synchronously), then fade
	# only if THIS touch flipped the commence latch. No GameLoop found (tests) = old behavior.
	var gl: Node = get_tree().root.get_node_or_null("GameLoop") if is_inside_tree() else null
	var latch_before: bool = gl != null and gl.get("_battle_transition_starting") == true
	touched.emit(monster_id, monster_types, elite)
	var latch_after: bool = gl != null and gl.get("_battle_transition_starting") == true
	if gl == null or (not latch_before and latch_after):
		_begin_fade()


## Contact with a field elite is a DECISION, not an ambush -- struktured: "You have to make
## contact to decide to fight it". Declining leaves it standing exactly where it was; the
## player walks away and body_entered only re-fires on a fresh entry, so there is no
## re-prompt loop while they stand in it.
func _ask_then_fight() -> void:
	var lock: Node = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if lock and lock.has_method("push_lock"):
		lock.push_lock("elite_prompt")
	var choice: String = await _present_elite_prompt()
	if lock and lock.has_method("pop_lock"):
		lock.pop_lock("elite_prompt")
	_prompt_open = false
	if not _active or _fading:
		return
	if choice == ELITE_FIGHT:
		_emit_touch_and_maybe_fade()


## The line is shown as a floating tell rather than a modal. A second dialogue box before
## the choice would put another await inside the touch chain -- the exact shape of the two
## wedges fixed on 2026-09-06 -- and buys nothing the aura and the label do not already say.
func _tick_elite_watch() -> void:
	if _tell == null:
		return
	var near: bool = false
	if _player_ref and is_instance_valid(_player_ref):
		near = global_position.distance_to(_player_ref.global_position) <= ALERT_RADIUS
		if near:
			_face_player()
	if near and not _prompt_open:
		_tell.text = ELITE_PROMPT_TEXT
		_tell.add_theme_color_override("font_color", Color(0.92, 0.62, 1.0))
		_tell.position = Vector2(-58, -44)
		_tell.visible = true
	elif not _prompt_open:
		_tell.visible = false


const ELITE_FIGHT := "Fight"
const ELITE_LEAVE := "Leave it"
const ELITE_PROMPT_TEXT := "It is watching you."


## Reuses the game's own choice menu so the elite prompt is gamepad-navigable and looks like
## every other choice. Unavailable menu = decline, never an accidental unfair fight.
func _present_elite_prompt() -> String:
	var MenuScript = load("res://src/llm/DialogueChoiceMenu.gd")
	if MenuScript == null:
		return ELITE_LEAVE
	var layer := CanvasLayer.new()
	layer.layer = 96
	var menu: Node = MenuScript.new()
	get_tree().root.add_child(layer)
	layer.add_child(menu)
	var result: String = await menu.present([ELITE_FIGHT, ELITE_LEAVE])
	layer.queue_free()
	return result


## Immediately stop the monster from triggering a battle. Called by
## MonsterSpawner when exploration pauses (menu opens) so queued
## body_entered signals in the same physics frame don't leak into
## battle after the player is supposed to be safe.
func deactivate() -> void:
	_active = false
	_fading = false
	if _collision:
		## Deferred: this runs INSIDE body_entered (touch -> battle -> pause ->
		## set_enabled(false) -> _despawn_all), and changing shape state mid-flush threw
		## "Can't change this state while flushing queries" 52x in one play session.
		## The battle-leak guard is _active above, which stays synchronous.
		_collision.set_deferred("disabled", true)
	if _sprite:
		_sprite.visible = false


func _begin_fade() -> void:
	_fading = true
	_fade_timer = 0.0


func set_player_ref(player: Node2D) -> void:
	_player_ref = player
