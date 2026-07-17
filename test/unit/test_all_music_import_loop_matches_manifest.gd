extends GutTest

## Full-manifest loop-agreement ratchet (2026-07-16).
##
## Every track that ships must have its .import `loop` flag agree with
## the manifest's `loop` key. Rationale is the same as the monster-track
## ratchet (test_battle_monster_import_loop_matches_manifest.gd): the
## runtime path _try_play_from_manifest overrides the .import loop with
## the manifest value, but other code paths (like _start_monster_music)
## bypass the manifest and load the OGG directly — .import then wins at
## runtime. The 2026-07-16 slime/bat regression was exactly this drift
## in the bypass path; extending the ratchet to the full manifest closes
## the same class of bug for every future new play-code path that skips
## the override.
##
## Two guarantees:
##   1. Any NEW mismatched track fails the gate on the first CI run.
##   2. Any KNOWN_LOOP_MISMATCHES entry that now agrees fails the gate
##      until it's removed from the snapshot — no stale allowlist drift.
##
## The current snapshot covers 53 tracks whose loop semantics are a
## user design ruling (should victory theme loop? should job_special
## stingers keep playing after triggering? etc. — logged on
## struktured's open-questions list per cowir-main msg 2625). Once he
## rules and the two files are aligned per class, entries drop off.


const MANIFEST_PATH := "res://data/music_manifest.json"

## Snapshot of manifest.loop ≠ .import loop as of 2026-07-16. All 53
## entries have manifest.loop=true, .import loop=false (runtime is
## correct because _try_play_from_manifest overrides). Remove an entry
## when the two files agree; add nothing without cowir-main sign-off.
const KNOWN_LOOP_MISMATCHES: Array[String] = [
	# One-shot stinger candidates (design Q: should these ever loop?)
	"victory",
	"victory_medieval",
	"victory_suburban",
	"victory_steampunk",
	"victory_industrial",
	"victory_digital",
	"victory_abstract",
	"job_fighter_special",
	"job_cleric_special",
	"job_mage_special",
	"job_rogue_special",
	"job_bard_special",
	"job_guardian_special",
	"job_ninja_special",
	"job_summoner_special",
	"job_speculator_special",
	"job_scriptweaver_special",
	"job_time_mage_special",
	"job_necromancer_special",
	"job_bossbinder_special",
	"job_skiptrotter_special",
	# Long-play candidates (should loop while player sits — currently manifest
	# says loop, .import says no; runtime override keeps them looping)
	"game_over",
	"credits_medieval",
	"credits_suburban",
	"credits_steampunk",
	"credits_industrial",
	"credits_digital",
	"credits_abstract",
	# Cutscene beds (should loop for dialogue reads; runtime override handles it)
	"cutscene_alt_breaker_speed",
	"cutscene_alt_witness_lament",
	"cutscene_w1_conscription",
	"cutscene_w1_warden_farewell",
	"cutscene_w1_mordaine_dissolution",
	"cutscene_w2_portal_arrival",
	"cutscene_w2_coordinator_memo",
	"cutscene_w3_pattern_recognized",
	"cutscene_w3_calibrant_revealed",
	"cutscene_w4_foreman_confession",
	"cutscene_w4_direct_engagement",
	"cutscene_w4_director_unmasked",
	"cutscene_w5_boot_sequence",
	"cutscene_w5_deprecated_goblin",
	"cutscene_w5_cached_memory",
	"cutscene_w5_calibrant_desk",
	"cutscene_w6_entering_nothing",
	"cutscene_w6_no_one_speaks",
	"cutscene_w6_calibrant_question",
	"cutscene_w6_memory_is_love",
	"cutscene_w6_answer_automation",
	"cutscene_w6_answer_manual",
	"cutscene_w6_answer_grind",
	"cutscene_w6_answer_exploit",
	"cutscene_w6_epilogue",
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _import_loop_flag(ogg_res_path: String) -> String:
	## Read `loop=` from an .import file. Returns "true", "false", or "" if absent.
	var text: String = _read(ogg_res_path + ".import")
	for line in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("loop="):
			return stripped.substr(len("loop=")).strip_edges().to_lower()
	return ""


func test_no_new_manifest_import_loop_drift() -> void:
	var text: String = _read(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary and parsed.has("tracks"),
		"music_manifest.json must parse into {tracks: {...}}")
	var tracks: Dictionary = parsed["tracks"]

	var actual_mismatches: Array[String] = []
	var checked: int = 0
	for key in tracks.keys():
		var k: String = str(key)
		var entry: Dictionary = tracks[k]
		var ogg_path: String = entry.get("file", "")
		if ogg_path == "":
			continue  # placeholder-only entries
		if not ogg_path.begins_with("res://"):
			ogg_path = "res://" + ogg_path
		var manifest_loop: bool = bool(entry.get("loop", false))
		var import_loop_str: String = _import_loop_flag(ogg_path)
		if import_loop_str == "":
			continue  # no loop line in .import — treat as separate concern
		var import_loop: bool = import_loop_str == "true"
		checked += 1
		if import_loop != manifest_loop:
			actual_mismatches.append(k)

	# Guarantee 1: no NEW drift.
	var known_set := {}
	for k in KNOWN_LOOP_MISMATCHES:
		known_set[k] = true
	var new_drift: Array[String] = []
	for k in actual_mismatches:
		if not known_set.has(k):
			new_drift.append(k)
	assert_eq(new_drift.size(), 0,
		"NEW manifest/import loop drift (%d): %s — runtime relies on _try_play_from_manifest override but any new bypass code path (like _start_monster_music) makes .import authoritative. Fix by aligning .import loop with manifest, OR add to KNOWN_LOOP_MISMATCHES with a documented reason." % [new_drift.size(), new_drift])

	# Guarantee 2: no snapshot rot — every allowlisted entry must still mismatch.
	var actual_set := {}
	for k in actual_mismatches:
		actual_set[k] = true
	var stale_allowlist: Array[String] = []
	for k in KNOWN_LOOP_MISMATCHES:
		if not actual_set.has(k):
			stale_allowlist.append(k)
	assert_eq(stale_allowlist.size(), 0,
		"KNOWN_LOOP_MISMATCHES entries that now AGREE — remove them from the allowlist (%d): %s" % [stale_allowlist.size(), stale_allowlist])

	assert_gt(checked, 100,
		"Sanity: expected 100+ tracks to be checked, got %d — manifest walk is broken" % checked)
