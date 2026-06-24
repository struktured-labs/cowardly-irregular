extends GutTest

## tick 95 regression: W2-W5 dungeons must declare defeat_cutscene
## pointing to a real defeat cutscene JSON. Pre-fix, the W2-W5
## dungeons (SuburbanUnderground, SteampunkMechanism, AssemblyCore,
## RootProcess) declared boss_cutscene_id (intro) but NOT
## defeat_cutscene — so on victory, DragonCave._on_boss_defeated
## skipped the defeat cutscene play entirely (line 543 guards on
## `defeat_cutscene != ""`).
##
## The defeat cutscene files all existed in data/cutscenes/, just
## never reached: world2_warden_defeat / world3_tempo_defeat /
## world4_warden_defeat / world5_arbiter_defeat. Players got the
## boss intro but no post-victory dialogue.
##
## W6 NullChamber skipped: world6_curator_defeat.json doesn't exist
## on disk yet (the only authored W6 boss-defeat cutscene is the
## final Calibrant battle, not the NullChamber dungeon Curator).

const DUNGEON_DEFEATS: Array[Array] = [
	["res://src/maps/dungeons/SuburbanUnderground.gd",  "world2_warden_defeat"],
	["res://src/maps/dungeons/SteampunkMechanism.gd",   "world3_tempo_defeat"],
	["res://src/maps/dungeons/AssemblyCore.gd",         "world4_warden_defeat"],
	["res://src/maps/dungeons/RootProcess.gd",          "world5_arbiter_defeat"],
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_every_w2_w5_dungeon_declares_defeat_cutscene() -> void:
	for entry in DUNGEON_DEFEATS:
		var path: String = entry[0]
		var expected: String = entry[1]
		var src := _read(path)
		var quoted: String = "defeat_cutscene = \"" + expected + "\""
		assert_true(src.contains(quoted),
			"%s must declare defeat_cutscene = '%s' in _init — without it, DragonCave._on_boss_defeated skips the post-victory cutscene" % [path, expected])


func test_every_referenced_defeat_cutscene_file_exists() -> void:
	for entry in DUNGEON_DEFEATS:
		var expected: String = entry[1]
		var path: String = "res://data/cutscenes/" + expected + ".json"
		assert_true(FileAccess.file_exists(path),
			"Defeat cutscene file %s must exist on disk" % path)


func test_w6_null_chamber_defeat_cutscene_not_yet_authored() -> void:
	# Negative pin documenting why W6 is excluded: the Curator
	# defeat cutscene file doesn't exist yet. If a future commit
	# authors it AND wires NullChamber, this test should be removed
	# and that entry added to DUNGEON_DEFEATS above.
	assert_false(FileAccess.file_exists("res://data/cutscenes/world6_curator_defeat.json"),
		"If world6_curator_defeat.json now exists, wire NullChamber.defeat_cutscene and remove this guard")


func test_w1_castle_harmonia_defeat_cutscene_preserved() -> void:
	# Don't regress: W1 final boss (Mordaine / CastleHarmonia)
	# already had defeat_cutscene wired correctly.
	var src := _read("res://src/maps/dungeons/CastleHarmonia.gd")
	assert_true(src.contains("defeat_cutscene = \"world1_mordaine_defeat\""),
		"CastleHarmonia must still declare defeat_cutscene = 'world1_mordaine_defeat'")


func test_dragon_cave_still_reads_defeat_cutscene_field() -> void:
	# Sanity: the read path in DragonCave._on_boss_defeated must
	# still gate on `defeat_cutscene != ""` and call
	# director.play_cutscene with it. If a future refactor
	# repurposes the field, all 4 newly-wired dungeons silently
	# skip their cutscene.
	var src := _read("res://src/maps/dungeons/DragonCave.gd")
	assert_true(src.contains("if defeat_cutscene != \"\":"),
		"DragonCave._on_boss_defeated must still check defeat_cutscene != \"\"")
	assert_true(src.contains("director.play_cutscene(defeat_cutscene)"),
		"DragonCave._on_boss_defeated must still call director.play_cutscene(defeat_cutscene)")
