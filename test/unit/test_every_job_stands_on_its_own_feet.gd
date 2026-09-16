extends GutTest

## ⛔ ONE NUMBER WAS DOING TWO JOBS. Party sprites are centred on their slot, so a sheet whose figure
## stops short of the frame bottom floats inside it. Measured in a live battle before the fix:
##
##   fighter  feet 58.6 px below its slot        figure ends at y=162 of 256, and JOB_SCALE_OVERRIDES
##   cleric / rogue / mage / bard   78.8 px      1.4 multiplies that 30 px gap (cowir-sprites)
##
## `JOB_SCALE_OVERRIDES` sizes the figure and cannot place it. PARTY_FEET_BELOW_SLOT is the line the
## four frame-filling sheets already stood on, derived from the constants that produce it rather than
## tuned: the 64 px frame-bottom margin at the base scale = PARTY_SPRITE_HEIGHT * SPRITE_SCALE_BUMP / 4.
##
## These arms read the REAL starter sheets at the SHIPPED scale. A test-chosen scale would prove nothing:
## the defect is the interaction between a sheet's figure placement and the scale the game gives it.

const SceneScript = preload("res://src/battle/BattleScene.gd")
const AuraScript = preload("res://src/battle/AdvanceAura.gd")
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]
## The live spread before the fix was 20.2 px; a correct tree lands every job within a pixel.
const FEET_TOLERANCE_PX := 1.0


func _sprite_for(job: String) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = HybridSpriteLoader.load_sprite_frames(null, job, "", "", "", "")
	sprite.animation = &"idle"
	var s: float = SceneScript.party_sprite_scale(sprite.sprite_frames, job)
	sprite.scale = Vector2(s, s)
	add_child_autofree(sprite)
	return sprite


## Where this sheet's feet land relative to its SLOT: the figure's bottom, scaled, plus the correction.
func _feet_below_slot(sprite: AnimatedSprite2D, corrected: bool) -> float:
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture(&"idle", 0)
	var figure: Rect2 = AuraScript.figure_rect_of(tex)
	var uncorrected: float = (figure.end.y - tex.get_size().y * 0.5) * sprite.scale.y
	return uncorrected + (SceneScript.party_feet_correction(sprite) if corrected else 0.0)


func test_the_sheets_really_do_place_their_figures_differently() -> void:
	## CONTROL and anti-vacuity: without the correction the starters disagree by ~20 px, so the arm
	## below cannot pass by the sheets happening to agree.
	var lo := INF
	var hi := -INF
	for job in STARTERS:
		var v: float = _feet_below_slot(_sprite_for(job), false)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	assert_gt(hi - lo, 10.0, "uncorrected, the starter sheets' feet spread %.1f px — if this ever reaches 0 the guard is moot" % (hi - lo))


func test_every_starter_stands_on_the_same_line_below_its_slot() -> void:
	var offenders: Array = []
	for job in STARTERS:
		var feet: float = _feet_below_slot(_sprite_for(job), true)
		if absf(feet - SceneScript.PARTY_FEET_BELOW_SLOT) > FEET_TOLERANCE_PX:
			offenders.append("%s stands %.1f px below its slot, not %.1f" % [job, feet, SceneScript.PARTY_FEET_BELOW_SLOT])
	assert_eq(offenders.size(), 0, "a job floats in its slot: " + str(offenders))


func test_the_line_is_derived_from_the_layout_constants_not_tuned() -> void:
	## ⛔ A VALUE CHECK CANNOT SEE THIS. I predicted that hardcoding `78.75` would red this arm; it did not,
	## because the hardcode EQUALS the derivation today — the value arms would only notice later, when
	## PARTY_SPRITE_HEIGHT moves and the copy stops following. The claim is about the SHAPE, so it is
	## pinned on the shape, and the value arms stay as the check that the shape means what it says.
	var code: String = GdSourceHelper.code_of("res://src/battle/BattleScene.gd")
	assert_true(code.contains("const PARTY_FEET_BELOW_SLOT: float = PARTY_SPRITE_HEIGHT * SPRITE_SCALE_BUMP / 4.0"),
		"the standing line must be WRITTEN as the derivation, so it follows the layout constants it came from")
	assert_almost_eq(SceneScript.PARTY_FEET_BELOW_SLOT, SceneScript.PARTY_SPRITE_HEIGHT * SceneScript.SPRITE_SCALE_BUMP / 4.0, 0.001,
		"and the derivation is the frame-bottom margin at the base scale")
	assert_almost_eq(SceneScript.PARTY_FEET_BELOW_SLOT, 78.75, 0.01, "which is 78.75 px on today's constants")


func test_the_fighters_override_still_only_sizes_it() -> void:
	## The override stays — it is why the Fighter reads at the same size as the others. What it no longer
	## has to do is place the figure, which it could never do correctly anyway.
	var fighter := _sprite_for("fighter")
	var cleric := _sprite_for("cleric")
	assert_gt(fighter.scale.y, cleric.scale.y, "CONTROL: the Fighter is still scaled up by its override")
	assert_gt(SceneScript.party_feet_correction(fighter), 10.0, "and is the sheet that needed dropping")
	assert_lt(absf(SceneScript.party_feet_correction(cleric)), FEET_TOLERANCE_PX, "while a frame-filling sheet barely moves")


func test_an_unreadable_or_frameless_sprite_is_left_where_it_was() -> void:
	var bare := AnimatedSprite2D.new()
	add_child_autofree(bare)
	assert_eq(SceneScript.party_feet_correction(bare), 0.0, "no frames, no correction — never a nudge based on nothing")
	var empty := AnimatedSprite2D.new()
	empty.sprite_frames = SpriteFrames.new()
	add_child_autofree(empty)
	assert_eq(SceneScript.party_feet_correction(empty), 0.0, "an animation with no frames is left alone too")


func test_the_scene_applies_the_correction_where_it_places_the_sprite() -> void:
	## The arms above prove the arithmetic; this proves the sprite builder uses it. _create_party_sprites
	## needs a live battle to run, so this reads its stripped source.
	var code: String = GdSourceHelper.code_of("res://src/battle/BattleScene.gd")
	var at: int = code.find("base_pos += offset")
	assert_gt(at, -1, "CONTROL: the formation offset line survives stripping")
	assert_true(code.substr(at, 200).contains("base_pos.y += party_feet_correction(sprite)"),
		"the placement must apply the correction, or the arithmetic above is decoration")


const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
