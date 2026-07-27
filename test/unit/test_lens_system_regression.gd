extends GutTest

## Lens system — layer 3 of the character model (Primary locked / Secondary job / Lens).
## Design: docs/design/lens-system-and-evolutions-proposal.md + lens-system-addendum-2026-07-27.md
##
## struktured ruling 2026-07-27: **POOLED.** "killing blow feels wrong, the lens should be
## equippable by anyone." So these pin the ABSENCE of binding as hard as the presence of
## everything else — a future "bind to the killer" refactor has to delete a test, not slip past one.

const LENS_PATH := "res://data/lenses.json"
const AXES := ["warden", "arbiter", "tempo", "curator"]

var _saved_recipes: Array[String] = []
var _saved_owned: Array[String] = []
var _saved_assign: Dictionary = {}


func before_each() -> void:
	_saved_recipes = GameState.unlocked_lens_recipes.duplicate()
	_saved_owned = GameState.owned_lenses.duplicate()
	_saved_assign = GameState.lens_assignments.duplicate()
	GameState.unlocked_lens_recipes.clear()
	GameState.owned_lenses.clear()
	GameState.lens_assignments.clear()


func after_each() -> void:
	GameState.unlocked_lens_recipes = _saved_recipes
	GameState.owned_lenses = _saved_owned
	GameState.lens_assignments = _saved_assign


# ── Data ────────────────────────────────────────────────────────────

func test_all_four_axes_load() -> void:
	# Compared as a set: all_axes() sorts for a stable menu order, which is not the subject here.
	var loaded := LensSystem.all_axes()
	var expected := AXES.duplicate()
	loaded.sort()
	expected.sort()
	assert_eq(loaded, expected,
		"one Lens per masterite axis — the 20 masterites are exactly 5 per axis")
	for axis in AXES:
		var lens := LensSystem.get_lens(axis)
		assert_false(lens.is_empty(), "%s Lens must load" % axis)
		assert_ne(str(lens.get("passive_name", "")), "", "%s needs a passive name" % axis)
		assert_ne(str(lens.get("voice_tint", "")), "", "%s needs a voice tint for cowir-story" % axis)


func test_stat_mod_keys_match_passive_system_vocabulary() -> void:
	# Lens mods and passive mods get composed together in battle. If the two vocabularies
	# drift, a Lens tilt silently does nothing — no error, no warning, just a dead stat.
	var known := LensSystem.NEUTRAL_MODS.keys()
	for axis in AXES:
		var stat_mods: Dictionary = LensSystem.get_lens(axis).get("stat_mods", {})
		for key in stat_mods:
			assert_true(key in known,
				"%s declares stat_mod '%s', which PassiveSystem.get_passive_mods does not know — "
					% [axis, key] + "it would be silently ignored")


func test_tempo_and_curator_carry_identity_in_the_passive_not_a_stat_tilt() -> void:
	# cowir-battle measured the 20 live masterites (msg 3178): Tempo is 20/25 support
	# (haste/slow/time_tax) so +SPD is the stat it MANIPULATES, and every Curator "magic"
	# ability attacks MP or buffs rather than HP so +MAG misreads it. Both doc tilts were
	# derived from ability TYPE. Pinned so a later "the doc says +10% SPD" edit is deliberate.
	for axis in ["tempo", "curator"]:
		var lens := LensSystem.get_lens(axis)
		assert_true((lens.get("stat_mods", {}) as Dictionary).is_empty(),
			"%s must carry its identity in meta_effects, not a stat tilt" % axis)
		assert_false((lens.get("meta_effects", {}) as Dictionary).is_empty(),
			"%s has no stat tilt, so its meta_effects ARE the Lens" % axis)


# ── Acquisition ─────────────────────────────────────────────────────

func test_recipe_unlock_is_idempotent() -> void:
	# Five masterites share each axis. The second must not re-announce or duplicate.
	assert_true(LensSystem.unlock_recipe("warden"), "first defeat unlocks")
	assert_false(LensSystem.unlock_recipe("warden"), "second defeat of the same axis is a no-op")
	assert_eq(GameState.unlocked_lens_recipes.count("warden"), 1, "no duplicate recipe entries")


func test_unknown_axis_cannot_unlock() -> void:
	assert_false(LensSystem.unlock_recipe("nonsense"), "unknown axes must be refused, not stored")
	assert_eq(GameState.unlocked_lens_recipes.size(), 0)


func test_crafting_is_gated_on_the_recipe() -> void:
	var reason := LensSystem.craft_blocked_reason("warden")
	assert_string_contains(reason, "Recipe not yet unlocked",
		"crafting before defeating the axis must be refused WITH a reason the UI can show")
	assert_false(LensSystem.can_craft("warden"))


func test_crafting_is_gated_on_materials_and_names_the_shortfall() -> void:
	LensSystem.unlock_recipe("warden")
	var reason := LensSystem.craft_blocked_reason("warden")
	# With no party in this harness there are no materials, so it must block on them.
	assert_string_contains(reason, "Need",
		"an unaffordable craft must say WHICH material is short, not just fail: got '%s'" % reason)


func test_every_recipe_is_satisfiable_from_a_real_drop() -> void:
	# A recipe naming an item no masterite drops would be permanently uncraftable.
	var mons = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var monsters: Dictionary = mons.get("monsters", mons)
	var droppable := {}
	for mid in monsters:
		var m = monsters[mid]
		if m is Dictionary and m.get("masterite", false):
			for d in m.get("drop_table", []):
				if d is Dictionary:
					droppable[str(d.get("item", ""))] = true
	for axis in AXES:
		var recipe := LensSystem.get_recipe(axis)
		assert_false(recipe.is_empty(), "%s needs a recipe or it can never be crafted" % axis)
		for item_id in recipe:
			assert_true(droppable.has(item_id),
				"%s's recipe needs '%s', which no masterite drops — permanently uncraftable"
					% [axis, item_id])


# ── Pooled equipping (struktured's ruling) ──────────────────────────

func test_any_character_can_equip_any_owned_lens() -> void:
	# The ruling in one test: no binding, no eligibility check, no killer.
	GameState.owned_lenses.append("warden")
	for char_id in ["fighter", "cleric", "mage", "rogue", "bard"]:
		assert_true(LensSystem.equip_lens(char_id, "warden"),
			"'%s' must be able to equip a pooled Lens — binding was explicitly ruled out" % char_id)


func test_equipping_elsewhere_MOVES_the_lens_rather_than_duplicating_it() -> void:
	GameState.owned_lenses.append("warden")
	LensSystem.equip_lens("fighter", "warden")
	LensSystem.equip_lens("cleric", "warden")
	assert_eq(LensSystem.get_equipped("fighter"), "",
		"the previous holder must lose it — one Lens exists per axis")
	assert_eq(LensSystem.get_equipped("cleric"), "warden")
	assert_eq(LensSystem.holder_of("warden"), "cleric")


func test_an_unowned_lens_cannot_be_equipped() -> void:
	assert_false(LensSystem.equip_lens("fighter", "warden"),
		"equipping a Lens that was never crafted must fail — crafting is the gate")


func test_unequip_clears_the_slot() -> void:
	GameState.owned_lenses.append("tempo")
	LensSystem.equip_lens("bard", "tempo")
	assert_true(LensSystem.unequip_lens("bard"))
	assert_eq(LensSystem.get_equipped("bard"), "")
	assert_eq(LensSystem.holder_of("tempo"), "", "and it returns to the pool")


# ── Effects ─────────────────────────────────────────────────────────

func test_mods_are_neutral_without_a_lens() -> void:
	var mods := LensSystem.get_lens_mods("fighter")
	for key in mods:
		var expected: float = 0.0 if key in ["crit_chance", "evasion"] else 1.0
		assert_eq(float(mods[key]), expected, "%s must be neutral with no Lens equipped" % key)


func test_warden_tilt_applies_when_equipped() -> void:
	GameState.owned_lenses.append("warden")
	LensSystem.equip_lens("fighter", "warden")
	var mods := LensSystem.get_lens_mods("fighter")
	assert_gt(float(mods["defense_multiplier"]), 1.0, "the Warden Lens must actually raise defense")


func test_meta_effects_and_voice_tint_are_readable() -> void:
	GameState.owned_lenses.append("curator")
	LensSystem.equip_lens("mage", "curator")
	assert_false(LensSystem.get_lens_meta_effects("mage").is_empty(),
		"battle code needs to read non-stat Lens effects")
	assert_eq(LensSystem.get_voice_tint("mage"), "transactional",
		"cowir-story authors dialogue against the tint tag")


# ── Persistence ─────────────────────────────────────────────────────

func test_lens_state_survives_a_save_roundtrip_with_correct_types() -> void:
	# JSON.parse returns an untyped Array; assigning that to Array[String] is a SILENT
	# script error that leaves the field at its default. That trap ate party data before.
	GameState.unlocked_lens_recipes.append("warden")
	GameState.owned_lenses.append("warden")
	GameState.lens_assignments["fighter"] = "warden"

	var round_tripped: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.unlocked_lens_recipes.clear()
	GameState.owned_lenses.clear()
	GameState.lens_assignments.clear()
	GameState.from_dict(round_tripped)

	assert_eq(GameState.unlocked_lens_recipes, ["warden"] as Array[String],
		"recipes must survive JSON with their element type intact")
	assert_eq(GameState.owned_lenses, ["warden"] as Array[String],
		"owned Lenses must survive JSON with their element type intact")
	assert_eq(str(GameState.lens_assignments.get("fighter", "")), "warden",
		"assignments must survive the roundtrip")


func test_new_game_clears_lens_state() -> void:
	# Same leak class as the quests/crystals bleed fixed 2026-07-02: starting a new run
	# already holding last run's Lenses.
	GameState.unlocked_lens_recipes.append("warden")
	GameState.owned_lenses.append("warden")
	GameState.lens_assignments["fighter"] = "warden"
	GameState.reset_game_state()
	assert_eq(GameState.unlocked_lens_recipes.size(), 0, "recipes must not survive New Game")
	assert_eq(GameState.owned_lenses.size(), 0, "Lenses must not survive New Game")
	assert_eq(GameState.lens_assignments.size(), 0, "assignments must not survive New Game")
