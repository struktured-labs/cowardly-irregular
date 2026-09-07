extends GutTest

## struktured 2026-08-15: "I don't hear any [sound] when the monster fades out
## on final blow" — the burned-away scorch (enemy_death.ogg, the agreed FF4-6
## guide) was wired but NEVER audible: it fired inside take_damage's died
## signal, then the killing blow's own hit sound stomped it milliseconds later
## on the shared _battle_player (one voice). It now starts WITH the fade —
## inside the death tween, after the white-flash — so it plays after the hit
## sound instead of under it.

func test_death_cry_fires_inside_the_fade_tween_not_before_the_hit_sound() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var fn_idx := src.find("func _on_enemy_died")
	assert_gt(fn_idx, -1, "_on_enemy_died present")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body := src.substr(fn_idx, (next_fn - fn_idx) if next_fn > -1 else -1)

	var tween_start := body.find("var tween = create_tween()")
	assert_gt(tween_start, -1, "death tween present")
	var cry := body.find('play_death("enemy_death")', tween_start)
	assert_gt(cry, tween_start, "the scorch fires INSIDE the death tween (after the flash) — immediately-on-died gets stomped by the killing blow's hit sound on the shared battle player")
	var dissolve := body.find("dissolve_amount", tween_start)
	assert_gt(dissolve, cry, "the scorch starts before/with the dissolve step, synced to the fade the player watches")

	# No early fire: between function start and the tween there is no play (except the spriteless fallback, which is inside a not-valid guard)
	var head := body.substr(0, tween_start)
	var early := head.find('play_death("enemy_death")')
	if early > -1:
		var guard := head.rfind("if not is_instance_valid(sprite):", early)
		assert_gt(guard, -1, "any pre-tween death cry must be the spriteless fallback only")


func test_death_cry_has_its_own_voice() -> void:
	# 2026-08-18 second report: even fired at fade-start, the scorch died on the
	# SHARED _battle_player — at 2x+ speed the next action's hit sound arrives
	# inside the 1s tail and cuts it. Death cries get a dedicated player.
	var sm := FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_true("var _death_player: AudioStreamPlayer" in sm, "dedicated death voice exists")
	var fn := sm.find("func play_death")
	assert_gt(fn, -1, "play_death helper exists")
	var body := sm.substr(fn, sm.find("\nfunc ", fn + 1) - fn)
	assert_true("_death_player" in body, "play_death routes to the dedicated voice")
	assert_false("_battle_player" in body, "play_death must NOT touch the shared battle voice")

