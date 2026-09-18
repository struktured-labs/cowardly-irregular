extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## The enemy name label is a TARGETING AID (struktured 2026-08-15: "the monster ones are helpful
## tho"), so it has to belong to the monster it names. It was seated on the FRAME:
##   vertical    frame_h/2 + 6, while the figures' feet sit 6-77px above the frame bottom (114 sheets)
##   horizontal  x = -20 on an auto-width label, so its own centre landed at -20 + width/2 —
##               BAT -10px, SKELETON KNIGHT +26, PYRROTH +50. Longer name, bigger error.
## ENEMY_SCALE_BUMP (2.5) multiplies both on every <=128px sheet, and enemy slots are ~85px apart,
## so a label could sit nearer the monster below it than the one it names.

const SCENE := "res://src/battle/BattleScene.tscn"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const FRAME := 64
## The fixture's figure: inset 10 from the left, 30 from the right (centre +10), ending 20 above the frame bottom.
const FIG_L := 10
const FIG_R := 34
const FIG_BOTTOM := 44


## ⛔ THIS FILE LEFT 19 BattleManager FIELDS ON THE AUTOLOAD, INCLUDING FREED OBJECTS in
## player_party / all_combatants and as _died_callbacks KEYS. It loads the real BattleScene.tscn to
## measure a label against its monster, which is the right way to test it — and BattleScene._ready()
## writes the autoload unconditionally (set_autobattle_script at :477, then _start_test_battle ->
## _create_default_party + _spawn_enemies). Standing the scene up is sufficient; the test does
## nothing wrong.
##
## ⚠️ A BARE `BattleScene.new()` DOES NOT LEAK, AND NOT BECAUSE IT IS SAFER: with no scene tree an
## @onready node is null, _ready ABORTS on it, and the writes below never run (cowir-autogrind).
## 24 of the 26 files that stand up a BattleScene measured clean, mostly for that reason. Making
## _ready defensive would turn every one of them into a leaker — today's protection is an error.
var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func _scene() -> Node:
	var s = load(SCENE).instantiate()
	add_child_autofree(s)
	return s


## A frame whose figure is off-centre and clear of the frame's bottom edge.
func _sprite() -> AnimatedSprite2D:
	var img := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(14, FIG_BOTTOM):
		for x in range(FIG_L, FIG_R):
			img.set_pixel(x, y, Color(1, 1, 1, 1))
	var frames := SpriteFrames.new()
	frames.add_animation(&"idle")
	frames.add_frame(&"idle", ImageTexture.create_from_image(img))
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.animation = &"idle"
	add_child_autofree(s)
	return s


func _label_of(sprite: Node) -> Label:
	for c in sprite.get_children():
		if c is Label:
			return c
	return null


## The property, vertical: the label's top sits just under the figure's feet, not under the frame.
func test_the_label_sits_under_the_figures_feet() -> void:
	var scene := _scene()
	var spr := _sprite()
	scene._add_sprite_label(spr, "FIXTURE", 40.0)
	var label := _label_of(spr)
	assert_not_null(label, "the label must be added as a child of the sprite")
	if label == null:
		return
	var feet_local: float = float(FIG_BOTTOM) - float(FRAME) * 0.5
	assert_almost_eq(label.position.y, feet_local + scene.NAME_LABEL_GAP, 0.01,
		"the label must start NAME_LABEL_GAP under the feet (%.1f), not under the frame (%.1f)" % [
			feet_local + scene.NAME_LABEL_GAP, float(FRAME) * 0.5 + 6.0])
	# The GAP's value is cosmetic and deliberately not pinned to a number; these two bounds are the property.
	assert_gte(label.position.y, feet_local - 0.01, "the name must never ride up ON the figure")
	assert_lte(label.position.y - feet_local, 20.0, "and never float in the air below it")


## CONTROL: the two rules must disagree on this fixture, else every vertical assert here is free.
func test_control_the_frame_rule_would_be_lower() -> void:
	var feet_local: float = float(FIG_BOTTOM) - float(FRAME) * 0.5
	var frame_rule: float = float(FRAME) * 0.5 + 6.0
	assert_gt(frame_rule - (feet_local + 6.0), 15.0,
		"the fixture must leave real air below its figure, or the frame rule and the figure rule coincide")


## The property, horizontal: the label's own CENTRE lands on the figure's body centre.
func test_the_label_is_centred_on_the_body_not_at_a_fixed_offset() -> void:
	var scene := _scene()
	var spr := _sprite()
	scene._add_sprite_label(spr, "FIXTURE", 40.0)
	var label := _label_of(spr)
	assert_not_null(label)
	if label == null:
		return
	var body_centre: float = (float(FIG_L) + float(FIG_R)) * 0.5 - float(FRAME) * 0.5
	assert_almost_eq(label.position.x + label.size.x * 0.5, body_centre, 0.01,
		"the label's centre must land on the body centre (%+.1f), not at a fixed x plus half a text width" % body_centre)


## A long name must not push its own centre off the monster — the old bug was width-dependent.
func test_a_long_name_is_centred_like_a_short_one() -> void:
	var scene := _scene()
	var short_spr := _sprite()
	var long_spr := _sprite()
	scene._add_sprite_label(short_spr, "BAT", 40.0)
	scene._add_sprite_label(long_spr, "PYRROTH, THE EMBER WYRM", 40.0)
	var a := _label_of(short_spr)
	var b := _label_of(long_spr)
	assert_not_null(a)
	assert_not_null(b)
	if a == null or b == null:
		return
	assert_almost_eq(a.position.x + a.size.x * 0.5, b.position.x + b.size.x * 0.5, 0.01,
		"a 3-letter name and a 23-letter name must centre on the same point above them")


## flip_h mirrors the drawn frame but not its children, so the body centre mirrors with it.
func test_a_flipped_sprite_mirrors_its_body_centre() -> void:
	var scene := _scene()
	var spr := _sprite()
	spr.flip_h = true
	scene._add_sprite_label(spr, "FIXTURE", 40.0)
	var label := _label_of(spr)
	assert_not_null(label)
	if label == null:
		return
	var body_centre: float = (float(FIG_L) + float(FIG_R)) * 0.5 - float(FRAME) * 0.5
	assert_almost_eq(label.position.x + label.size.x * 0.5, -body_centre, 0.01,
		"a flipped sheet draws its body on the other side, so the name must follow it")


## No readable frame: fall back to the caller's drop and the sprite's own origin, never to nothing.
func test_an_unreadable_sprite_falls_back_to_the_callers_drop() -> void:
	var scene := _scene()
	var spr := AnimatedSprite2D.new()
	add_child_autofree(spr)
	scene._add_sprite_label(spr, "FIXTURE", 40.0)
	var label := _label_of(spr)
	assert_not_null(label)
	if label == null:
		return
	assert_eq(label.position.y, 40.0, "with no frame to read, the caller's drop stands")
	assert_almost_eq(label.position.x + label.size.x * 0.5, 0.0, 0.01,
		"and the label centres on the sprite's own origin")


## END TO END on the built battle: every enemy's real label must sit on its own figure.
func test_every_built_enemy_label_sits_on_its_own_figure() -> void:
	var scene := _scene()
	var enemies: Array = scene.enemy_sprite_nodes
	assert_gt(enemies.size(), 0, "PRECONDITION: enemy sprites must build, else this measures nothing")
	var pads: Array = []
	for spr in enemies:
		if not is_instance_valid(spr) or spr.sprite_frames == null:
			continue
		if not spr.sprite_frames.has_animation(&"idle") or spr.sprite_frames.get_frame_count(&"idle") == 0:
			continue
		var tex: Texture2D = spr.sprite_frames.get_frame_texture(&"idle", 0)
		var img: Image = tex.get_image()
		if img == null or img.is_empty():
			continue
		var used: Rect2i = img.get_used_rect()
		if used.size.y <= 0:
			continue
		var label := _label_of(spr)
		assert_not_null(label, "every enemy sprite must carry its name label")
		if label == null:
			continue
		var h: float = float(tex.get_height())
		var feet_local: float = float(used.end.y) - h * 0.5
		pads.append(h * 0.5 + 6.0 - (feet_local + scene.NAME_LABEL_GAP))
		assert_almost_eq(label.position.y, feet_local + scene.NAME_LABEL_GAP, 1.0,
			"%s: the label must sit under its own feet" % spr.name)
		assert_gte(label.position.y, feet_local - 1.0, "%s: never ON the figure" % spr.name)
		assert_lte(label.position.y - feet_local, 20.0, "%s: never floating below it" % spr.name)
		var body_centre: float = float(used.position.x) + float(used.size.x) * 0.5 - float(tex.get_width()) * 0.5
		if spr.flip_h:
			body_centre = -body_centre
		assert_almost_eq(label.position.x + label.size.x * 0.5, body_centre, 1.0,
			"%s: the label must centre on its own body" % spr.name)
	pads.sort()
	gut.p("built enemies measured: %d · air removed under each name: %s px" % [pads.size(), str(pads)])
	assert_gt(pads.size(), 0, "at least one built enemy must have a readable sheet")
	if pads.is_empty():
		return
	assert_gt(pads[-1], 4.0,
		"ANTI-VACUITY: some built enemy's sheet must still pad its frame (%s px of air under the old rule), else the frame rule and the figure rule agree here" % str(pads))

## This file instantiates BattleScene.tscn, whose `_ready` starts a battle — so the battle flow
## calls play_music and leaves `_current_music` and `_music_playing` behind, without this file
## naming either. A `BS.new()` script construction aborts in `_ready` (null @onready) and leaks
## nothing; instantiating the SCENE lets it run, which is why only the .tscn files are affected.
func after_all() -> void:
	SoundState.restore()
