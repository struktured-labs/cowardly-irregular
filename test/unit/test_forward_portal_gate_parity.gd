extends GutTest

## Forward-portal gate parity lint (cowir-main msg 2586 continuation).
##
## The v3.33.187 fix (7c585c26) surfaced the split-brain-portal-gate class:
## HarmoniaVillage's "Strange Device" portal was gated on `w1_boss_defeated`
## — a flag with NO setter since the progression rework moved W2-unlock to
## Mordaine. The overworld sibling portal got the tick-278 fix; this one
## was missed. Post-Mordaine players simply never saw the village portal.
##
## Every world's forward portal now uses the same canonical dual gate:
##   `is_world_unlocked(N+1) OR cutscene_flag_<world_boss>_defeated`
## The `is_world_unlocked` half handles save-load; the flag half fires
## the same tick the boss dies (no race). This lint pins the canonical
## shape on all 5 forward-portal sites so a future rename/rework can't
## silently drop half of the gate.

const FORWARD_PORTALS: Array = [
	# [source_path, world_unlocked_number, canonical_defeat_flag, note]
	["res://src/exploration/OverworldScene.gd",       2,
		"cutscene_flag_world1_mordaine_defeated",  "W1→W2 (Mordaine)"],
	["res://src/exploration/SuburbanOverworld.gd",    3,
		"cutscene_flag_warden_suburban_defeated",  "W2→W3 (Warden of Routine)"],
	["res://src/exploration/SteampunkOverworld.gd",   4,
		"cutscene_flag_tempo_steampunk_defeated",  "W3→W4 (Tempo of Progress)"],
	["res://src/exploration/IndustrialOverworld.gd",  5,
		"cutscene_flag_warden_industrial_defeated","W4→W5 (Warden of Yield)"],
	["res://src/exploration/FuturisticOverworld.gd",  6,
		"cutscene_flag_arbiter_futuristic_defeated","W5→W6 (Arbiter of Instances)"],
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


## Assert every forward portal declares BOTH halves of the canonical gate
## (world unlock AND boss-defeat flag) so a rename to just one silently
## strands the player at whichever half kept its stale flag.
func test_every_forward_portal_uses_the_canonical_dual_gate() -> void:
	for entry in FORWARD_PORTALS:
		var path: String = entry[0]
		var world_n: int = entry[1]
		var flag: String = entry[2]
		var note: String = entry[3]
		var src: String = _read(path)
		assert_ne(src, "", "%s must be readable" % path)
		# Both halves must appear in the same physical file. The lint
		# doesn't try to parse control flow — a stray reference elsewhere
		# in the file would falsely pass — but the forward-portal region
		# is the ONLY place these strings occur in these files today.
		assert_true(src.contains("is_world_unlocked(%d)" % world_n),
			"%s (%s) missing 'is_world_unlocked(%d)' — save-load half of the gate" % [
				path, note, world_n])
		assert_true(src.contains("\"" + flag + "\""),
			"%s (%s) missing '\"%s\"' — same-tick defeat half of the gate" % [
				path, note, flag])


## The Harmonia in-village "Strange Device" is the ONLY in-village world
## portal (a diegetic gag exclusive to W1). Its gate MUST match the
## OverworldScene W1→W2 gate exactly — the split-brain fix cowir-main
## just made permanent (v3.33.187).
func test_harmonia_strange_device_matches_overworld_w1_gate() -> void:
	var harmonia := _read("res://src/maps/villages/HarmoniaVillage.gd")
	assert_ne(harmonia, "", "HarmoniaVillage readable")
	# Anchor on the "SuburbanPortal" name so any drift lands in this test.
	assert_true(harmonia.contains("suburban_portal.name = \"SuburbanPortal\""),
		"HarmoniaVillage builds a SuburbanPortal (the Strange Device)")
	# Both halves of the W1→W2 gate must be in the file.
	assert_true(harmonia.contains("is_world_unlocked(2)"),
		"Strange Device gate missing is_world_unlocked(2) — save-load half")
	assert_true(harmonia.contains("cutscene_flag_world1_mordaine_defeated"),
		"Strange Device gate missing Mordaine flag — same-tick half")
	# The stale w1_boss_defeated flag must not resurface as a gate. It was
	# the culprit in v3.33.187; the lint holds the line.
	var w1_boss_lines := 0
	for line in harmonia.split("\n"):
		if line.contains("w1_boss_defeated") and (line.contains("is_story_flag_set") \
				or line.contains("get_story_flag")):
			w1_boss_lines += 1
	assert_eq(w1_boss_lines, 0,
		"HarmoniaVillage must not re-read the dead w1_boss_defeated flag as a gate")


## Belt-and-suspenders: the OverworldScene Castle Harmonia gate is the
## OTHER half of the pair. If either side drifts, the pair breaks —
## same failure class as v3.33.187 (village portal never spawned) but
## in the opposite direction. Pin both files together.
func test_castle_harmonia_gate_matches_strange_device() -> void:
	var overworld := _read("res://src/exploration/OverworldScene.gd")
	assert_ne(overworld, "", "OverworldScene readable")
	# The Castle Harmonia W1→W2 gate line — pin both halves.
	assert_true(overworld.contains("is_world_unlocked(2)"),
		"OverworldScene W1→W2 gate must include is_world_unlocked(2)")
	assert_true(overworld.contains("cutscene_flag_world1_mordaine_defeated"),
		"OverworldScene W1→W2 gate must include the Mordaine defeat flag")
