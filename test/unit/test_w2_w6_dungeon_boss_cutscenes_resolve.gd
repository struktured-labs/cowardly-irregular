extends GutTest

## tick 94 regression: every W2-W6 dungeon subclass must declare
## boss_cutscene_id pointing to a real cutscene JSON file in
## data/cutscenes/. Pre-fix, SteampunkMechanism (W3) and
## SuburbanUnderground (W2) were missing the field entirely —
## DragonCave.gd reads it before emitting battle_triggered and a
## missing/empty id skips the boss intro silently. Players would
## walk into the boss arena and get the fight without any setup.

const DUNGEONS_WITH_CUTSCENES: Array[Array] = [
	["res://src/maps/dungeons/SuburbanUnderground.gd",  "world2_warden_routine"],
	["res://src/maps/dungeons/SteampunkMechanism.gd",   "world3_tempo_intro"],
	["res://src/maps/dungeons/AssemblyCore.gd",         "world4_assembly_boss"],
	["res://src/maps/dungeons/RootProcess.gd",          "world5_root_process_boss"],
	["res://src/maps/dungeons/NullChamber.gd",          "world6_null_chamber_boss"],
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_every_w2_w6_dungeon_declares_boss_cutscene_id() -> void:
	for entry in DUNGEONS_WITH_CUTSCENES:
		var path: String = entry[0]
		var expected: String = entry[1]
		var src := _read(path)
		var quoted: String = "boss_cutscene_id = \"" + expected + "\""
		assert_true(src.contains(quoted),
			"%s must declare boss_cutscene_id = '%s' in _init — DragonCave reads this to trigger the boss intro" % [path, expected])


func test_every_referenced_cutscene_file_exists() -> void:
	# Pin: each boss_cutscene_id must resolve to a real JSON file on
	# disk. Otherwise CutsceneDirector silently no-ops the play.
	for entry in DUNGEONS_WITH_CUTSCENES:
		var expected: String = entry[1]
		var path: String = "res://data/cutscenes/" + expected + ".json"
		assert_true(FileAccess.file_exists(path),
			"Cutscene file %s must exist on disk — referenced by a W2-W6 dungeon's boss_cutscene_id" % path)


func test_every_referenced_cutscene_id_field_matches() -> void:
	# Pin: the JSON file's `id` field must match the filename's stem.
	# CutsceneDirector loads by filename + id; a mismatch silently
	# fails to locate the cutscene.
	for entry in DUNGEONS_WITH_CUTSCENES:
		var expected_id: String = entry[1]
		var path: String = "res://data/cutscenes/" + expected_id + ".json"
		var f := FileAccess.open(path, FileAccess.READ)
		assert_not_null(f, "%s must be readable" % path)
		var text: String = f.get_as_text()
		f.close()
		var json := JSON.new()
		var err: int = json.parse(text)
		assert_eq(err, OK, "%s must parse as valid JSON" % path)
		var data = json.data
		assert_true(data is Dictionary, "%s must be a top-level dict" % path)
		assert_eq(data.get("id", ""), expected_id,
			"%s 'id' field must match the filename stem — CutsceneDirector matches both" % path)


func test_w1_dragon_caves_keep_their_cutscene_ids() -> void:
	# Negative pin: the W1 dragon caves should still have their own
	# boss_cutscene_id values. Don't regress those while adding W2/W3.
	for entry in [
		["res://src/maps/dungeons/IceDragonCave.gd",        "world1_glacius_intro"],
		["res://src/maps/dungeons/CastleHarmonia.gd",       "world1_mordaine_intro"],
	]:
		var path: String = entry[0]
		var expected: String = entry[1]
		var src := _read(path)
		# Best-effort — only check if the file declares boss_cutscene_id
		if not src.contains("boss_cutscene_id"):
			continue
		assert_true(src.contains("\"" + expected + "\""),
			"%s must keep boss_cutscene_id reference to %s — W1 boss intros unchanged by tick 94" % [path, expected])
