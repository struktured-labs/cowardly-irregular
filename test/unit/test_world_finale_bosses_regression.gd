extends GutTest

## World finale bosses W2-W4 (msg 3183 / 3260 / 3264).
##
## cowir-main's audit found five worlds ending on a MASTERITE — the
## four-axis profiling encounters, which are a different design object
## from a world finale. Only W1 had a real finale (Mordaine) with a
## story-closure flag and a world unlock; W2-W6 carried `*_cleared`
## dungeon flags and no progression.
##
## @cowir-story's canon supplies the identities: the Calibrant wears a
## different face per world, and the through-line is DE-COSTUMING —
## robes → glasses → goggles → gray suit → nothing. So these three get
## progressively plainer, and W5/W6 are deliberately NOT fights at all
## (a desk conversation and an essence Q&A duel), which is why only
## three entries exist here rather than five.
##
## NUMBERS are authored directly in the ×10 scale (e3653adf), not
## written small and multiplied. Mordaine at 16,500 is the W1 floor a
## later-world finale must clear — an earlier draft of these blocks
## interpolated the MASTERITE curve and landed ~20× too low, because
## masterites wander and are deliberately soft while a finale is a wall.

const MONSTERS: String = "res://data/monsters.json"
const FINALES: Array = ["the_coordinator", "the_regulator", "the_director"]


func _monsters() -> Dictionary:
	var f: FileAccess = FileAccess.open(MONSTERS, FileAccess.READ)
	assert_not_null(f, "monsters.json must be readable")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "monsters.json must parse")
	return parsed


## ── (1) The three exist and are bosses ───────────────────────────────

func test_three_finale_bosses_authored() -> void:
	var m: Dictionary = _monsters()
	for id in FINALES:
		assert_true(m.has(id), "world finale '%s' must exist in monsters.json" % id)
		assert_true(bool((m[id] as Dictionary).get("boss", false)),
			"'%s' must be flagged boss — it is a world finale" % id)


func test_finales_are_not_masterites() -> void:
	# The whole point of the audit: a masterite is a profiling encounter,
	# not a finale. If one of these ever acquires masterite:true, the two
	# design objects have been collapsed again.
	var m: Dictionary = _monsters()
	for id in FINALES:
		assert_false(bool((m[id] as Dictionary).get("masterite", false)),
			"'%s' must NOT be a masterite — that collapse is the bug this fixes" % id)


## ── (2) Authored in the ×10 scale, above the W1 floor ────────────────

func test_finales_clear_the_mordaine_floor() -> void:
	# Mordaine is W1's finale. A W2/W3/W4 finale that ends easier than
	# the world-1 boss is the second half of cowir-main's audit finding.
	var m: Dictionary = _monsters()
	var floor_hp: int = int(((m["chancellor_mordaine"] as Dictionary)["stats"] as Dictionary)["max_hp"])
	assert_gt(floor_hp, 10000, "sanity: Mordaine must be in the ×10 scale, got %d" % floor_hp)
	for id in FINALES:
		var hp: int = int(((m[id] as Dictionary)["stats"] as Dictionary)["max_hp"])
		assert_gt(hp, floor_hp,
			"'%s' (%d hp) must exceed the W1 finale floor (Mordaine %d) — a later world cannot end easier than world 1" % [id, hp, floor_hp])


func test_finale_difficulty_is_monotonic() -> void:
	# W2 → W3 → W4 must climb. Authored in order, so a later edit that
	# breaks the ordering is a real regression rather than a taste call.
	var m: Dictionary = _monsters()
	var last: int = 0
	for id in FINALES:
		var hp: int = int(((m[id] as Dictionary)["stats"] as Dictionary)["max_hp"])
		assert_gt(hp, last, "finale HP must increase across worlds; '%s' broke the order" % id)
		last = hp


func test_finales_declare_magic_defense() -> void:
	# msg 3264 split magic_defense out as a real stat, with every
	# migrated monster defaulting to defense/2. These are authored AFTER
	# the split, so they should carry a DELIBERATE value — the whole
	# point of the new axis is enemies that are physically tough and
	# magically frail, or the reverse.
	var m: Dictionary = _monsters()
	for id in FINALES:
		var s: Dictionary = (m[id] as Dictionary)["stats"]
		assert_true(s.has("magic_defense"),
			"'%s' must author magic_defense — it was created after the stat split" % id)
	# And at least one must diverge from the defense/2 migration default,
	# or the new axis is being wasted on the fights most able to use it.
	var diverged: int = 0
	for id in FINALES:
		var s: Dictionary = (m[id] as Dictionary)["stats"]
		if int(s["magic_defense"]) != int(int(s["defense"]) / 2):
			diverged += 1
	assert_gt(diverged, 0,
		"at least one finale must set magic_defense away from the defense/2 default — otherwise the new stat axis is unused where it matters most")


## ── (3) Dungeon wiring: flag + unlock, mirroring CastleHarmonia ──────

func test_dungeons_point_at_the_finale_bosses() -> void:
	var wiring: Dictionary = {
		"SuburbanUnderground": "the_coordinator",
		"SteampunkMechanism": "the_regulator",
		"AssemblyCore": "the_director",
	}
	for scene in wiring:
		var src: String = FileAccess.get_file_as_string("res://src/maps/dungeons/%s.gd" % scene)
		assert_string_contains(src, 'boss_id = "%s"' % wiring[scene],
			"%s must point at its world finale, not a masterite" % scene)


func test_dungeons_unlock_the_next_world() -> void:
	# The half of the audit that is pure progression: only CastleHarmonia
	# declared unlock_world, so beating W2-W4 advanced nothing.
	var expected: Dictionary = {
		"SuburbanUnderground": 3, "SteampunkMechanism": 4, "AssemblyCore": 5,
	}
	for scene in expected:
		var src: String = FileAccess.get_file_as_string("res://src/maps/dungeons/%s.gd" % scene)
		assert_string_contains(src, "unlock_world = %d" % expected[scene],
			"%s must unlock world %d on defeat — without this the world is a dead end" % [scene, expected[scene]])


func test_dungeons_carry_story_closure_flags() -> void:
	# `*_cleared` is a dungeon flag; a finale needs a STORY flag so
	# cutscenes and quests can gate on the world actually ending.
	#
	# NOTE this is boss_flag_key, NOT defeat_cutscene_flags. An earlier
	# draft added three new cutscene flags too — and the flag-audit
	# ratchet correctly failed them as "set by a dungeon, read by no
	# gate". That is the shipped-unwired shape: a cutscene flag with no
	# cutscene. The closure record belongs in boss_flag_key until
	# cowir-story authors the W2-W4 closer scenes, at which point the
	# cutscene flags land WITH their gates.
	var expected: Dictionary = {
		"SuburbanUnderground": "world2_coordinator_defeated",
		"SteampunkMechanism": "world3_regulator_defeated",
		"AssemblyCore": "world4_director_defeated",
	}
	for scene in expected:
		var src: String = FileAccess.get_file_as_string("res://src/maps/dungeons/%s.gd" % scene)
		assert_string_contains(src, 'boss_flag_key = "%s"' % expected[scene],
			"%s must set a story-closure flag, mirroring world1_mordaine_defeated" % scene)


## ── (4) Data integrity — every reference must resolve ────────────────

func test_finale_abilities_all_exist() -> void:
	# The silent-failure class: a typo'd ability id means the boss skips
	# its turn and reads as an AI that chose not to act.
	var m: Dictionary = _monsters()
	var af: FileAccess = FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var abilities: Dictionary = JSON.parse_string(af.get_as_text())
	for id in FINALES:
		for a in (m[id] as Dictionary).get("abilities", []):
			assert_true(abilities.has(str(a)),
				"'%s' references ability '%s' which does not exist" % [id, a])


func test_finale_drops_all_exist() -> void:
	var m: Dictionary = _monsters()
	var itf: FileAccess = FileAccess.open("res://data/items.json", FileAccess.READ)
	var items: Dictionary = JSON.parse_string(itf.get_as_text())
	for id in FINALES:
		for entry in (m[id] as Dictionary).get("drop_table", []):
			var item_id: String = str((entry as Dictionary).get("item", ""))
			assert_true(items.has(item_id),
				"'%s' drops '%s' which does not exist in items.json" % [id, item_id])


func test_finale_one_shot_thresholds_are_reachable() -> void:
	# hp_threshold below max_hp is unreachable on a fresh boss — the
	# whole block would be dead data.
	var m: Dictionary = _monsters()
	for id in FINALES:
		var d: Dictionary = m[id]
		var os: Dictionary = d.get("one_shot", {})
		if os.is_empty():
			continue
		assert_gte(int(os.get("hp_threshold", 0)), int((d["stats"] as Dictionary)["max_hp"]),
			"'%s' one_shot threshold must be >= max_hp or it can never fire" % id)
