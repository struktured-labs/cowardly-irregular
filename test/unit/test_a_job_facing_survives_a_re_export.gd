extends GutTest

## The monster path learned this on 2026-07-26: chancellor_mordaine was re-exported 256px -> 128px
## for a SCALE bump and her facing silently reversed with it, caught only at fold review. The repair
## was `monster_faces_party` — declared `flip_h` wins, frame size is the fallback convention only.
##
## BattleScene's PARTY branch never got that repair. It read `get_height() > 128` inline and there
## was nothing a sheet could declare, so the same re-export on a job sheet would have flipped a
## party member to face away from the enemy line with no override to reach for.
##
## All 17 party sheets are 256px today, so the trigger is latent. It is not remote: the comparison
## is EXCLUSIVE (`> 128`), so a 256 -> 128 re-export lands exactly ON the failing side — and that is
## precisely the operation the monster incident was.

const LOADER = preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const SHEETS := "res://data/sprite_manifest.json"


func _sheets() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(SHEETS))
	return (d as Dictionary).get("sheets", {}) if d is Dictionary else {}


## The property the whole file defends: SIZE cannot move FACING for a sheet that declares one.
func test_a_declared_facing_is_immune_to_the_size_convention() -> void:
	var big := LOADER.job_faces_enemy("__no_such_job__", false)
	var small := LOADER.job_faces_enemy("__no_such_job__", true)
	assert_false(big, "CONTROL: an undeclared job must fall through to the convention it was handed")
	assert_true(small, "CONTROL: ...in both directions, else the convention arm is dead and every arm below is vacuous")
	assert_ne(big, small,
		"CONTROL: the convention must actually reach the result — if it cannot, this file cannot tell a declaration from a fallback")


## The monster twin's guard pins this for cave_rat_king. The party side has no declared sheet yet,
## so drive the mechanism through the loader's own static state rather than waiting for one to ship.
func test_a_declaration_outranks_a_re_export_in_both_directions() -> void:
	const PROBE := "zz_synthetic_facing_probe"
	LOADER._load_manifest()
	var had: bool = LOADER._manifest.has(PROBE)
	var prior = LOADER._manifest.get(PROBE, null)

	LOADER._manifest[PROBE] = {"path": "res://assets/sprites/jobs/fighter/", "flip_h": false}
	var declared_false_big := LOADER.job_faces_enemy(PROBE, false)
	var declared_false_small := LOADER.job_faces_enemy(PROBE, true)

	LOADER._manifest[PROBE] = {"path": "res://assets/sprites/jobs/fighter/", "flip_h": true}
	var declared_true_small := LOADER.job_faces_enemy(PROBE, true)
	var declared_true_big := LOADER.job_faces_enemy(PROBE, false)

	# The loader's manifest is STATIC — anything registered here must be removed, or the next file inherits it.
	if had:
		LOADER._manifest[PROBE] = prior
	else:
		LOADER._manifest.erase(PROBE)

	assert_false(declared_false_big, "a declared flip_h=false must hold when the convention says false")
	assert_false(declared_false_small,
		"RE-EXPORT: a declared flip_h=false flipped because the frame shrank past 128 — this is the mordaine defect on the party side")
	assert_true(declared_true_small, "a declared flip_h=true must hold when the convention says true")
	assert_true(declared_true_big,
		"RE-EXPORT: a declared flip_h=true flipped because the frame grew past 128 — the same defect in the other direction")


## WIRING: behaviour nothing calls protects nothing, and the inline `not _is_artist_sheet` is the defect.
func test_the_party_branch_resolves_facing_through_the_owner() -> void:
	var src := _code("res://src/battle/BattleScene.gd")
	assert_true(src.contains("flip_h = HybridSpriteLoaderClass.job_faces_enemy(job_id, not _is_artist_sheet)"),
		"WIRING: the party facing site no longer resolves through job_faces_enemy — a sheet's declared flip_h reaches nothing")
	assert_false(src.contains("sprite.flip_h = not _is_artist_sheet"),
		"OWNER: the inline size-infers-facing form is back in the party branch. That is the defect: a re-export silently reverses a party member's facing")
	assert_false(src.contains("not HybridSpriteLoaderClass.job_faces_enemy("),
		"INVERSION: `not job_faces_enemy(...)` is a DOUBLE inversion — it cancels for the convention and reverses every declared flip_h, the exact shape test_a_declared_facing_survives_the_dungeon.gd refuses for monsters")


## SCOPE: the trigger is latent only while every party sheet stays above the boundary.
func test_every_party_sheet_is_above_the_exclusive_boundary() -> void:
	var sheets := _sheets()
	assert_gt(sheets.size(), 10, "CONTROL: the sheets section must carry the job roster, else this arm reads nothing")
	var at_or_below: Array = []
	var scanned: Array = []
	for jid in sheets:
		var e = sheets[jid]
		if not (e is Dictionary):
			continue
		var p: String = str(e.get("path", ""))
		var idle: String = p if p.ends_with(".png") else p.rstrip("/") + "/idle.png"
		if not ResourceLoader.exists(idle):
			continue
		var tex: Texture2D = load(idle)
		if tex == null:
			continue
		scanned.append(jid)
		if tex.get_height() <= 128 and not (e is Dictionary and e.has("flip_h")):
			at_or_below.append("%s (%dpx)" % [jid, tex.get_height()])
	# named members the scan MUST reach — a count floor passes on the SURVIVORS (17 resolve, floor 10)
	for must in ["fighter", "cleric", "mage", "rogue", "bard"]:
		assert_true(scanned.has(must),
			"CORPUS: the scan never reached %s — it left the corpus and the count floor did not notice" % must)
	assert_gt(scanned.size(), 10, "CONTROL: scanned only %d sheets — the loop read almost nothing" % scanned.size())
	assert_eq(at_or_below, [],
		"UNDECLARED: %s sit at or below the exclusive 128 boundary and declare no flip_h, so the size convention alone decides their facing: %s" % [at_or_below.size(), at_or_below])


## Comments leave the corpus before any pin runs: a commented-out line carries every boundary a
## pattern can put on it (cowir-controller, 2026-09-18). A `#` inside a string truncates that line,
## which can only cost a false RED.
static func _code(path: String) -> String:
	var out := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		out += line.split("#")[0] + "\n"
	return out
