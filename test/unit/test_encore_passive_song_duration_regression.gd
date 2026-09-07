extends GutTest

## tick 441: encore passive's meta_effects.song_duration_bonus now
## actually extends bard song durations.
##
## Pre-fix passives.json authored:
##   encore: {meta_effects: {song_duration_bonus: 1}}
##   description: "Song buffs and debuffs last 1 extra turn"
## but no code path read the field. Bards equipped encore expecting
## +1 turn on every song and got base duration.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_support_ability_bumps_song_duration() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Pin the song-gated bonus read.
	assert_true(body.contains("ability.get(\"type\", \"\")) == \"song\""),
		"_execute_support_ability must gate the duration bonus on ability.type == 'song'")
	assert_true(body.contains("_get_passive_meta_effect_sum(\"song_duration_bonus\")"),
		"_execute_support_ability must consult the caster's song_duration_bonus")
	assert_true(body.contains("duration += bonus"),
		"the bonus must be ADDED to the duration (not multiplied or replaced)")


func test_song_gate_protects_non_songs() -> void:
	# Pin that the bonus block sits inside the song gate — so a
	# defensive_stance or dispel won't accidentally inherit the bonus.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var gate_idx: int = body.find("\"song\"")
	var add_idx: int = body.find("duration += bonus")
	assert_gt(gate_idx, -1)
	assert_gt(add_idx, -1)
	assert_lt(gate_idx, add_idx,
		"the song-gate check must precede the duration += bonus addition")


func test_data_still_authors_song_bonus() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("encore"))
	var me: Variant = data["encore"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(int(me.get("song_duration_bonus", 0)), 0,
		"encore passive must still author song_duration_bonus > 0")


func test_song_abilities_still_have_type_song() -> void:
	# Regression guard: if abilities.json ever rebrands songs to a
	# different `type:` field, the encore wire silently stops working.
	# Pin the canonical bard songs.
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	for song_id in ["battle_hymn", "lullaby", "discord"]:
		if not data.has(song_id):
			continue
		assert_eq(str(data[song_id].get("type", "")), "song",
			"%s must remain type=song so encore continues applying" % song_id)


func test_runtime_no_passive_no_bonus() -> void:
	# Regression guard: a caster without encore must NOT get the
	# bonus on a song.
	var c: Combatant = _make("Vanilla")
	c.equipped_passives = []
	var bonus: float = c._get_passive_meta_effect_sum("song_duration_bonus")
	assert_eq(bonus, 0.0,
		"vanilla combatant must report 0.0 song_duration_bonus — fix must not silently grant baseline bonus")


func test_runtime_with_passive_returns_bonus() -> void:
	# Pin the helper returns the authored value when encore is equipped.
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	if not ps.passives.has("encore"):
		pending("encore passive required")
		return
	var c: Combatant = _make("Bard")
	c.equipped_passives = ["encore"]
	var bonus: float = c._get_passive_meta_effect_sum("song_duration_bonus")
	assert_gt(bonus, 0.0,
		"encore-equipped combatant must report the authored song_duration_bonus via the helper")
