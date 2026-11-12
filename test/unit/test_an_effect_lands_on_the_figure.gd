extends GutTest

## A party slot's anchor is the centre of its sprite FRAME, and a hero can stand well off that: in the .792 clips Protect's
## wall drew at the Fighter's back and Shell's dome over empty ground beside him (cowir-cutscenes 24028, cowir-main 24025),
## and Provoke's ring sat 80 px to his right (cowir-sprites 24032). Three sequences were patched with constants measured on
## one job. The fix is in the runner: a sequence's target and caster resolve to the FIGURE (BattleScene._figure_anchor), a
## bolt still leaves the HAND, and the constants are gone. These arms measure every job sheet in the manifest.

const SCENE := preload("res://src/battle/BattleScene.gd")
const FX := preload("res://src/battle/FractalFX.gd")
const MANIFEST := "res://data/sprite_manifest.json"
const SCALE := 1.5

var _scene = null
var _seen: Array = []


func before_each() -> void:
	_scene = SCENE.new()
	_seen = []


func after_each() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.free()
	_scene = null


## One AnimatedSprite2D per job sheet that has an idle strip: its first idle frame, as the battle draws it.
func _job_sprites() -> Dictionary:
	var out := {}
	var sheets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)).get("sheets", {})
	for job in sheets:
		var row: Dictionary = sheets[job]
		var path := str(row.get("path", "")) + "/idle.png"
		if not ResourceLoader.exists(path):
			continue
		var atlas := AtlasTexture.new()
		atlas.atlas = load(path)
		atlas.region = Rect2(0, 0, int(row.get("frame_width", 256)), int(row.get("frame_height", 256)))
		var frames := SpriteFrames.new()
		frames.add_animation(&"idle")
		frames.add_frame(&"idle", atlas)
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames
		spr.scale = Vector2(SCALE, SCALE)
		spr.position = Vector2(700, 300)
		add_child_autofree(spr)
		out[str(job)] = spr
	return out


## The figure's centre on screen, measured here from the pixels, independently of the helper under test.
func _measured_centre(spr: AnimatedSprite2D) -> Vector2:
	var tex: Texture2D = spr.sprite_frames.get_frame_texture(&"idle", 0)
	var img: Image = tex.get_image()
	var used: Rect2i = img.get_used_rect()
	var off: Vector2 = Vector2(used.get_center()) - Vector2(img.get_size()) * 0.5
	return spr.position + off * SCALE


func test_an_effect_is_aimed_at_every_jobs_body() -> void:
	var sprites := _job_sprites()
	assert_gt(sprites.size(), 12, "floor: the job sheets were read (%d)" % sprites.size())
	var off_centre := 0
	for job in sprites:
		var spr: AnimatedSprite2D = sprites[job]
		var aim: Vector2 = _scene._figure_anchor(spr)
		var body := _measured_centre(spr)
		assert_lt(aim.distance_to(body), 12.0 * SCALE, "%s: the aim is on the body (aim %s, body %s)" % [job, aim, body])
		off_centre += 1 if spr.position.distance_to(body) > 12.0 * SCALE else 0
	assert_gt(off_centre, 3, "CONTROL: several jobs stand OFF their frame's centre, so aiming at the frame misses them (%d)" % off_centre)
	var fighter: AnimatedSprite2D = sprites.get("fighter")
	assert_not_null(fighter, "CONTROL: the Fighter has a sheet")
	if fighter != null:
		assert_gt(_scene._stable_sprite_anchor(fighter).distance_to(_measured_centre(fighter)), 12.0 * SCALE,
			"CONTROL: the Fighter's frame centre is NOT on his body, which is what the clips showed")


func test_a_mirrored_sprite_is_aimed_on_its_mirrored_side() -> void:
	var fighter: AnimatedSprite2D = _job_sprites().get("fighter")
	if fighter == null:
		assert_not_null(fighter, "CONTROL: the Fighter has a sheet")
		return
	var plain: float = _scene._figure_anchor(fighter).x - fighter.position.x
	fighter.flip_h = true
	var flipped: float = _scene._figure_anchor(fighter).x - fighter.position.x
	assert_gt(absf(plain), 5.0, "CONTROL: the Fighter's body is off his frame centre (%.0f px)" % plain)
	assert_almost_eq(flipped, -plain, 2.0, "flipped, the body is on the other side by the same distance")


func test_the_hand_is_on_the_leading_edge_of_the_body() -> void:
	var fighter: AnimatedSprite2D = _job_sprites().get("fighter")
	if fighter == null:
		assert_not_null(fighter, "CONTROL: the Fighter has a sheet")
		return
	var body: Vector2 = _scene._figure_anchor(fighter)
	assert_lt(_scene._hand_anchor(fighter, -1.0).x, body.x, "facing left, the hand is left of the body's centre")
	assert_gt(_scene._hand_anchor(fighter, 1.0).x, body.x, "facing right, it is right of it")
	var bare := Node2D.new()
	add_child_autofree(bare)
	bare.position = Vector2(100, 100)
	assert_eq(_scene._hand_anchor(bare, -1.0), Vector2(60, 80), "CONTROL: a sprite with no frame keeps the old hand guess")


func _record(_kind: String, at: Vector2, _from: Vector2, _power: float, _phase: Dictionary) -> void:
	_seen.append(at)


## The runner's three origins: target, the caster's body, the caster's hand. A caller that passes no body keeps the hand.
func test_a_phase_resolves_its_origin() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var hand := Vector2(600, 280)
	var body := Vector2(650, 300)
	var target := Vector2(300, 300)
	var seq := {"phases": [{"kind": "gather", "origin": "caster"}, {"kind": "gather", "origin": "hand"}, {"kind": "gather"}]}
	var fx = FX.new(host, 5)
	fx.on_element_phase = _record
	fx.caster_centre = body
	fx.play(seq, hand, target)
	assert_eq(_seen, [body, hand, target], "caster = the body · hand = the hand · default = the target")
	_seen = []
	var old = FX.new(host, 5)
	old.on_element_phase = _record
	old.play(seq, hand, target)
	fx.on_element_phase = Callable()
	old.on_element_phase = Callable()
	assert_eq(_seen, [hand, hand, target], "CONTROL: with no body given, `caster` is the hand, as before this change")


## The cast path aims at the figure, and the per-job constants this replaces are gone from the data.
func test_the_runner_uses_it_and_the_constants_are_gone() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _play_ability_sequence(")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_gt(i, -1, "CONTROL: the cast path was found")
	assert_true(body.contains("_figure_anchor(ts)"), "a cast's target is the figure")
	assert_true(body.contains("caster_centre = _figure_anchor(caster_sprite)"), "and its caster's body is passed to the runner")
	assert_false(body.contains("_stable_sprite_anchor("), "nothing in the cast path aims at a frame centre")
	for id in ["protect_battle", "shell_battle", "fighter_provoke"]:
		for ph in FX.load_sequence(id).get("phases", []):
			for key in ["offset", "a_offset", "b_offset"]:
				if (ph as Dictionary).has(key):
					assert_lte(absf(float(ph[key][0])), 60.0, "%s: no phase carries a figure-sized x offset (%s %s)" % [id, key, str(ph[key])])
