extends GutTest

## Live-log find 2026-07-04: "Animation 'cast' not found!" fired when the
## Rogue's Backstab requested a cast anim the sheet lacked — the sprite
## froze + warned instead of degrading. The old single-level fallback
## only bridged defeat↔dead. Now ANIM_FALLBACKS is a cycle-guarded chain
## resolved by _resolve_animation, terminating at attack → idle, so every
## ability-specific anim (backstab, cast_fire, battle_hymn, cast) plays
## SOMETHING rather than freezing.


func _sprite(anims: Array) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	for a in anims:
		sf.add_animation(a)
		sf.add_frame(a, ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8)))
	s.sprite_frames = sf
	add_child_autofree(s)
	return s


func _animator(anims: Array) -> BattleAnimator:
	var a := BattleAnimator.new()
	add_child_autofree(a)
	a.sprite = _sprite(anims)
	return a


func test_cast_falls_back_to_attack() -> void:
	var a := _animator(["idle", "attack", "hit"])  # no cast
	assert_eq(a._resolve_animation("cast"), "attack",
		"a caster with no 'cast' anim must swing (attack), not freeze — this is the exact live-log warning")


func test_magic_special_chains_through_cast_to_attack() -> void:
	var a := _animator(["idle", "attack"])  # no cast_fire, no cast
	assert_eq(a._resolve_animation("cast_fire"), "attack",
		"cast_fire → cast → attack chain must resolve to attack")


func test_windup_anims_are_NOT_remapped() -> void:
	# lunge/advance/defer keep their synchronous-skip contract (commit
	# 0a02aed) — they must NOT resolve to attack, or the melee windup
	# double-plays and the on_complete timing breaks. Missing → return
	# self so play_animation's else-branch fires on_complete synchronously.
	var a := _animator(["idle", "attack"])
	for windup in ["lunge", "advance", "defer"]:
		assert_eq(a._resolve_animation(windup), windup,
			"%s must NOT be remapped — its missing-anim contract fires on_complete sync" % windup)


func test_exact_anim_wins_over_fallback() -> void:
	var a := _animator(["idle", "attack", "cast"])
	assert_eq(a._resolve_animation("cast"), "cast",
		"a sheet that HAS the exact anim must use it, not the fallback")


func test_dead_defeat_cycle_does_not_loop() -> void:
	# Neither pose in the sheet — the bidirectional dead↔defeat pair must
	# not loop forever; the cycle guard returns the original (caller warns).
	var a := _animator(["idle"])  # no dead, no defeat
	assert_eq(a._resolve_animation("dead"), "dead",
		"dead↔defeat cycle must terminate without hanging (returns self → caller warns)")


func test_bard_songs_resolve_to_a_playable_anim() -> void:
	var a := _animator(["idle", "attack", "cast"])
	for song in ["battle_hymn", "lullaby", "discord", "inspiring_melody"]:
		assert_eq(a._resolve_animation(song), "cast",
			"%s → cast (present) must resolve to cast" % song)
