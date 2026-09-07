extends GutTest

## struktured 2026-09-06: "I also want cooler effects for bard casts". The Bard had no visual
## identity at all — songs resolved to DARK (a shadow bolt) and Riff, whose own description is
## "a sour, clashing chord", fell through to the physical fallback and swung a sword.

const ABILITIES := "res://data/abilities.json"

func _abilities() -> Dictionary:
	var raw := FileAccess.get_file_as_string(ABILITIES)
	assert_gt(raw.length(), 100, "CONTROL: read a non-empty abilities.json")
	var parsed = JSON.parse_string(raw)
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return parsed.get("abilities", parsed)

func test_every_song_and_riff_resolves_to_the_musical_shape() -> void:
	var ab := _abilities()
	var musical: Array = []
	for id in ab:
		var a: Dictionary = ab[id]
		if str(a.get("type", "")) == "song" or str(a.get("animation", "")) == "riff":
			musical.append(str(id))
	assert_gt(musical.size(), 3, "CONTROL: found the bard's kit in data (%d)" % musical.size())
	for id in musical:
		var got: String = str(AbilityVFX.resolve(ab[id])["shape"])
		assert_eq(got, "chord", "%s must render musically, got shape '%s'" % [id, got])

func test_a_song_is_never_a_shadow_bolt_again() -> void:
	var ab := _abilities()
	var checked := 0
	for id in ab:
		var a: Dictionary = ab[id]
		if str(a.get("type", "")) != "song":
			continue
		checked += 1
		var t: int = int(AbilityVFX.resolve(a)["type"])
		assert_ne(t, EffectSystem.EffectType.DARK,
			"%s resolved to DARK — a rallying song rendering as dark magic is the bug this fixes" % id)
	assert_gt(checked, 3, "CONTROL: actually examined songs (%d)" % checked)

func test_a_rallying_song_reads_as_a_buff_and_discord_as_a_debuff() -> void:
	var ab := _abilities()
	assert_true(ab.has("battle_hymn") and ab.has("discord"), "CONTROL: both songs exist")
	assert_eq(int(AbilityVFX.resolve(ab["battle_hymn"])["type"]), EffectSystem.EffectType.BUFF,
		"an all-allies attack_up song is a buff")
	assert_eq(int(AbilityVFX.resolve(ab["discord"])["type"]), EffectSystem.EffectType.DEBUFF,
		"an all-enemies defense_down song is a debuff")

func test_musical_abilities_carry_the_performance_colour() -> void:
	var ab := _abilities()
	var c = AbilityVFX.resolve(ab["riff"])["color"]
	assert_true(c is Color, "riff must carry a colour, not null")
	assert_eq(c, AbilityVFX.MUSIC_COLOR, "musical abilities use the shared performance amber")

func test_an_authored_shape_still_beats_the_musical_default() -> void:
	## The musical arm is a DEFAULT. If someone authors vfx.shape on a song it must win, or the
	## resolver's documented precedence is a lie for exactly one job.
	var authored := {"id": "test_song", "type": "song", "vfx": {"shape": "bolt"}}
	assert_eq(str(AbilityVFX.resolve(authored)["shape"]), "bolt",
		"an authored vfx.shape must outrank the musical default")

func test_chord_is_a_registered_shape() -> void:
	assert_true("chord" in AbilityVFX.SHAPES,
		"the renderer matches on shape strings; an unregistered shape would silently take the default bloom arm")

func test_the_release_visual_renders_the_musical_shape() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(src.length(), 1000, "CONTROL: read BattleScene")
	## `"chord":` occurs TWICE — the match arm AND the `== "chord"` test in the style function.
	## A bare contains() is satisfied by the second, so deleting the renderer left this green.
	## The two-tab prefix is what distinguishes a `match` arm from the comparison.
	assert_eq(src.count("\n\t\t\"chord\":"), 1,
		"_full_render_release_visual must have exactly one chord match arm — without it the shape resolves and then silently renders as the default bloom")
	assert_true(src.contains("var staff := ColorRect.new()"),
		"CONTROL: the chord arm's body is present, not just its label")

func test_the_two_style_sources_agree_for_songs() -> void:
	## AbilityVFX feeds the cast anticipation; _full_render_element_style feeds the release.
	## They disagreed for songs (DARK vs BUFF), so one ability looked like two different spells.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(src.contains("var resolved: Dictionary = AbilityVFX.resolve(ability)"),
		"_full_render_element_style must consult the resolver rather than deriving a second answer for musical abilities")
