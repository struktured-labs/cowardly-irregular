extends GutTest

## Smoke-log find 2026-07-03: artist monster sheets ship a "dead"
## animation, but BattleScene death paths call play_defeat() → "defeat",
## which only procedural sprites define. Result: every sheet-based
## monster froze on its last frame instead of playing the death anim
## the artist drew. BattleAnimator.ANIM_FALLBACKS bridges the two
## vocabularies in both directions.


func _make_sprite(anims: Array) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	for a in anims:
		sf.add_animation(a)
		sf.add_frame(a, ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8)))
	s.sprite_frames = sf
	add_child_autofree(s)
	return s


func test_defeat_falls_back_to_dead_on_artist_sheets() -> void:
	var animator := BattleAnimator.new()
	add_child_autofree(animator)
	animator.sprite = _make_sprite(["idle", "dead"])
	animator.play_defeat()
	assert_eq(animator.sprite.animation, &"dead",
		"artist sheet (no 'defeat') must play its 'dead' anim, not freeze")


func test_dead_falls_back_to_defeat_on_procedural_sprites() -> void:
	var animator := BattleAnimator.new()
	add_child_autofree(animator)
	animator.sprite = _make_sprite(["idle", "defeat"])
	animator.play_animation(BattleAnimator.AnimState.DEAD)
	assert_eq(animator.sprite.animation, &"defeat",
		"procedural sprite (no 'dead') must play 'defeat' via the reverse mapping")


func test_exact_name_still_wins_over_fallback() -> void:
	var animator := BattleAnimator.new()
	add_child_autofree(animator)
	animator.sprite = _make_sprite(["idle", "dead", "defeat"])
	animator.play_defeat()
	assert_eq(animator.sprite.animation, &"defeat",
		"fallback must not hijack sprites that define the requested anim")


func test_every_manifest_monster_sheet_can_die_on_screen() -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var missing: Array = []
	for monster_id in m.get("monster_sheets", {}):
		var anims: Dictionary = m["monster_sheets"][monster_id].get("animations", {})
		if anims.is_empty():
			continue
		if not (anims.has("dead") or anims.has("defeat")):
			missing.append(monster_id)
	assert_eq(missing.size(), 0,
		"monster sheets with NO death anim under either name (they'd freeze on kill): %s" % str(missing))
