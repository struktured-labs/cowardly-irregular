extends GutTest

## Five Spotlight Duels author a `victory_sfx`. Five real .ogg files exist for them. Nothing played.
##
## monsters.json gives each duel miniboss BOTH `signature_sfx` and `victory_sfx`, authored in the
## same rows. The signature half was wired when cowir-sfx surfaced it (_maybe_play_signature_sfx,
## fires on the boss's first action). The victory half was never read — zero occurrences in src/ —
## so the moment the duel is actually FOR, the win, fell back to the generic stinger every time.
##
## ⚠️ MEASUREMENT NOTE, because it nearly sent me the wrong way: grepping SoundManager.gd for these
## cue keys returns 0 for ALL TEN, including the signature ones that demonstrably play. The cues
## live in data/sfx_manifest.json with real files behind them, not in SoundManager's hardcoded dict.
## The control — a key known to work reading 0 — is the only reason I did not report the signature
## half as broken too. Two stores, and the one I reached for first was the wrong one.
##
## Resolver lives beside its sibling in BattleManager on purpose: the two halves were authored
## together and split apart, which is how one got wired and the other did not.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)

func _enemy(monster_id: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = monster_id
	c.max_hp = 100
	c.current_hp = 0
	c.set_meta("monster_type", monster_id)
	return c

func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	return (parsed as Dictionary).get("monsters", parsed)

func test_a_duel_miniboss_returns_its_own_cue() -> void:
	assert_eq(_bm.victory_cue_for([_enemy("fighter_skeleton_knight")]), "spotlight_fighter_victory",
		"the Fighter's duel must end on the Fighter's own fanfare")

func test_an_ordinary_monster_falls_back() -> void:
	assert_eq(_bm.victory_cue_for([_enemy("slime")]), "victory_stinger",
		"every non-duel fight keeps the generic stinger — this adds a case, it does not replace one")

func test_an_empty_field_falls_back() -> void:
	assert_eq(_bm.victory_cue_for([]), "victory_stinger", "no enemies, no bespoke cue, no crash")

func test_a_malformed_entry_does_not_take_the_cue_slot() -> void:
	## A combatant with no monster_type meta is skipped rather than resolving to "" and silencing
	## the win — an empty cue key is silence, which is indistinguishable from "nobody triggers it".
	var nameless := Combatant.new()
	autofree(nameless)
	nameless.combatant_name = "?"
	assert_eq(_bm.victory_cue_for([nameless, _enemy("bard_hostile_courtier")]), "spotlight_bard_victory",
		"a metaless combatant must not shadow a real duel opponent behind it")

func test_all_five_duels_author_a_cue_and_a_real_file() -> void:
	## The premise, measured. A cue key with no file behind it is silence that reads as working.
	var manifest := FileAccess.get_file_as_string("res://data/sfx_manifest.json")
	assert_gt(manifest.length(), 1000, "CONTROL: read the sfx manifest")
	var checked: int = 0
	var mons: Dictionary = _monsters()
	for mid in mons:
		var v: Dictionary = mons[mid]
		if not bool(v.get("spotlight_duel", false)):
			continue
		checked += 1
		var cue: String = str(v.get("victory_sfx", ""))
		assert_ne(cue, "", "%s is a spotlight duel and must author a victory cue" % mid)
		assert_string_contains(manifest, "\"%s\"" % cue,
			"%s's cue '%s' must be registered in the sfx manifest" % [mid, cue])
		assert_true(FileAccess.file_exists("res://assets/audio/sfx/%s.ogg" % cue),
			"%s's cue '%s' must have a real file — an unresolvable key is silence" % [mid, cue])
	assert_eq(checked, 5, "CONTROL: five spotlight duels — if this moves, revisit the roster")

func test_the_scene_asks_for_the_cue_rather_than_hardcoding_one() -> void:
	## The resolver is only half of it; the victory site has to consult it.
	var scene := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_string_contains(scene, "BattleManager.victory_cue_for(",
		"the victory stinger must be resolved, not hardcoded")
	assert_false(scene.contains("play_battle(\"victory_stinger\")"),
		"and the hardcoded call must be gone, or the duel cue never gets a chance")
