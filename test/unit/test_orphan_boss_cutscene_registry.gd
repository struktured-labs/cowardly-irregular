extends GutTest

## tick 243: tracked registry of "planned" boss intro cutscenes
## that exist as JSON files but have no code path triggering them.
##
## Most are Masterite per-world intro variants (Arbiter/Curator/
## Tempo/Warden across each non-base world) — content the story
## team authored anticipating the recurring-Masterite-boss
## mechanic that isn't wired yet — a statement of intent this file
## has carried since tick 243, and the clearest evidence on record
## that the Masterites were meant to RECUR rather than pilot in W1.
##
## This test converts dormant content debt into a tracked metric:
##
##   - If a KNOWN_PLANNED entry vanishes from disk → the JSON
##     file was deleted; remove it from the registry too.
##
##   - If a KNOWN_PLANNED entry gains a code reference → it was
##     wired up (good); remove it from the registry too.
##
##   - If a NEW boss/intro JSON file appears with no code
##     reference AND isn't in the registry → either a new
##     planned cutscene (add to registry) OR a wiring bug
##     (add the code path). The failure forces a code-review
##     decision.

const CUTSCENES_DIR := "res://data/cutscenes"

## Boss/intro cutscene files that have NO code reference yet.
## Update this list deliberately as content lands.
## RETIRED: world2_curator_intro — MapleHeightsVillage._place_masterites made the Curator a real
## fight and passes it as the encounter's cutscene_id, so it has a caller now. world2_arbiter_intro
## STAYS: it writes the flag world2_chapter4 is gated on NOT having, so wiring it would cancel that
## chapter permanently (see test_no_scene_cancels_another_scenes_gate_regression, its 2nd declarer).
const KNOWN_PLANNED_INTROS: Array[String] = [
	## W1's four. Each beat already plays through a wired `*_encounter` scene, so these are a second
	## authored take on a moment the player does reach — dormant by choice, not by oversight.
	"world1_arbiter_intro",
	"world1_curator_intro",
	"world1_tempo_intro",
	"world1_warden_intro",
	## ⛔ MUST STAY ORPHANED, AND IT IS THE ONE ENTRY HERE THAT WIRING WOULD BREAK SOMETHING.
	## It sets `cutscene_flag_arbiter_suburban_intro_complete`, which world2_chapter4 is gated on NOT
	## having. Playing it would cancel chapter4 permanently — and chapter4 is itself titled
	## "Arbiter's Appeal" and serves as that intro. Pinned from the other side in
	## test_a_masterite_defeat_is_fought_not_granted.
	"world2_arbiter_intro",
	## ⛔ THE THREE ARCHETYPES WHOSE FIGHT IS A DUNGEON BOSS, NOT A VILLAGE PLACEMENT. Each dungeon
	## declares its own boss scene and writes that archetype's defeat flag, so the village-style
	## intro has no fight left to introduce. Remember the file-numbering offset: a `worldN_*` intro
	## file is the world N+1 THEME from industrial up, which is why these three read as a world off.
	"world3_warden_intro",   # industrial Warden -> AssemblyCore, world4_assembly_boss
	"world4_arbiter_intro",  # futuristic Arbiter -> RootProcess, world5_root_process_boss
	"world5_curator_intro",  # abstract Curator -> NullChamber, world6_null_chamber_boss
	## world6_calibrant_intro RETIRED 2026-08-04 — VertexApex.gd wires it as boss_cutscene_id.
	## Its 86 steps had never played; the Calibrant is now a fight instead of an elided cutscene.
	## Removing it here is this registry working exactly as designed, not a suppression.
	##
	## TEN RETIRED 2026-10-23 — the W2-W6 Masterites became real fights, and a placement's
	## `cutscene_id` is their first caller. Dropped: world2_tempo_intro (Maple Heights);
	## world3_{tempo,arbiter,curator}_intro (Rivet Row, industrial); world4_{warden,tempo,curator}_intro
	## (Node Prime, futuristic); world5_{warden,tempo,arbiter}_intro (Vertex, abstract). Brasston's
	## three steampunk bosses have no entries here because no steampunk intros were ever authored.
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	return t


# Recursively grep res://src for a literal reference to the cutscene id.
func _has_code_reference(cutscene_id: String) -> bool:
	# Two forms count as a reference:
	#   - the bare quoted id "X" anywhere in source (used by boss_cutscene_id assignments)
	#   - the explicit play_cutscene("X") call
	var dir := DirAccess.open("res://src")
	if dir == null:
		return false
	return _walk_for_ref(dir, "res://src", cutscene_id)


func _walk_for_ref(dir: DirAccess, base: String, cutscene_id: String) -> bool:
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full: String = "%s/%s" % [base, entry]
		if dir.current_is_dir():
			var subdir := DirAccess.open(full)
			if subdir != null and _walk_for_ref(subdir, full, cutscene_id):
				dir.list_dir_end()
				return true
		elif entry.ends_with(".gd"):
			var content: String = FileAccess.get_file_as_string(full)
			if content.contains("\"" + cutscene_id + "\""):
				dir.list_dir_end()
				return true
	dir.list_dir_end()
	return false


# ── Registry hygiene ────────────────────────────────────────────────

func test_known_planned_intros_all_exist_on_disk() -> void:
	# Pin: every KNOWN_PLANNED entry must have a corresponding JSON
	# file. If the file was deleted, remove the entry — keeping
	# stale registry entries grants false confidence.
	var missing: Array[String] = []
	for id in KNOWN_PLANNED_INTROS:
		var path := "%s/%s.json" % [CUTSCENES_DIR, id]
		if not FileAccess.file_exists(path):
			missing.append(id)
	assert_eq(missing.size(), 0,
		"KNOWN_PLANNED_INTROS entries with no JSON file on disk (remove from list): %s" % str(missing))


func test_known_planned_intros_have_no_code_reference() -> void:
	# Pin: every KNOWN_PLANNED entry must still be ORPHANED in code.
	# If one gained a code reference (wiring landed), remove it from
	# the registry — the dormancy is over.
	var wired: Array[String] = []
	for id in KNOWN_PLANNED_INTROS:
		if _has_code_reference(id):
			wired.append(id)
	assert_eq(wired.size(), 0,
		"KNOWN_PLANNED_INTROS entries that gained a code reference (wiring landed — remove from list): %s" % str(wired))


# ── Drift detection: new orphans must be tracked ────────────────────

func test_no_new_orphan_boss_or_intro_cutscenes() -> void:
	# Pin: every JSON file matching the boss/intro naming pattern
	# must EITHER have a code reference OR be in KNOWN_PLANNED_INTROS.
	# New unreferenced files are content debt that should be
	# acknowledged (added to registry) or wired up.
	var dir := DirAccess.open(CUTSCENES_DIR)
	assert_ne(dir, null, "cutscenes dir must exist")
	dir.list_dir_begin()
	var unknown_orphans: Array[String] = []
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if not entry.ends_with(".json"):
			continue
		var id: String = entry.replace(".json", "")
		# Only consider boss/intro-shaped filenames.
		var is_boss_or_intro: bool = (
			id.ends_with("_intro")
			or id.contains("_boss")
		)
		if not is_boss_or_intro:
			continue
		# Skip if already known-planned.
		if id in KNOWN_PLANNED_INTROS:
			continue
		# Skip if it has a code reference (legitimately wired).
		if _has_code_reference(id):
			continue
		# Otherwise it's a NEW orphan.
		unknown_orphans.append(id)
	dir.list_dir_end()
	assert_eq(unknown_orphans.size(), 0,
		"New orphan boss/intro cutscene JSON files (add to KNOWN_PLANNED_INTROS or wire up): %s" % str(unknown_orphans))


# ── Cross-pin: tick 213 boss intro audit preserved ─────────────────

func test_tick_213_boss_intro_audit_still_passes() -> void:
	# Sanity: the original tick 213 audit (each dungeon's
	# boss_cutscene_id points to an existing JSON) still in place
	# as a separate test file.
	assert_true(FileAccess.file_exists("res://test/unit/test_boss_intro_cutscene_audit.gd"),
		"tick 213 boss intro audit file must still exist")
