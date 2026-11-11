extends GutTest

## cowir-adhoc's animation audit (23674), built on cowir-main 23675. Every action armed a flat 0.7 s idle snap,
## and a melee swing only starts at contact (t≈0.17), so a swing got 0.53 s: 4 frames at 8 fps. The mage's 10,
## the cleric's 9, Mordaine's 13 were cut at frame 4, with the attacker already walking home. Now a one-shot is
## PACED into a budget (every frame drawn), the attacker holds at the target for the swing at spotlight speeds,
## the snap waits for a pose still drawing, a sheet may author the frame its hit lands on, a bespoke ability
## pose returns to idle by itself, and a knocked sprite comes to rest at its home.

const SCENE := preload("res://src/battle/BattleScene.gd")
const ANIMATOR := preload("res://src/battle/BattleAnimator.gd")
const MANIFEST := "res://data/sprite_manifest.json"
var _saved_scale := 1.0


func before_each() -> void:
	_saved_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _saved_scale


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "VOID: sprite_manifest.json did not parse")
	return parsed if parsed is Dictionary else {}


func _animator(frames: SpriteFrames, parent: Node, x: float = 400.0) -> ANIMATOR:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.position = Vector2(x, 0)
	parent.add_child(sprite)
	sprite.play("idle")
	var animator: ANIMATOR = ANIMATOR.new()
	animator.setup(sprite)
	parent.add_child(animator)
	return animator


func _scene() -> Node:
	var scene = SCENE.new()
	add_child_autofree(scene)
	return scene


## Every attack sheet the game can load: [label, SpriteFrames].
func _attack_sheets() -> Array:
	var out: Array = []
	var m := _manifest()
	HybridSpriteLoader._load_manifest()
	for job in (m.get("sheets", {}) as Dictionary).keys():
		var entry = m["sheets"][job]
		if not (entry is Dictionary) or not entry.has("path"):
			continue
		var frames: SpriteFrames = HybridSpriteLoader._load_external_sheet(entry, str(job))
		if frames and frames.has_animation("attack"):
			out.append(["job " + str(job), frames])
	for monster in (m.get("monster_sheets", {}) as Dictionary).keys():
		var entry = m["monster_sheets"][monster]
		if not (entry is Dictionary) or not entry.has("path"):
			continue
		var frames: SpriteFrames = HybridSpriteLoader.load_monster_sprite_frames(str(monster))
		if frames and frames.has_animation("attack"):
			out.append(["monster " + str(monster), frames])
	return out


## Derived from the manifest: at BOTH paces every attack sheet's played length fits its budget, and the
## fast-pace budget ends before the idle snap. CONTROLs: the corpus is real, long sheets exist (unpaced they
## overrun), and the fighter's 4-frame swing is untouched.
func test_every_attack_sheet_draws_all_its_frames_before_the_snap() -> void:
	var scene := _scene()
	var sheets := _attack_sheets()
	assert_gt(sheets.size(), 100, "VOID: only %d attack sheets loaded" % sheets.size())
	var overran_unpaced := 0
	for row in sheets:
		var animator := _animator(row[1], scene)
		var length: float = animator.animation_length("attack")
		assert_gt(length, 0.0, "VOID: %s attack has no length" % row[0])
		if length > 0.53:
			overran_unpaced += 1
		for budget in [SCENE.SWING_WINDOW, SCENE.SWING_CAP]:
			animator.swing_budget_provider = func() -> float: return budget
			assert_lte(animator.played_length("attack"), budget + 0.001, "%s attack plays %.2f s in a %.2f s budget: its last frames are cut" % [row[0], animator.played_length("attack"), budget])
			assert_gte(animator.rate_for("attack"), 1.0, "%s attack was slowed down" % row[0])
		animator.sprite.queue_free()
		animator.queue_free()
	assert_gt(overran_unpaced, 15, "CONTROL: only %d sheets were longer than the old 0.53 s window; the corpus changed" % overran_unpaced)
	## The fast pace's timeline is .790's: contact at 0.17, then the window, all before the 0.7 s snap.
	assert_lte(0.05 + 0.12 + SCENE.SWING_WINDOW, 0.7 + 0.001, "the fast-pace swing window runs past the idle snap")
	var fighter: SpriteFrames = HybridSpriteLoader._load_external_sheet(_manifest()["sheets"]["fighter"], "fighter")
	var fa := _animator(fighter, scene)
	fa.swing_budget_provider = func() -> float: return SCENE.SWING_WINDOW
	assert_eq(fa.rate_for("attack"), 1.0, "CONTROL: the fighter's 4-frame swing fits and must play at its authored rate")


## The real path, on the mage's real 10-frame sheet: lunge, swing, the 0.7 s snap. Every frame is drawn, and
## the last one while the mage is still at the target.
func _swing_frames(time_scale: float, turbo: bool) -> Dictionary:
	Engine.time_scale = time_scale
	var scene := _scene()
	scene.turbo_mode = turbo
	var mage: SpriteFrames = HybridSpriteLoader._load_external_sheet(_manifest()["sheets"]["mage"], "mage")
	var animator := _animator(mage, scene, 600.0)
	animator.swing_budget_provider = scene.swing_budget
	var attacker: AnimatedSprite2D = animator.sprite
	var target := AnimatedSprite2D.new()
	target.position = Vector2(100, 0)
	scene.add_child(target)
	var seen := {}
	var away_at_last := [false]
	var last: int = mage.get_frame_count("attack") - 1
	attacker.frame_changed.connect(func() -> void:
		if attacker.animation == &"attack":
			seen[attacker.frame] = true
			if attacker.frame == last:
				away_at_last[0] = attacker.position.distance_to(Vector2(600, 0)) > 100.0)
	scene._animate_melee_attack(attacker, target, animator, null)
	var lunge: float = scene._last_lunge_length
	get_tree().create_timer(0.7).timeout.connect(scene._delayed_snap_and_idle.bind(attacker, animator))
	var t0 := Time.get_ticks_msec()
	var swung := false
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		if attacker.animation == &"attack":
			swung = true
			seen[attacker.frame] = true
		elif swung:
			break
	return {"seen": seen.size(), "frames": last + 1, "away": away_at_last[0], "idle": attacker.animation == &"idle", "lunge": lunge}


func test_a_long_swing_shows_every_frame_and_finishes_at_the_target() -> void:
	var r: Dictionary = await _swing_frames(0.5, false)
	assert_eq(r["frames"], 10, "VOID: the mage's attack is no longer 10 frames")
	assert_eq(r["seen"], r["frames"], "the mage's swing drew %d of %d frames before idle" % [r["seen"], r["frames"]])
	assert_true(r["away"], "the swing's last frame was drawn after the mage had walked home")
	assert_true(r["idle"], "the mage never returned to idle after the swing")


## cowir-autogrind 23678: under turbo (and the console, and 4x+) the lunge is .790's length exactly, and every
## frame is still drawn inside it.
func test_turbo_keeps_the_old_lunge_and_still_draws_every_frame() -> void:
	var r: Dictionary = await _swing_frames(0.5, true)
	assert_almost_eq(float(r["lunge"]), 0.12 + SCENE.STRIKE_HOLD + 0.18, 0.051, "turbo's lunge changed length (%.2f s)" % r["lunge"])
	assert_eq(r["seen"], r["frames"], "at turbo the mage's swing drew %d of %d frames" % [r["seen"], r["frames"]])
	assert_eq(SCENE.strike_hold(1.25, false), SCENE.STRIKE_HOLD, "a fast-pace strike hold grew with the swing")
	assert_gt(SCENE.strike_hold(0.75, true), SCENE.STRIKE_HOLD, "CONTROL: at spotlight pace the hold must follow the swing")
	assert_eq(SCENE.strike_hold(0.125, true), SCENE.STRIKE_HOLD, "a 1-frame sheet (sprites' repointed attacks) must keep the old hold")


func _two_pose_frames() -> SpriteFrames:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", tex)
	frames.add_animation("cleave")
	frames.set_animation_loop("cleave", false)
	frames.set_animation_speed("cleave", 30.0)
	for i in 3:
		frames.add_frame("cleave", tex)
	return frames


## A bespoke ability pose carried current_state IDLE, so it held its last frame until the scene's snap.
func test_a_bespoke_ability_pose_returns_to_idle_by_itself() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var animator := _animator(_two_pose_frames(), holder)
	animator.play_named_animation("cleave")
	assert_eq(animator.sprite.animation, &"cleave", "CONTROL: the bespoke pose must play")
	await wait_seconds(0.4)
	assert_eq(animator.sprite.animation, &"idle", "the bespoke pose finished and never returned to idle")
	assert_true(animator.sprite.is_playing(), "the idle it returned to isn't playing")


## Two hits inside the first's knockback captured a displaced origin and parked the monster off its mark.
func test_rapid_hits_leave_a_monster_at_its_home() -> void:
	var scene := _scene()
	for weakness in [false, true]:
		var s := AnimatedSprite2D.new()
		s.position = Vector2(300, 200)
		s.set_meta("home_position", Vector2(300, 200))
		scene.add_child(s)
		for i in 3:
			if weakness:
				scene._apply_weakness_hit_knockback(s, -1.0, 2.0)
			else:
				scene._apply_hit_knockback(s, -1.0)
			await wait_seconds(0.05)
		assert_gt(s.position.distance_to(Vector2(300, 200)), 0.5, "CONTROL: the sprite must be mid-knockback right after the hits")
		await wait_seconds(0.5)
		assert_almost_eq(s.position.x, 300.0, 0.01, "three rapid %s hits left the monster %.1f px off its mark" % ["weakness" if weakness else "plain", s.position.x - 300.0])
		assert_almost_eq(s.position.y, 200.0, 0.01, "three rapid hits left the monster off its floor line")


## An authored impact frame is real data: inside its animation and past frame 0. And a plain attack at
## spotlight pace holds its damage for it, while turbo lands at contact as before.
func test_an_impact_frame_holds_the_hit_until_the_art_lands() -> void:
	var m := _manifest()
	var authored := 0
	for job in m["sheets"].keys():
		var entry = m["sheets"][job]
		if entry is Dictionary and entry.has("impact_frames"):
			var frames: SpriteFrames = HybridSpriteLoader._load_external_sheet(entry, str(job))
			for anim in entry["impact_frames"].keys():
				authored += 1
				assert_true(frames != null and frames.has_animation(anim), "%s declares an impact frame for a pose it lacks: %s" % [job, anim])
				assert_between(int(entry["impact_frames"][anim]), 1, frames.get_frame_count(anim) - 1, "%s %s impact frame is outside the animation" % [job, anim])
	for monster in m["monster_sheets"].keys():
		var entry = m["monster_sheets"][monster]
		if not (entry is Dictionary) or not (entry.get("animations") is Dictionary):
			continue
		for anim in entry["animations"].keys():
			var a = entry["animations"][anim]
			if a is Dictionary and a.has("impact"):
				authored += 1
				assert_between(int(a["impact"]), 1, int(a.get("end", 0)) - int(a.get("start", 0)), "%s %s impact frame is outside the animation" % [monster, anim])
	assert_gt(authored, 3, "VOID: no impact frames are authored")
	for turbo in [false, true]:
		Engine.time_scale = 0.5
		var scene := _scene()
		scene.turbo_mode = turbo
		var mage: SpriteFrames = HybridSpriteLoader._load_external_sheet(m["sheets"]["mage"], "mage")
		var animator := _animator(mage, scene, 600.0)
		animator.swing_budget_provider = scene.swing_budget
		var target := AnimatedSprite2D.new()
		target.position = Vector2(100, 0)
		scene.add_child(target)
		scene._animate_melee_attack(animator.sprite, target, animator, null, 0.0, "", true)
		match turbo:
			true:
				assert_null(scene._full_render_dmg_buffer, "turbo held the hit for an impact frame; it must land at contact as in .790")
			false:
				assert_gt(animator.impact_time("attack"), 0.1, "CONTROL: the mage's swing has an impact frame past its start")
				assert_not_null(scene._full_render_dmg_buffer, "a plain attack at spotlight pace didn't hold its damage for the impact frame")
				await wait_seconds(1.6)
				assert_null(scene._full_render_dmg_buffer, "the held hit never landed")


## cowir-battle 23687: a battle that ends mid-swing (the killing blow, an escape, a wipe) lands the held hit at
## once, before the defeat scene and the victory flow, and the swing's own callback then finds nothing to land.
func test_a_battle_that_ends_mid_swing_lands_the_held_hit_first() -> void:
	var scene := _scene()
	var token: int = scene._hold_melee_damage(5.0)
	assert_not_null(scene._full_render_dmg_buffer, "CONTROL: the hold must open the damage buffer")
	scene._land_held_hit()
	assert_null(scene._full_render_dmg_buffer, "ending the battle left the swing's hit in the buffer")
	scene._full_render_dmg_buffer = []  # a later Full Render cast's buffer: the spent swing must not flush it
	scene._land_melee_damage(token)
	assert_not_null(scene._full_render_dmg_buffer, "the spent swing landed a second time, into another cast's buffer")
	scene._full_render_dmg_buffer = null
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var at := src.find("func _on_battle_ended")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_gt(body.find("_land_held_hit()"), -1, "_on_battle_ended never lands a held hit")
	assert_lt(body.find("_land_held_hit()"), body.find("_stage_defeat_scene("), "the held hit must land before the defeat scene")
