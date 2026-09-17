extends GutTest
const ImageProbe := preload("res://test/unit/helpers/image_probe.gd")

## ⛔ THE LUNGE STOPPED A GOBLIN-AND-A-HALF SHORT. `_melee_contact_gap` summed FRAME half-widths, which
## is padding, not the character — while its own docstring said "stop where the attacker's weapon frame
## reaches the target's visible edge". Measured in a live battle on the shipped sheets:
##
##   goblin   128 px frame at 2.5x   frame half-width 160 px   figure edge 32 px from its origin
##   fighter / cleric / rogue / mage / bard   halted 209-221 px short of contact
##
## The 2026-07 fix cured the opposite error — stopping 88 px INSIDE the goblin — by swapping a 40 px
## constant for frame halves. Right direction, off by the padding (cowir-adhoc 11472).
##
## Fixed: each sprite is measured on the side FACING the other, from its figure's opaque bounds.

const SceneScript = preload("res://src/battle/BattleScene.gd")
const AuraScript = preload("res://src/battle/AdvanceAura.gd")


func _sprite(frames: SpriteFrames, scale: float, at: Vector2, flip: bool = false) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.animation = &"idle"
	s.scale = Vector2(scale, scale)
	s.position = at
	s.flip_h = flip
	add_child_autofree(s)
	return s


## flip_h TRUE and scale 2.5, because that is what the battle builds: enemy sheets are authored facing
## one way and flipped to face the party, and ENEMY_SCALE_BUMP applies to every <=128 px sheet. ⚠️ My
## first fixture skipped the flip and measured the goblin's figure at 105 px instead of the live 32 —
## the figure is off-centre in its frame, so the mirror is not cosmetic.
func _goblin(at: Vector2) -> AnimatedSprite2D:
	return _sprite(HybridSpriteLoader.load_monster_sprite_frames("goblin"), 2.5, at, true)


func _fighter(at: Vector2) -> AnimatedSprite2D:
	var frames := HybridSpriteLoader.load_sprite_frames(null, "fighter", "", "", "", "")
	return _sprite(frames, SceneScript.party_sprite_scale(frames, "fighter"), at)


func test_the_goblins_frame_is_mostly_padding() -> void:
	## CONTROL and anti-vacuity: if a sheet's figure ever fills its frame this guard proves nothing, so
	## the gap between the two measurements is asserted first.
	var goblin := _goblin(Vector2(300, 300))
	var figure: Rect2 = AuraScript.figure_rect_in_sprite(goblin)
	var frame_half: float = goblin.sprite_frames.get_frame_texture(&"idle", 0).get_size().x * 0.5 * goblin.scale.x
	assert_gt(frame_half, figure.end.x * 2.0,
		"the goblin's frame half-width (%.0f) must dwarf its figure's leading edge (%.0f), or there was nothing to fix" % [frame_half, figure.end.x])


func test_the_gap_is_the_two_figures_plus_the_mercy_margin() -> void:
	var goblin := _goblin(Vector2(300, 300))
	var fighter := _fighter(Vector2(880, 300))
	var gap: float = SceneScript._melee_contact_gap(fighter, goblin)
	var expected: float = absf(AuraScript.figure_rect_in_sprite(fighter).position.x) \
		+ AuraScript.figure_rect_in_sprite(goblin).end.x + SceneScript.MELEE_CONTACT_MERCY_PX
	assert_almost_eq(gap, expected, 0.01, "the gap is figure-edge to figure-edge plus the mercy margin")
	var fw := ImageProbe.frame_width_of(fighter.sprite_frames, &"idle", 0)
	var gw := ImageProbe.frame_width_of(goblin.sprite_frames, &"idle", 0)
	assert_eq(fw.size() + gw.size(), 2,
		"reading a frame size ABORTED rather than measuring it, so the comparison below is free")
	if fw.is_empty() or gw.is_empty():
		return
	var frame_gap: float = (fw[0] * 0.5 * fighter.scale.x) \
		+ (gw[0] * 0.5 * goblin.scale.x) + SceneScript.MELEE_CONTACT_MERCY_PX
	assert_lt(gap, frame_gap - 150.0,
		"and it is far closer than the frame rule it replaced (%.0f vs %.0f) — the live shortfall was 209-221 px" % [gap, frame_gap])


func test_each_sprite_is_measured_on_the_side_that_faces_the_other() -> void:
	## A figure sits off-centre in its frame (the Fighter's sword reaches left), so one symmetric
	## half-width is wrong on one of the two edges. Swap who stands on the left and the leads swap.
	var fighter_right := _fighter(Vector2(880, 300))
	var goblin_left := _goblin(Vector2(300, 300))
	var facing_left: float = SceneScript._melee_contact_gap(fighter_right, goblin_left)
	var fighter_left := _fighter(Vector2(300, 300))
	var goblin_right := _goblin(Vector2(880, 300))
	var facing_right: float = SceneScript._melee_contact_gap(fighter_left, goblin_right)
	var fig: Rect2 = AuraScript.figure_rect_in_sprite(fighter_right)
	assert_ne(absf(fig.position.x), fig.end.x, "CONTROL: the Fighter's figure is off-centre in its frame, so the two sides differ")
	assert_ne(facing_left, facing_right, "so the gap depends on which way the attacker travels")
	assert_almost_eq(facing_right, fig.end.x + absf(AuraScript.figure_rect_in_sprite(goblin_right).position.x) + SceneScript.MELEE_CONTACT_MERCY_PX, 0.01,
		"travelling right, each sprite is measured on its own right/left edge respectively")


func test_an_unmeasurable_sprite_keeps_the_pre_fix_constant() -> void:
	var goblin := _goblin(Vector2(300, 300))
	var bare := Node2D.new()
	add_child_autofree(bare)
	assert_eq(SceneScript._melee_contact_gap(bare, goblin), SceneScript.MELEE_CONTACT_FALLBACK_PX,
		"a sprite with no frames falls back to the pre-fix 40, never to the mercy margin alone")
	var empty := AnimatedSprite2D.new()
	empty.sprite_frames = SpriteFrames.new()
	add_child_autofree(empty)
	assert_eq(SceneScript._melee_contact_gap(empty, goblin), SceneScript.MELEE_CONTACT_FALLBACK_PX,
		"and so does one whose animation has no frames")


func test_the_lunge_aims_at_that_gap() -> void:
	## The arms above prove the arithmetic; this proves the animation consumes it.
	var code: String = GdSourceHelper.code_of("res://src/battle/BattleScene.gd")
	var at: int = code.find("func _animate_melee_attack(")
	assert_gt(at, -1, "CONTROL: the melee animation survives stripping")
	var body: String = code.substr(at, 2500)
	assert_true(body.contains("_melee_contact_gap(attacker_sprite, target_sprite)"), "the stop distance comes from the gap helper")
	assert_true(body.contains("target_pos - direction * contact_gap"), "and the lunge stops that far short of the target's home")
	assert_false(body.contains("direction * 40"), "the pre-fix 40 px hardcode stays gone")


const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
