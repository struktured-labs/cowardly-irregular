extends GutTest

## struktured, playing .792: "sometimes a player or monster is attacking someone but aims center", "its when a character
## moves to attack something". The lunge stopped on the line between the two sprites' FRAME homes, a contact gap short of
## the target's home: aimed at another row it halted off the target's row, toward the middle of the field, and since
## .791 it holds there for the whole swing. It now stands beside the target figure, feet level with the target's feet.

const BS := preload("res://src/battle/BattleScene.gd")
const AdvanceAura := preload("res://src/battle/AdvanceAura.gd")
const FRAME := 96


## A sprite whose opaque figure is `fig` (frame px) inside a FRAME x FRAME frame, resting at `home`.
func _sprite(fig: Rect2i, home: Vector2, scale: float = 1.0, flip: bool = false) -> AnimatedSprite2D:
	var img := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(fig, Color(1, 1, 1, 1))
	var frames := SpriteFrames.new()
	frames.add_animation(&"idle")
	frames.add_frame(&"idle", ImageTexture.create_from_image(img))
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.animation = &"idle"
	s.scale = Vector2(scale, scale)
	s.flip_h = flip
	s.position = home
	s.set_meta("home_position", home)
	add_child_autofree(s)
	return s


## The figure's rect in the parent's space with the sprite standing at `at`.
func _figure_at(s: AnimatedSprite2D, at: Vector2) -> Rect2:
	var local: Rect2 = AdvanceAura.figure_rect_in_sprite(s, &"idle")
	return Rect2(at + local.position, local.size)


## The old stop: a contact gap short of the target's home, along the line between the two homes.
func _old_stop(a: AnimatedSprite2D, t: AnimatedSprite2D) -> Vector2:
	var ah: Vector2 = a.get_meta("home_position")
	var th: Vector2 = t.get_meta("home_position")
	return th - (th - ah).normalized() * BS._melee_contact_gap(a, t)


func test_an_attacker_from_another_row_stands_on_its_targets_row() -> void:
	## A hero up-right of a monster two rows down: both figures off-centre in their frames, as the artist sheets are.
	var hero := _sprite(Rect2i(10, 20, 40, 70), Vector2(900, 200), 2.0)
	var monster := _sprite(Rect2i(40, 30, 44, 56), Vector2(300, 520), 2.5)
	var stop: Vector2 = BS.melee_stand_point(hero, monster)
	var hero_fig := _figure_at(hero, stop)
	var monster_fig := _figure_at(monster, monster.get_meta("home_position"))
	assert_almost_eq(hero_fig.end.y, monster_fig.end.y, 0.5, "the attacker's feet are level with the target's feet")
	assert_almost_eq(hero_fig.position.x - monster_fig.end.x, BS.MELEE_CONTACT_MERCY_PX, 0.5, "its leading edge stops a mercy short of the target's facing edge")
	var old_fig := _figure_at(hero, _old_stop(hero, monster))
	assert_gt(absf(old_fig.end.y - monster_fig.end.y), 40.0,
		"CONTROL: the old diagonal stop left the attacker's feet %.0f px off the target's row" % absf(old_fig.end.y - monster_fig.end.y))


func test_a_monster_reaches_a_hero_in_another_row_the_same_way() -> void:
	var monster := _sprite(Rect2i(40, 30, 44, 56), Vector2(280, 180), 2.5)
	var hero := _sprite(Rect2i(10, 20, 40, 70), Vector2(980, 560), 2.0)
	var stop: Vector2 = BS.melee_stand_point(monster, hero)
	var monster_fig := _figure_at(monster, stop)
	var hero_fig := _figure_at(hero, hero.get_meta("home_position"))
	assert_almost_eq(monster_fig.end.y, hero_fig.end.y, 0.5, "feet level with the hero's")
	assert_almost_eq(hero_fig.position.x - monster_fig.end.x, BS.MELEE_CONTACT_MERCY_PX, 0.5, "and its leading edge a mercy short of him, from the left")


func test_on_one_row_the_stop_is_where_it_always_was() -> void:
	## Same feet line: the diagonal was already horizontal, so the new point must equal the old one (the .790 feel is kept).
	var hero := _sprite(Rect2i(10, 20, 40, 70), Vector2(900, 400), 2.0)
	var monster := _sprite(Rect2i(40, 20, 44, 70), Vector2(300, 400), 2.0)
	var stop: Vector2 = BS.melee_stand_point(hero, monster)
	var old: Vector2 = _old_stop(hero, monster)
	assert_almost_eq(stop.x, old.x, 0.5, "CONTROL: level with its target, the stop's x is the contact gap's, unchanged")
	assert_almost_eq(stop.y, old.y, 0.5, "and its y is the row both stand on")


func test_a_flipped_sheet_is_measured_as_it_is_drawn() -> void:
	var hero := _sprite(Rect2i(10, 20, 40, 70), Vector2(900, 200), 2.0, true)
	var monster := _sprite(Rect2i(40, 30, 44, 56), Vector2(300, 520), 2.5)
	var stop: Vector2 = BS.melee_stand_point(hero, monster)
	var gap: float = _figure_at(hero, stop).position.x - _figure_at(monster, monster.get_meta("home_position")).end.x
	assert_almost_eq(gap, BS.MELEE_CONTACT_MERCY_PX, 0.5, "a flipped attacker's leading edge is its mirrored one")


func test_an_unreadable_frame_keeps_the_old_point() -> void:
	var hero := _sprite(Rect2i(10, 20, 40, 70), Vector2(900, 200), 2.0)
	var bare := Node2D.new()
	add_child_autofree(bare)
	bare.position = Vector2(300, 520)
	var stop: Vector2 = BS.melee_stand_point(hero, bare)
	var expect: Vector2 = Vector2(300, 520) - (Vector2(300, 520) - Vector2(900, 200)).normalized() * BS.MELEE_CONTACT_FALLBACK_PX
	assert_almost_eq(stop.x, expect.x, 0.5, "no figure to measure: the fallback gap along the line, as before")
	assert_almost_eq(stop.y, expect.y, 0.5, "in y too")


func test_the_lunge_goes_to_the_stand_point_and_a_summon_has_a_home() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var at := src.find("func _animate_melee_attack(")
	assert_gt(at, -1, "CONTROL: the lunge exists")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true("melee_stand_point(attacker_sprite, target_sprite)" in body, "the lunge's stop is the stand point")
	assert_false("target_pos - direction * contact_gap" in body, "and the diagonal stop is gone")
	var spawn := src.find("_enemy_base_positions.append(sprite.position)")
	assert_gt(spawn, -1, "CONTROL: the summon spawn keeps its base position")
	assert_true("set_meta(\"home_position\", sprite.position)" in src.substr(spawn, 400), "a summoned enemy is given its home where it spawns")
