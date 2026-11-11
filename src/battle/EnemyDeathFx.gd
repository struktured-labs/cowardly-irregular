extends RefCounted
class_name EnemyDeathFx

## How an ordinary monster leaves the battle when it dies. The style is DATA, per world
## (data/enemy_death_styles.json): struktured 2026-11-07 wanted "a digital-like fading out to fit
## the meta of the game, like a TV station turning off", and left the per-world choice for later.
## Every style runs on the WALL clock, so it reads the same at 0.25x and at 64x, and ends with the
## sprite hidden after an eased fade (no pop on the last frame). Bosses keep their own death.

const PATH := "res://data/enemy_death_styles.json"
const FALLBACK_STYLE := "crt_off"

## crt_off timeline (seconds of wall time), shared with cowir-sfx so the power-off cue lands on it:
## a flash to white, the picture squashes to a bright line, the line shrinks to a dot, the dot fades.
const CRT_FLASH := 0.08
const CRT_LINE := 0.30
const CRT_DOT := 0.48
const CRT_END := 0.62

static var _table: Dictionary = {}


static func table() -> Dictionary:
	if _table.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_table = parsed
	return _table


## World 1's suffix is "" (its art carries no suffix), so it reads as "medieval" here.
static func world_key(suffix: String) -> String:
	return "medieval" if suffix == "" else suffix


static func default_style() -> String:
	return str(table().get("default", FALLBACK_STYLE))


static func style_for(world: String) -> String:
	var picked := str((table().get("by_world", {}) as Dictionary).get(world, "default"))
	if picked == "default" or not (picked in (table().get("styles", []) as Array)):
		return default_style()
	return picked


static func current_style() -> String:
	return style_for(world_key(HybridSpriteLoader.current_world_suffix()))


## A boss keeps the death it has always had; only ordinary monsters take the world's style.
static func applies_to(enemy: Object) -> bool:
	return enemy != null and not enemy.has_meta("is_boss")


## The same REAL length at every battle speed, but stepped by game frames: speed_scale 1/time_scale, never
## set_ignore_time_scale (a Movie Maker capture showed the death already over, cowir-cutscenes 23594).
## Re-read EVERY frame, not once: a killing crit's hitlag drops time_scale to 0.1 for ~80 ms, and a scale
## locked in during it ran the whole death ~4x fast once the battle speed came back (cowir-main 23618).
## The escape beat uses it too.
static func real_time(t: Tween) -> Tween:
	t.set_speed_scale(_real_speed())
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return t
	var follow := [Callable()]
	follow[0] = func() -> void:
		if t.is_valid():
			t.set_speed_scale(_real_speed())
		elif tree.process_frame.is_connected(follow[0]):
			tree.process_frame.disconnect(follow[0])
	tree.process_frame.connect(follow[0])
	return t


static func _real_speed() -> float:
	return 1.0 / maxf(Engine.time_scale, 0.01)


## The death owns the sprite from its first frame: a crit or weakness flash still tweening `modulate` to an
## opaque rest colour (0.2-0.36 s) wrote over the fade's alpha, and a knockback still wrote its position
## (cowir-battle 23726). Both live on the sprite's meta, so the death ends them here.
static func _own(sprite: Node2D) -> void:
	for key in ["flash_tween", "knockback_tween"]:
		if sprite.has_meta(key):
			var running = sprite.get_meta(key)
			if running is Tween and running.is_valid():
				running.kill()


## Plays `style` on `sprite`. `on_cue` fires at the moment the death sound belongs (right after the
## flash); `on_done` after the sprite is hidden. Returns the tween so a caller can chain onto it.
static func play(sprite: Node2D, style: String, on_cue: Callable = Callable(), on_done: Callable = Callable()) -> Tween:
	_own(sprite)
	var tween := real_time(sprite.create_tween())
	match style:
		"pixel_dissolve":
			_pixel_dissolve(sprite, tween, on_cue)
		"glitch_out":
			_glitch_out(sprite, tween, on_cue)
		_:
			_crt_off(sprite, tween, on_cue)
	tween.tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.visible = false
		if on_done.is_valid():
			on_done.call()
	)
	return tween


static func _cue(tween: Tween, on_cue: Callable) -> void:
	if on_cue.is_valid():
		tween.tween_callback(on_cue)


static func _base_scale(sprite: Node2D) -> Vector2:
	return sprite.get_meta("base_scale", sprite.scale)


## A TV switching off: white-out, the picture collapses to a bright horizontal line (with a two-frame
## RGB-split jitter on the way), the line shrinks to a dot, the dot fades out.
static func _crt_off(sprite: Node2D, tween: Tween, on_cue: Callable) -> void:
	var base := _base_scale(sprite)
	tween.tween_property(sprite, "modulate", Color(3.0, 3.0, 3.0, 1.0), CRT_FLASH)
	_cue(tween, on_cue)
	tween.tween_property(sprite, "scale", Vector2(base.x * 1.15, base.y * 0.03), CRT_LINE - CRT_FLASH) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if "offset" in sprite:
		var off: Vector2 = sprite.offset
		tween.parallel().tween_property(sprite, "offset", off + Vector2(3, 0), 0.04)
		tween.tween_property(sprite, "offset", off - Vector2(3, 0), 0.04)
		tween.tween_property(sprite, "offset", off, 0.04)
	tween.tween_property(sprite, "scale", Vector2(base.x * 0.03, base.y * 0.03), CRT_DOT - CRT_LINE) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "modulate:a", 0.0, CRT_END - CRT_DOT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Today's look, eased and on the wall clock: flash, then the shader's pixel dissolve (or an eased
## alpha fade where the sprite has no dissolve material).
static func _pixel_dissolve(sprite: Node2D, tween: Tween, on_cue: Callable) -> void:
	tween.tween_property(sprite, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.1)
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)
	_cue(tween, on_cue)
	var mat: Variant = (sprite as CanvasItem).material
	if mat is ShaderMaterial:
		tween.tween_method(func(v: float) -> void:
			if is_instance_valid(sprite) and sprite.material is ShaderMaterial:
				sprite.material.set_shader_parameter("dissolve_amount", v), 0.0, 1.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		tween.tween_property(sprite, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## A signal breaking up: flash, then the picture jitters sideways while it fades in eased steps.
static func _glitch_out(sprite: Node2D, tween: Tween, on_cue: Callable) -> void:
	tween.tween_property(sprite, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.08)
	_cue(tween, on_cue)
	var has_offset: bool = "offset" in sprite
	var off: Vector2 = sprite.offset if has_offset else Vector2.ZERO
	var steps := 6
	for i in range(steps):
		var a := 1.0 - float(i + 1) / float(steps)
		tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, a * a), 0.07)
		if has_offset:
			tween.parallel().tween_property(sprite, "offset", off + Vector2(4 if i % 2 == 0 else -4, 0), 0.07)
	if has_offset:
		tween.tween_property(sprite, "offset", off, 0.01)
