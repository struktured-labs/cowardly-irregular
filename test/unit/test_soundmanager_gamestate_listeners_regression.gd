extends GutTest

## SoundManager's two GameState listeners must actually be CONNECTED (2026-09-09).
##
## Both hookups are written as a null-guarded early return:
##
##     var gs: Node = get_node_or_null("/root/GameState")
##     if gs == null or not gs.has_signal("corruption_changed"):
##         return
##
## and _connect_corruption_source carries its own warning — "GameState may not
## be ready when SoundManager._ready runs, and a missed connection is silent."
## The comment names the hazard; nothing enforced it. If either connection is
## missed the game keeps working and keeps making sound, so there is no symptom
## to notice: save corruption simply never becomes audible, and night ambience
## never switches. That is the class three lanes shipped the same day —
## cowir-overworld's BestiarySystem lookups returned null forever and every
## caller took a plausible fallback, so a level-18 roamer fled from a level-5
## party for four releases.
##
## Checked at the time of writing: both ARE connected. This guard exists so
## that stays true, because nothing else in the suite would notice it stopping.
##
## It asserts the VALUE (is the connection live) rather than the null check
## (did the lookup return something), which is the whole distinction.


func test_both_gamestate_listeners_are_live() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	assert_not_null(gs,
		"SCOPE control: GameState autoload is missing, so every assertion below would pass vacuously")
	assert_not_null(SoundManager,
		"SCOPE control: SoundManager autoload is missing")

	## Control that the signals exist at all — without this, a RENAMED signal
	## reads identically to a broken connection and the fix would be wrong.
	assert_true(gs.has_signal("corruption_changed"),
		"GameState no longer declares corruption_changed — the signal was renamed or removed, so fix the listener's name rather than the connection")
	assert_true(gs.has_signal("time_of_day_changed"),
		"GameState no longer declares time_of_day_changed — renamed or removed")

	assert_true(gs.corruption_changed.is_connected(SoundManager.set_save_corruption),
		"SoundManager is NOT listening to GameState.corruption_changed — save corruption is inaudible, and the hookup fails SILENTLY by construction (null-guarded early return)")
	assert_true(gs.time_of_day_changed.is_connected(SoundManager._on_time_of_day_changed_for_ambience),
		"SoundManager is NOT listening to GameState.time_of_day_changed — night ambience never switches, same silent early return")
