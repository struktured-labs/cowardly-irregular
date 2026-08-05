extends GutTest

## The Calibrant used to not exist. GameLoop's W6 closer said so in its own comment: "The
## Calibrant 'battle' is elided as narrative ... since no Calibrant arena/dungeon exists" — so
## the antagonist of the whole game was never fought, and world6_calibrant_intro (86 authored
## steps, a boss_intro step, its own music track) had ZERO references in src/ and never played.
##
## This guards the fight end to end: the boss exists, its phases actually change the fight, the
## arena is registered and reachable, and the ending waits on a real defeat flag.
##
## Phases CHANGE rather than SCALE, which is not a style preference: party damage is flat from
## L20 to L28 (one equipment catalog), so extra HP buys length and nothing else. Each face swaps
## the kit and the elemental profile, so a single autobattle script cannot ride the whole fight.

const GameLoopScript = preload("res://src/GameLoop.gd")
const CALIBRANT := "the_calibrant"


func _monster(id: String) -> Dictionary:
	var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(f, "monsters.json must be readable")
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed.get(id, {}) if parsed is Dictionary else {}


func _build_calibrant() -> Combatant:
	var m := _monster(CALIBRANT)
	var c := Combatant.new()
	c.combatant_name = str(m.get("name", "The Calibrant"))
	c.max_hp = int(m["stats"]["max_hp"])
	c.current_hp = c.max_hp
	c.max_mp = int(m["stats"]["max_mp"])
	c.current_mp = c.max_mp
	c.attack = int(m["stats"]["attack"])
	c.defense = int(m["stats"]["defense"])
	c.magic = int(m["stats"]["magic"])
	c.speed = int(m["stats"]["speed"])
	c.is_alive = true
	c.set_meta("monster_type", CALIBRANT)
	# Typed-array coercion: assigning a JSON generic Array to Array[String] aborts the function.
	var tw: Array[String] = []
	for e in m.get("weaknesses", []):
		tw.append(str(e))
	c.elemental_weaknesses = tw
	var tr: Array[String] = []
	for e in m.get("resistances", []):
		tr.append(str(e))
	c.elemental_resistances = tr
	var abil: Array = []
	for a in m.get("abilities", []):
		abil.append(str(a))
	c.job = {"id": CALIBRANT, "abilities": abil}
	return c


func test_the_calibrant_exists_and_is_a_real_boss() -> void:
	var m := _monster(CALIBRANT)
	assert_false(m.is_empty(), "the antagonist of the game must exist in monsters.json")
	assert_true(bool(m.get("boss", false)), "flagged as a boss")
	assert_gt(int(m.get("level", 0)), 20, "the final boss outranks Mordaine (L20), the first mask")
	var faces: Array = m.get("phase_faces", [])
	assert_eq(faces.size(), 5,
		"four masterite faces it already spent on the player, then no face at all")
	assert_eq(str(faces[faces.size() - 1].get("name", "")), "no face at all",
		"the last phase drops every borrowed face — the tuning comes off")
	var thresholds: Array = []
	for f in faces:
		thresholds.append(float(f.get("below_pct", 0)))
	var sorted_desc: Array = thresholds.duplicate()
	sorted_desc.sort()
	sorted_desc.reverse()
	assert_eq(thresholds, sorted_desc,
		"faces must be authored in descending HP order or the walker lands on the wrong one: %s" % str(thresholds))


func test_every_phase_ability_and_element_resolves() -> void:
	# A typo'd ability id would leave a phase with an empty kit and no error at runtime.
	var m := _monster(CALIBRANT)
	var af := FileAccess.get_file_as_string("res://data/abilities.json")
	var abilities = JSON.parse_string(af)
	assert_true(abilities is Dictionary, "abilities.json parses")
	if not (abilities is Dictionary):
		return
	var missing: Array[String] = []
	var checked: int = 0
	for face in m.get("phase_faces", []):
		for a in face.get("abilities", []):
			checked += 1
			if not (abilities as Dictionary).has(str(a)):
				missing.append("%s (%s)" % [str(a), str(face.get("name", "?"))])
	assert_gt(checked, 8, "CONTROL: real abilities were checked, not an empty walk")
	assert_eq(missing, [] as Array[String],
		"a phase ability that does not resolve leaves that face with no kit: %s" % str(missing))


## BEHAVIOURAL. Drives the real BattleManager hook rather than asserting the data shape — the
## data being present says nothing about whether crossing a threshold changes the fight.
func test_crossing_a_threshold_swaps_the_kit_and_the_elements() -> void:
	var c := _build_calibrant()
	var opening_kit: Array = (c.job["abilities"] as Array).duplicate()
	var saved_party: Array = BattleManager.enemy_party.duplicate()
	var typed: Array[Combatant] = [c]
	BattleManager.enemy_party = typed

	# Above every threshold: nothing should change.
	c.current_hp = c.max_hp
	BattleManager._maybe_advance_boss_face()
	assert_eq(c.job["abilities"], opening_kit,
		"at full HP the Calibrant wears its own face — no phase has been crossed")

	# Drop below the first threshold (80%).
	c.current_hp = int(c.max_hp * 0.75)
	BattleManager._maybe_advance_boss_face()
	assert_ne(c.job["abilities"], opening_kit,
		"crossing 80% must swap the kit — this is what makes the phase a CHANGE and not more HP")
	var warden_kit: Array = (c.job["abilities"] as Array).duplicate()
	assert_true("physical" in c.elemental_resistances,
		"the Warden's face resists physical — the elemental profile moves with the kit")

	# Drop past EVERY remaining threshold in one hit: land on the FINAL face, not the next one.
	var faces: Array = _monster(CALIBRANT).get("phase_faces", [])
	var final_face: Dictionary = faces[faces.size() - 1]
	c.current_hp = int(c.max_hp * 0.02)
	BattleManager._maybe_advance_boss_face()
	assert_ne(c.job["abilities"], warden_kit, "a big hit still advances the face")
	for a in final_face.get("abilities", []):
		assert_true(str(a) in c.job["abilities"],
			"a hit crossing several thresholds lands on the LAST face ('%s'), not the next one — missing %s"
				% [str(final_face.get("name", "?")), str(a)])
	assert_false("masterite_execution" in c.job["abilities"],
		"and it must not be left wearing an intermediate face's kit")

	BattleManager.enemy_party.assign(saved_party)


func test_a_face_never_advances_backwards_or_repeats() -> void:
	var c := _build_calibrant()
	var saved_party: Array = BattleManager.enemy_party.duplicate()
	var typed: Array[Combatant] = [c]
	BattleManager.enemy_party = typed

	# Count face CHANGES, not the resulting kit. Re-applying the same face writes the same
	# abilities, so an equality check passes even when the latch is gone and the face re-fires
	# on every single action — measured: deleting the latch failed 0 tests until this counter
	# replaced it. The observable of a missing latch is the announcement, not the state.
	var changes: Array[String] = []
	BattleManager.boss_face_changed.connect(func(_e, n): changes.append(str(n)))

	c.current_hp = int(c.max_hp * 0.75)
	BattleManager._maybe_advance_boss_face()
	assert_eq(changes.size(), 1, "crossing 80% announces exactly one face change")

	# Re-polling at the same HP must not re-announce — this runs after EVERY action.
	BattleManager._maybe_advance_boss_face()
	BattleManager._maybe_advance_boss_face()
	assert_eq(changes.size(), 1,
		"the same face must not re-announce on every action: %s" % str(changes))

	# Healing back up must not rewind the fight to a face already shed.
	c.current_hp = c.max_hp
	BattleManager._maybe_advance_boss_face()
	c.current_hp = int(c.max_hp * 0.75)
	BattleManager._maybe_advance_boss_face()
	assert_eq(changes.size(), 1,
		"faces are one-way — healing must not replay a shed face: %s" % str(changes))

	BattleManager.enemy_party.assign(saved_party)


func test_the_arena_is_registered_and_the_intro_is_finally_lit() -> void:
	assert_true(MapSystem.is_dungeon_map("vertex_apex"),
		"the arena must be a known dungeon map or the save_point_only gate misses it")
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_string_contains(src, '"vertex_apex":',
		"GameLoop must be able to BUILD the arena — a registered id with no scene is a dead map")
	var apex := FileAccess.get_file_as_string("res://src/maps/dungeons/VertexApex.gd")
	assert_string_contains(apex, 'boss_id = "the_calibrant"', "the arena fights the Calibrant")
	assert_string_contains(apex, 'boss_cutscene_id = "world6_calibrant_intro"',
		"THE POINT: 86 authored steps that had zero references in src/ now have an emitter")
	assert_true(FileAccess.file_exists("res://data/cutscenes/world6_calibrant_intro.json"),
		"CONTROL: the cutscene this wires actually exists on disk")


func test_the_ending_waits_for_the_real_defeat() -> void:
	# Regression on the elision itself: the closer must not fire from chapter3 alone.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i: int = src.find('return "world6_calibrant_defeat"')
	assert_gt(i, -1, "the W6 closer gate must exist")
	if i < 0:
		return
	var gate: String = src.substr(max(0, i - 400), 400)
	assert_string_contains(gate, "cutscene_flag_world6_calibrant_defeated",
		"the ending must require the Calibrant to actually be beaten, not just The Question asked")


func test_the_arena_is_reachable_from_the_abstract_overworld() -> void:
	# An unreachable final boss is the same defect class as an unfinishable quest.
	var ow := FileAccess.get_file_as_string("res://src/exploration/AbstractOverworld.gd")
	assert_string_contains(ow, 'target_map = "vertex_apex"',
		"the player needs a door to the last room in the game")
	assert_string_contains(ow, "world6_chapter3_complete",
		"and it must be gated on The Question, so the finale cannot be walked into early")
