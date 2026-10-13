extends GutTest

## THE BARD'S BASIC ATTACK PLAYED A SPELLCASTING POSE.
##
## `riff` is `type: physical`, `damage_multiplier: 1.0`, `mp_cost: 0`, and carries
## `replaces_attack: true` in jobs.json — so the Bard has NO separate Attack row and Riff IS the
## swing. Its own description says "struck like a weapon… it lands as hard as a swing".
##
## 🔑 THE CHAIN, measured end to end: `_ability_anim_name` prefers a bespoke sheet animation named
## after the ability id, and the Bard's sheet has no `riff` — it has `battle_hymn`, `discord`,
## `inspiring_melody` and `lullaby`, but not the attack row's. So it falls through to the ability's
## own `animation` field, which is also "riff", and `play_named_animation("riff")` reaches the match
## arm — where `riff` sat GROUPED WITH THE FOUR SONGS and routed to `play_cast`.
##
## ⛔ Three lines above it, `"strike"` — the Rogue's free move, the same shape — routes to
## `play_attack` and carries the comment "physical attack fallback (not cast)". The right answer was
## already in the file, one arm away. Riff was grouped by WHO uses it rather than by WHAT it does.
##
## 📌 And the project already asserted the data half: test_bard_job:206 pins
## `riff.type == "physical"` with the message "Riff is a strike". Nothing pinned the animation, and
## test_bard_songs_resolve_to_a_playable_anim covers the four songs only — so the contradiction
## between a pinned datum and the routing had no arm on it.

const SONGS := ["battle_hymn", "lullaby", "discord", "inspiring_melody"]


func _animator(anims: Array) -> BattleAnimator:
	var s := AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	for a in anims:
		sf.add_animation(a)
		sf.add_frame(a, ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8)))
	s.sprite_frames = sf
	add_child_autofree(s)
	var an := BattleAnimator.new()
	add_child_autofree(an)
	an.sprite = s
	return an


func _abilities() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	if not (raw is Dictionary):
		return {}
	var a: Variant = (raw as Dictionary).get("abilities", raw)
	return a if a is Dictionary else {}


## THE DEFECT. A sheet carrying both poses, so the routing is what decides — not availability.
func test_riff_swings_rather_than_casts() -> void:
	var a := _animator(["idle", "attack", "cast"])
	a.play_named_animation("riff")
	assert_eq(a.current_state, BattleAnimator.AnimState.ATTACK,
		"Riff IS the Bard's attack row (replaces_attack, type physical, 1.0x) — it must swing, not cast")


## CONTROL, passes on BOTH trees: the Rogue's equivalent was always right, and it proves the
## observable can read ATTACK at all. Without it the arm above could pass for a broken instrument.
func test_control_the_rogue_strike_already_swings() -> void:
	var a := _animator(["idle", "attack", "cast"])
	a.play_named_animation("strike")
	assert_eq(a.current_state, BattleAnimator.AnimState.ATTACK,
		"strike has routed to play_attack since it was added — if this fails the observable is wrong, not Riff")


## CONTROL, and the one that stops the fix from broadening: the four SONGS must still cast. Riff left
## their arm; they did not.
func test_control_the_bard_songs_still_cast() -> void:
	for song in SONGS:
		var a := _animator(["idle", "attack", "cast"])
		a.play_named_animation(song)
		assert_eq(a.current_state, BattleAnimator.AnimState.CAST,
			"%s is type song and must still cast — the fix moves ONE name out of that arm" % song)


## CONTROL: the two MP-restore free moves are correctly cast, so "free move" is not the rule either.
func test_control_pray_and_channel_still_cast() -> void:
	for id in ["pray", "channel"]:
		var a := _animator(["idle", "attack", "cast"])
		a.play_named_animation(id)
		assert_eq(a.current_state, BattleAnimator.AnimState.CAST,
			"%s restores MP to an ally or self — casting is right for it" % id)


## THE PREMISE, derived rather than asserted in prose: Riff really is a physical full strike, and the
## Bard's sheet really lacks a bespoke `riff`, so the fallback really is what a player sees.
func test_the_premise_riff_is_a_strike_with_no_bespoke_art() -> void:
	var ab: Dictionary = _abilities()
	assert_true(ab.has("riff"), "CONTROL: riff must exist, else every arm here is about nothing")
	if not ab.has("riff"):
		return
	var r: Dictionary = ab["riff"]
	assert_eq(str(r.get("type", "")), "physical", "riff is a physical strike, not a song")
	assert_gte(float(r.get("damage_multiplier", 0.0)), 1.0, "and a full-strength one")
	var jraw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var jobs: Dictionary = (jraw as Dictionary).get("jobs", jraw) if jraw is Dictionary else {}
	var fm: Dictionary = (jobs.get("bard", {}) as Dictionary).get("free_move", {})
	assert_true(bool(fm.get("replaces_attack", false)),
		"riff REPLACES the Bard's Attack row — that is what makes a cast pose wrong rather than a style choice")
	var mraw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var sheet: Dictionary = ((mraw as Dictionary).get("sheets", {}) as Dictionary).get("bard", {})
	var anims: Variant = sheet.get("animations", [])
	var names: Array = anims.keys() if anims is Dictionary else (anims as Array)
	assert_false(names.has("riff"),
		"the Bard sheet has no bespoke `riff`, which is WHY the fallback decides — if art lands this arm reds and the routing stops mattering")
	assert_true(names.has("attack"), "and it does have `attack`, so swinging is actually playable")
