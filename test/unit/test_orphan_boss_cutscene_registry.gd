extends GutTest

## tick 243: tracked registry of "planned" boss intro cutscenes
## that exist as JSON files but have no code path triggering them.
##
## Most are Masterite per-world intro variants (Arbiter/Curator/
## Tempo/Warden across each non-base world) — content the story
## team authored anticipating the recurring-Masterite-boss
## mechanic that isn't wired yet. The world6_calibrant_intro is
## the final boss's intro, also not yet wired.
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
const KNOWN_PLANNED_INTROS: Array[String] = [
	"world1_arbiter_intro",
	"world1_curator_intro",
	"world1_tempo_intro",
	"world1_warden_intro",
	"world2_arbiter_intro",
	"world2_curator_intro",
	"world2_tempo_intro",
	"world3_arbiter_intro",
	"world3_curator_intro",
	"world3_warden_intro",
	"world4_arbiter_intro",
	"world4_curator_intro",
	"world4_tempo_intro",
	"world4_warden_intro",
	"world5_arbiter_intro",
	"world5_curator_intro",
	"world5_tempo_intro",
	"world5_warden_intro",
	"world6_calibrant_intro",
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
