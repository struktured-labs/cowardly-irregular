extends Node
class_name BattleAnimator

## BattleAnimator - Handles sprite animations for combatants in battle
## 12-bit style battle animations (SNES/Genesis era aesthetic)
##
## Sprite generation has been extracted to:
## - SpriteUtils (src/battle/sprites/_SpriteUtils.gd) - shared helpers, cache, equipment
## - PartySprites (src/battle/sprites/_PartySprites.gd) - hero, mage, thief sprites
## - MonsterSprites (src/battle/sprites/_MonsterSprites.gd) - all monster/enemy sprites
##
## This file retains: AnimState enum, animation playback, instance methods,
## and backward-compatible static proxy methods for external callers.

## Preloaded references to extracted sprite modules
const _SpriteUtils = preload("res://src/battle/sprites/SpriteUtils.gd")
const _PartySprites = preload("res://src/battle/sprites/PartySprites.gd")
const _MonsterSprites = preload("res://src/battle/sprites/MonsterSprites.gd")

## Animation states for combatants
enum AnimState {
	IDLE,
	ATTACK,
	DEFEND,
	HIT,
	CAST,
	ITEM,
	VICTORY,
	DEFEAT,
	DEAD
}

## Animation speeds (frames per animation frame) - slower for visibility
const ANIM_SPEED: Dictionary = {
	"idle": 0.4,
	"attack": 0.25,
	"defend": 0.35,
	"hit": 0.2,
	"cast": 0.3,
	"item": 0.25,
	"victory": 0.35,
	"defeat": 0.3
}

## Sprite size configuration - delegates to SpriteUtils for shared constants
const SPRITE_SIZE: int = _SpriteUtils.SPRITE_SIZE
const BASE_SIZE: int = _SpriteUtils.BASE_SIZE
const SPRITE_SCALE: float = _SpriteUtils.SPRITE_SCALE

## Clear the sprite cache (call when equipment changes or on memory pressure)
static func clear_sprite_cache() -> void:
	_SpriteUtils.clear_sprite_cache()

## Pre-warm the cache for common sprite types (call during loading screens)
static func prewarm_cache(monster_ids: Array = [], party_jobs: Array = []) -> void:
	"""Pre-generate and cache sprites for anticipated encounters."""
	# Pre-warm common monsters and minibosses
	for id in monster_ids:
		match id:
			"slime": _MonsterSprites.create_slime_sprite_frames()
			"skeleton": _MonsterSprites.create_skeleton_sprite_frames()
			"ghost": _MonsterSprites.create_specter_sprite_frames()
			"imp": _MonsterSprites.create_imp_sprite_frames()
			"wolf": _MonsterSprites.create_wolf_sprite_frames()
			"snake": _MonsterSprites.create_viper_sprite_frames()
			"bat": _MonsterSprites.create_bat_sprite_frames()
			"mushroom": _MonsterSprites.create_fungoid_sprite_frames()
			"goblin": _MonsterSprites.create_goblin_sprite_frames()
			"cave_rat": _MonsterSprites.create_cave_rat_sprite_frames()
			"rat_guard": _MonsterSprites.create_rat_guard_sprite_frames()
			"shadow_knight": _MonsterSprites.create_shadow_knight_sprite_frames()
			"cave_troll": _MonsterSprites.create_cave_troll_sprite_frames()
			"cave_rat_king": _MonsterSprites.create_cave_rat_king_sprite_frames()
			"fire_dragon": _MonsterSprites.create_fire_dragon_sprite_frames()
			"ice_dragon": _MonsterSprites.create_ice_dragon_sprite_frames()
			"lightning_dragon": _MonsterSprites.create_lightning_dragon_sprite_frames()
			"shadow_dragon": _MonsterSprites.create_shadow_dragon_sprite_frames()
	# Pre-warm party jobs
	for job_data in party_jobs:
		var job_id = job_data.get("job_id", "fighter")
		var weapon_id = job_data.get("weapon_id", "")
		match job_id:
			"fighter": _PartySprites.create_hero_sprite_frames(weapon_id)
			"white_mage": _PartySprites.create_mage_sprite_frames(Color(0.9, 0.9, 1.0), weapon_id)
			"black_mage": _PartySprites.create_mage_sprite_frames(Color(0.15, 0.1, 0.25), weapon_id)
			"thief": _PartySprites.create_thief_sprite_frames(weapon_id)

## Helper aliases delegating to SpriteUtils (backward compatibility)
static func _s(value: float) -> int: return _SpriteUtils._s(value)
static func _sf(value: float) -> float: return _SpriteUtils._sf(value)
static func _safe_pixel(img: Image, x: int, y: int, color: Color) -> void: _SpriteUtils._safe_pixel(img, x, y, color)
static func get_weapon_visual(weapon_id: String) -> Dictionary: return _SpriteUtils.get_weapon_visual(weapon_id)

## Current animation state
var current_state: AnimState = AnimState.IDLE
var current_frame: int = 0
var frame_timer: float = 0.0
var is_playing: bool = false
var loop_animation: bool = true
var on_animation_complete: Callable

## Reference to the sprite node
var sprite: AnimatedSprite2D

## Current animation tween (stored for cleanup/cancellation)
var _current_tween: Tween = null

## Animation callbacks
signal animation_started(state: AnimState)
signal animation_finished(state: AnimState)


func _init() -> void:
	"""Initialize the animator"""
	pass


func setup(animated_sprite: AnimatedSprite2D) -> void:
	"""Setup the animator with a sprite"""
	sprite = animated_sprite
	if sprite:
		sprite.animation_finished.connect(_on_sprite_animation_finished)


func _exit_tree() -> void:
	"""Cleanup when animator is freed"""
	# Kill any running tween
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	_current_tween = null

	# Disconnect signal if sprite still valid
	if sprite and is_instance_valid(sprite):
		if sprite.animation_finished.is_connected(_on_sprite_animation_finished):
			sprite.animation_finished.disconnect(_on_sprite_animation_finished)


func play_animation(state: AnimState, loop: bool = false, on_complete: Callable = Callable()) -> void:
	"""Play an animation state"""
	if not sprite:
		push_warning("BattleAnimator: No sprite assigned!")
		return

	current_state = state
	loop_animation = loop
	on_animation_complete = on_complete
	is_playing = true
	current_frame = 0

	# Map state to animation name
	var anim_name = _get_animation_name(state)

	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)
		animation_started.emit(state)
	else:
		push_warning("BattleAnimator: Animation '%s' not found!" % anim_name)
		is_playing = false


func stop_animation() -> void:
	"""Stop current animation"""
	if sprite:
		sprite.stop()
	is_playing = false


func set_idle() -> void:
	"""Set sprite to idle state"""
	play_animation(AnimState.IDLE, true)


func play_attack(on_complete: Callable = Callable()) -> void:
	"""Play attack animation"""
	play_animation(AnimState.ATTACK, false, on_complete)


func play_defend(on_complete: Callable = Callable()) -> void:
	"""Play defend animation"""
	play_animation(AnimState.DEFEND, false, on_complete)


func play_hit(on_complete: Callable = Callable()) -> void:
	"""Play hit/damage animation"""
	play_animation(AnimState.HIT, false, on_complete)


func play_cast(on_complete: Callable = Callable()) -> void:
	"""Play spell cast animation"""
	play_animation(AnimState.CAST, false, on_complete)


func play_item(on_complete: Callable = Callable()) -> void:
	"""Play item use animation"""
	play_animation(AnimState.ITEM, false, on_complete)


func play_victory(on_complete: Callable = Callable()) -> void:
	"""Play victory animation"""
	play_animation(AnimState.VICTORY, true, on_complete)


func play_defeat(on_complete: Callable = Callable()) -> void:
	"""Play defeat animation"""
	play_animation(AnimState.DEFEAT, false, on_complete)


func play_backstab(on_complete: Callable = Callable()) -> void:
	"""Quick diagonal lunge attack animation"""
	if not sprite:
		if on_complete.is_valid():
			on_complete.call()
		return

	# Kill any existing animation tween
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	# Store original position
	var original_pos = sprite.position

	# Quick diagonal dash forward-left
	_current_tween = create_tween()
	var tween = _current_tween
	tween.set_trans(Tween.TRANS_EXPO)
	tween.tween_property(sprite, "position", original_pos + Vector2(-30, -15), 0.1)

	# Play attack animation during the lunge
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
			sprite.play("attack")
	)

	# Hold at strike position briefly
	tween.tween_interval(0.15)

	# Return to original position
	tween.tween_property(sprite, "position", original_pos, 0.15)

	# Return to idle
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
		if on_complete.is_valid():
			on_complete.call()
	)


func play_steal(on_complete: Callable = Callable()) -> void:
	"""Quick dash in and out animation for stealing"""
	if not sprite:
		if on_complete.is_valid():
			on_complete.call()
		return

	# Kill any existing animation tween
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	var original_pos = sprite.position

	# Play attack animation
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")

	# Quick dash forward
	_current_tween = create_tween()
	var tween = _current_tween
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "position", original_pos + Vector2(-50, 0), 0.12)

	# Flash (invisible briefly = "grab")
	tween.tween_property(sprite, "modulate:a", 0.5, 0.05)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.05)

	# Quick dash back
	tween.set_trans(Tween.TRANS_EXPO)
	tween.tween_property(sprite, "position", original_pos, 0.15)

	# Return to idle
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
		if on_complete.is_valid():
			on_complete.call()
	)


func play_skill(on_complete: Callable = Callable()) -> void:
	"""Generic physical skill animation with pose hold"""
	if not sprite:
		if on_complete.is_valid():
			on_complete.call()
		return

	# Kill any existing animation tween
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	var original_pos = sprite.position

	# Play attack animation with a slight forward lean
	_current_tween = create_tween()
	var tween = _current_tween

	# Prep pose - lean back
	tween.tween_property(sprite, "position", original_pos + Vector2(10, 0), 0.1)

	# Execute - quick forward lunge
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
			sprite.play("attack")
	)
	tween.tween_property(sprite, "position", original_pos + Vector2(-25, 0), 0.08)

	# Brief pause at impact
	tween.tween_interval(0.1)

	# Return
	tween.tween_property(sprite, "position", original_pos, 0.12)

	# Back to idle
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
		if on_complete.is_valid():
			on_complete.call()
	)


func play_mug(on_complete: Callable = Callable()) -> void:
	"""Combination attack + steal animation"""
	if not sprite:
		if on_complete.is_valid():
			on_complete.call()
		return

	# Kill any existing animation tween
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	var original_pos = sprite.position

	# Play attack animation
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")

	# Aggressive dash forward with spin effect
	_current_tween = create_tween()
	var tween = _current_tween
	tween.set_trans(Tween.TRANS_EXPO)
	tween.tween_property(sprite, "position", original_pos + Vector2(-45, 0), 0.1)
	tween.parallel().tween_property(sprite, "rotation", 0.3, 0.1)

	# Strike and grab
	tween.tween_interval(0.08)
	tween.tween_property(sprite, "modulate", Color(1.2, 1.0, 0.8), 0.05)  # Flash gold
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.05)

	# Return with spin
	tween.tween_property(sprite, "position", original_pos, 0.15)
	tween.parallel().tween_property(sprite, "rotation", 0.0, 0.15)

	# Back to idle
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
		if on_complete.is_valid():
			on_complete.call()
	)


func _get_animation_name(state: AnimState) -> String:
	"""Convert animation state to string name"""
	match state:
		AnimState.IDLE: return "idle"
		AnimState.ATTACK: return "attack"
		AnimState.DEFEND: return "defend"
		AnimState.HIT: return "hit"
		AnimState.CAST: return "cast"
		AnimState.ITEM: return "item"
		AnimState.VICTORY: return "victory"
		AnimState.DEFEAT: return "defeat"
		AnimState.DEAD: return "dead"
	return "idle"


func _on_sprite_animation_finished() -> void:
	"""Handle animation completion"""
	animation_finished.emit(current_state)

	# Call completion callback if set
	if on_animation_complete.is_valid():
		on_animation_complete.call()
		on_animation_complete = Callable()

	# Return to idle unless it's a looping animation
	if not loop_animation and current_state != AnimState.IDLE:
		set_idle()

	is_playing = false


## Helper functions for common animation sequences

func attack_sequence(target_sprite: AnimatedSprite2D, damage_callback: Callable) -> void:
	"""Complete attack sequence: attack -> target hit -> return to idle"""
	play_attack(func():
		if target_sprite:
			var target_animator = get_script().new()
			target_animator.setup(target_sprite)
			target_animator.play_hit(func():
				damage_callback.call()
			)
	)


func defend_sequence(on_complete: Callable = Callable()) -> void:
	"""Complete defend sequence"""
	play_defend(on_complete)


func cast_sequence(on_complete: Callable = Callable()) -> void:
	"""Complete spell cast sequence"""
	play_cast(on_complete)


## =================
## BACKWARD-COMPATIBLE PROXY METHODS
## =================
## These static methods delegate to PartySprites / MonsterSprites
## so that external code calling BattleAnimator.create_*_sprite_frames()
## continues to work without modification.

## Party sprite proxies
static func create_hero_sprite_frames(weapon_id: String = "") -> SpriteFrames:
	return _PartySprites.create_hero_sprite_frames(weapon_id)

static func create_mage_sprite_frames(robe_color: Color = Color(0.15, 0.1, 0.25), weapon_id: String = "") -> SpriteFrames:
	return _PartySprites.create_mage_sprite_frames(robe_color, weapon_id)

static func create_thief_sprite_frames(weapon_id: String = "") -> SpriteFrames:
	return _PartySprites.create_thief_sprite_frames(weapon_id)

## Monster sprite proxies
static func create_slime_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_slime_sprite_frames()

static func create_skeleton_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_skeleton_sprite_frames()

static func create_specter_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_specter_sprite_frames()

static func create_imp_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_imp_sprite_frames()

static func create_wolf_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_wolf_sprite_frames()

static func create_viper_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_viper_sprite_frames()

static func create_bat_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_bat_sprite_frames()

static func create_fungoid_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_fungoid_sprite_frames()

static func create_goblin_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_goblin_sprite_frames()

static func create_shadow_knight_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_shadow_knight_sprite_frames()

static func create_cave_troll_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_cave_troll_sprite_frames()

static func create_cave_rat_king_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_cave_rat_king_sprite_frames()

static func create_cave_rat_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_cave_rat_sprite_frames()

static func create_rat_guard_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_rat_guard_sprite_frames()

static func create_fire_dragon_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_fire_dragon_sprite_frames()

static func create_ice_dragon_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_ice_dragon_sprite_frames()

static func create_lightning_dragon_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_lightning_dragon_sprite_frames()

static func create_shadow_dragon_sprite_frames() -> SpriteFrames:
	return _MonsterSprites.create_shadow_dragon_sprite_frames()
