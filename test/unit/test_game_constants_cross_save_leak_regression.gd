extends GutTest

## game_constants is BOTH the tunable-constant dict AND the store for every
## cutscene_flag_*, dungeon_flags, bestiary and quest-marker key. _apply_save_data
## MERGED the saved dict onto the live one (tick 112, to keep defaults for keys an
## old save predates) — so keys the loaded save does NOT carry survived from
## whatever was loaded before it. story_flags is REPLACED on the same load, so the
## two namespaces disagreed and is_story_flag_set's OR let the stale one win.
##
## Player-visible: play into W1, then Load an earlier slot to replay a section —
## Castle Harmonia is already on the map, the W2 portal is open, the prologue and
## chapter cutscenes never fire, and the bestiary shows monsters you have not met
## in that save. Same leak class as the 2026-07-02 quests/crystals fix and the
## 2026-07-04 battles_won fix, on the widest-blast-radius dict in the save.
##
## Fix: rebuild from the canonical defaults, then merge the save's values on top.
## That keeps tick 112's intent (a save that predates a key still gets its default)
## while making the loaded save authoritative for everything it does not carry.

const GS := preload("res://src/meta/GameState.gd")


func _late_game_session() -> Node:
	var gs = GS.new()
	autofree(gs)
	# Residue from the save that was loaded FIRST this session.
	gs.game_constants["cutscene_flag_prologue_complete"] = true
	gs.game_constants["cutscene_flag_chapter1_complete"] = true
	gs.game_constants["cutscene_flag_world1_mordaine_defeated"] = true
	gs.game_constants["dungeon_flags"] = {"cave_rat_king_defeated": true}
	gs.game_constants["defeated_monsters"] = {"pyrroth": true}
	gs.game_constants["exp_multiplier"] = 3.0
	gs.story_flags["world1_mordaine_defeated"] = true
	return gs


## An early save carries its own game_constants — every flag it never set must be gone.
func _early_save() -> Dictionary:
	return {
		"player_party": [],
		"story_flags": {},
		"game_constants": {
			"exp_multiplier": 1.0,
			"gold_multiplier": 1.0,
			"damage_multiplier": 1.0,
			"healing_multiplier": 1.0,
			"encounter_rate": 1.0,
			"drop_rate_multiplier": 1.0,
		},
	}


func test_cutscene_flags_do_not_survive_loading_an_earlier_save() -> void:
	var gs = _late_game_session()
	gs.from_dict(_early_save())
	assert_false(bool(gs.game_constants.get("cutscene_flag_prologue_complete", false)),
		"the prologue flag from the previously-loaded save must not survive into an early save")
	assert_false(bool(gs.game_constants.get("cutscene_flag_chapter1_complete", false)),
		"chapter1's completion flag must not survive — it gates the Theron briefing")
	assert_false(bool(gs.game_constants.get("cutscene_flag_world1_mordaine_defeated", false)),
		"Mordaine's defeat flag must not survive — it unlocks W2 and reveals Castle Harmonia")


func test_story_flag_lookup_agrees_with_the_loaded_save() -> void:
	var gs = _late_game_session()
	gs.from_dict(_early_save())
	# is_story_flag_set ORs story_flags / game_constants["cutscene_flag_"+f] /
	# game_constants[f] / dungeon_flags — one stale namespace poisons all four.
	assert_false(gs.is_story_flag_set("world1_mordaine_defeated"),
		"story_flags was replaced by the load; game_constants must not contradict it")
	assert_false(gs.is_story_flag_set("cave_rat_king_defeated"),
		"dungeon_flags from the prior save must not leak — it gates Masterites and Castle Harmonia")


func test_bestiary_progress_does_not_leak_across_slots() -> void:
	var gs = _late_game_session()
	gs.from_dict(_early_save())
	var defeated: Variant = gs.game_constants.get("defeated_monsters", {})
	assert_false(defeated is Dictionary and bool((defeated as Dictionary).get("pyrroth", false)),
		"a dragon killed in another save must not show as defeated in this one")


## tick 112's intent must survive the fix: a save predating a constant still gets its default.
func test_save_missing_a_constant_still_gets_the_default() -> void:
	var gs = GS.new()
	autofree(gs)
	gs.from_dict({"player_party": [], "game_constants": {"exp_multiplier": 2.0}})
	assert_eq(gs.game_constants.get("exp_multiplier"), 2.0,
		"the saved value must win over the default")
	assert_eq(gs.game_constants.get("drop_rate_multiplier"), 1.0,
		"a key the save predates must fall back to the shipped default, not vanish")
	assert_eq(gs.game_constants.get("gold_multiplier"), 1.0)
	assert_eq(gs.game_constants.get("healing_multiplier"), 1.0)
	assert_eq(gs.game_constants.get("encounter_rate"), 1.0)
	assert_eq(gs.game_constants.get("damage_multiplier"), 1.0)


## The save's own flags must still load — the fix must not throw the baby out.
func test_saved_flags_still_load() -> void:
	var gs = GS.new()
	autofree(gs)
	gs.from_dict({
		"player_party": [],
		"game_constants": {
			"cutscene_flag_chapter1_complete": true,
			"dungeon_flags": {"cave_rat_king_defeated": true},
			"exp_multiplier": 1.5,
		},
	})
	assert_true(bool(gs.game_constants.get("cutscene_flag_chapter1_complete", false)))
	assert_true(gs.is_story_flag_set("cave_rat_king_defeated"))
	assert_eq(gs.game_constants.get("exp_multiplier"), 1.5)


## A malformed game_constants block must not wipe the run — keep the current dict.
func test_malformed_game_constants_keeps_current() -> void:
	var gs = _late_game_session()
	gs.from_dict({"player_party": [], "game_constants": null})
	assert_true(bool(gs.game_constants.get("cutscene_flag_chapter1_complete", false)),
		"a malformed block is not authoritative — it must not clear progress either")


## Same defect, different fields: _apply_save_data skipped Lens + equipment_pool
## entirely when the key was absent, so those collections kept the previously-loaded
## save's contents. MEASURED against the local save set 2026-07-30: 3 of 5 files
## predate the Lens keys, 2 of 5 predate equipment_pool. Player-visible: load a save
## from before those features and you are holding Lenses you never crafted (with
## their live combat effects) and gear you never picked up.
func test_lens_and_equipment_do_not_leak_from_the_previously_loaded_save() -> void:
	var gs = GS.new()
	autofree(gs)
	gs.unlocked_lens_recipes = ["warden"] as Array[String]
	gs.owned_lenses = ["warden"] as Array[String]
	gs.lens_assignments = {"hero": "warden"}
	gs.equipment_pool = {"weapons": ["iron_sword"], "armors": [], "accessories": []}
	gs.from_dict({"player_party": []})
	assert_eq(gs.unlocked_lens_recipes.size(), 0,
		"a save predating the Lens layer unlocked no recipes — it must not inherit them")
	assert_eq(gs.owned_lenses.size(), 0,
		"crafted Lenses from another save must not appear in the pool")
	assert_eq(gs.lens_assignments.size(), 0,
		"a Lens equipped in another save must not stay equipped here")
	assert_eq(gs.equipment_pool, {"weapons": [], "armors": [], "accessories": []},
		"gear from another save must not carry into a save that predates the shared pool")


func test_permakills_and_corruption_do_not_leak_from_the_previously_loaded_save() -> void:
	# The same absent-key shape as the Lens/equipment fields, closed for consistency rather than
	# because a local save triggers it — all five carry both keys today. Left on the old semantics
	# it is the drift that produced the game_constants leak: four fields authoritative, two not.
	# Permakill is the sharper of the two — Necromancer extermination removes a species from all
	# three spawn paths, so an inherited list silently empties encounter tables in a run that never
	# cast it.
	var gs = GS.new()
	autofree(gs)
	gs.permakilled_monster_types = ["slime", "bat"] as Array[String]
	gs.corruption_effects = ["stat_drain", "ability_corruption"] as Array[String]
	gs.from_dict({"player_party": []})
	assert_eq(gs.permakilled_monster_types.size(), 0,
		"a save that permakilled nothing must not inherit another run's exterminations")
	assert_eq(gs.corruption_effects.size(), 0,
		"an uncorrupted playthrough must not inherit another save's stat_drain / ability_corruption")


func test_permakills_and_corruption_still_round_trip() -> void:
	# Positive control for the two clears above: they pass against a load path that drops these
	# fields entirely, which would silently un-exterminate a real Necromancer run.
	var gs = GS.new()
	autofree(gs)
	gs.from_dict({
		"player_party": [],
		"permakilled_monster_types": ["goblin"],
		"corruption_effects": ["visual_glitch"],
	})
	assert_eq(gs.permakilled_monster_types, ["goblin"] as Array[String],
		"a saved permakill list must still load")
	assert_eq(gs.corruption_effects, ["visual_glitch"] as Array[String],
		"saved corruption effects must still load")


func test_lens_and_equipment_still_round_trip() -> void:
	var gs = GS.new()
	autofree(gs)
	gs.from_dict({
		"player_party": [],
		"unlocked_lens_recipes": ["warden"],
		"owned_lenses": ["warden"],
		"lens_assignments": {"hero": "warden"},
		"equipment_pool": {"weapons": ["iron_sword"], "armors": [], "accessories": []},
	})
	assert_eq(gs.unlocked_lens_recipes, ["warden"] as Array[String])
	assert_eq(gs.owned_lenses, ["warden"] as Array[String])
	assert_eq(gs.lens_assignments, {"hero": "warden"})
	assert_eq(gs.equipment_pool["weapons"], ["iron_sword"])


## reset_game_state and the load path must agree on what the defaults ARE.
func test_new_game_defaults_match_the_load_path_defaults() -> void:
	var gs = GS.new()
	autofree(gs)
	gs.game_constants["cutscene_flag_chapter1_complete"] = true
	gs.reset_game_state()
	var after_new_game: Dictionary = gs.game_constants.duplicate(true)
	gs.game_constants["cutscene_flag_chapter1_complete"] = true
	gs.from_dict({"player_party": [], "game_constants": {}})
	assert_eq(gs.game_constants, after_new_game,
		"loading a save with an empty constants block must land on the same defaults New Game does")
