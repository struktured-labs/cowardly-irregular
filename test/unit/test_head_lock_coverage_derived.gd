extends GutTest

## The head-lock gate's coverage is a HAND LIST. This joins it to the corpus.
##
## test_overworld_head_lock_regression checks STARTER_JOBS (4) + NPC_ARCHETYPES
## (21) = 25 sheets. There are 41 overworld.png files on disk. Nothing joined
## the list to the corpus, so 16 sheets — including every named story NPC and
## all nine advanced/meta jobs — were never checked and nobody could tell.
##
## Measured 2026-07-30: of those 16, five named-NPC sheets (bram, elder_theron,
## marta, phil, scholar_milo) show 32 diffs in the gate's own band against its
## <4 threshold. Whether 32px of a 640px band reads as head jitter or as
## legitimate arm swing is a perceptual call, so this test does NOT assert
## anything about their quality — it asserts only that a sheet cannot be
## invisible to the gate. Deciding those five is struktured's, with his eyes.
##
## This is the fifth instance of one class found this session: a hand-maintained
## list and a data corpus with no check across them. The others were masterite
## pools (data, no spawn path), six giverless quests (quest JSON, no NPC),
## Aria (frames on disk, loader refusing them), and 49 spells falling through a
## 24-entry sound map. Each corpus was internally valid; the relationship wasn't.

const HEAD_LOCK_TEST := "res://test/unit/test_overworld_head_lock_regression.gd"

## Sheets deliberately outside the head-lock gate, each with a reason.
## A bare name here is not acceptable — the reason is the point, because an
## unexplained exemption is how KNOWN_HEAVY_TOP nearly became a to-do list.
const EXEMPT := {
	"bram": "32 diffs in the gate's band (f1 and f3, all 4 rows) — real and systematic, but 32px of a 640px band may be arm swing rather than head jitter. Perceptual call, struktured's, 2026-07-30",
	"elder_theron": "32 diffs, same signature as bram — pending struktured's eye, 2026-07-30",
	"marta": "32 diffs, same signature as bram — pending struktured's eye, 2026-07-30",
	"phil": "32 diffs, same signature as bram — pending struktured's eye, 2026-07-30",
	"scholar_milo": "32 diffs, same signature as bram — pending struktured's eye, 2026-07-30",
}


func _sheet_names(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for entry in d.get_directories():
		if ResourceLoader.exists("%s/%s/overworld.png" % [dir_path, entry]):
			out.append(entry)
	out.sort()
	return out


func _listed_in_head_lock_test() -> Array:
	var src := FileAccess.get_file_as_string(HEAD_LOCK_TEST)
	assert_ne(src, "", "the head-lock test must be readable — this check is about ITS coverage")
	var names: Array = []
	# Both const arrays are plain string literals; take every quoted token.
	var rx := RegEx.new()
	rx.compile('"([a-z_0-9]+)"')
	for m in rx.search_all(src):
		names.append(m.get_string(1))
	return names


func test_every_overworld_sheet_is_visible_to_the_head_lock_gate() -> void:
	var listed := _listed_in_head_lock_test()
	# NAMED controls, not a count. The extraction takes every quoted lowercase
	# token, so path fragments ("res", "assets", "png") inflate the total —
	# a size floor would pass even if real sheet names stopped being extracted.
	# cowir-battle's distinction (2026-07-30): a control asserting "the sweep
	# found something" cannot fail usefully; one asserting "the sweep sees THIS
	# KNOWN MEMBER" can. Their status join returned a clean 0 until a named
	# control showed `poison` missing from a set that plainly contained it.
	for known in ["fighter", "dr_temporal", "bard", "chancellor_mordaine"]:
		assert_true(known in listed,
			("the gate's lists must yield '%s' — it is there in the source, so " +
			 "if this fails the extraction shape has drifted and every result " +
			 "below is measuring the wrong set") % known)

	var on_disk: Array = []
	for job in _sheet_names("res://assets/sprites/jobs"):
		on_disk.append(job)
	for npc in _sheet_names("res://assets/sprites/npcs"):
		on_disk.append(npc)
	assert_gt(on_disk.size(), 30,
		"sanity: expected >30 overworld sheets on disk, found %d" % on_disk.size())

	var invisible: Array = []
	for name in on_disk:
		if name in listed:
			continue
		if EXEMPT.has(name):
			continue
		invisible.append(name)
	invisible.sort()

	assert_eq(invisible, [],
		("%d overworld sheet(s) exist but the head-lock gate never checks them. " +
		 "Add each to STARTER_JOBS/NPC_ARCHETYPES in the head-lock test, or to " +
		 "EXEMPT here WITH A REASON. A sheet that is invisible to the gate can " +
		 "drift forever without failing anything: %s") % [invisible.size(), str(invisible)])


func test_exempt_entries_all_carry_a_reason_and_still_exist() -> void:
	# Both directions: an exemption with no reason is a hole, and an exemption
	# for a sheet that no longer exists is stale coverage claiming to be real.
	var on_disk := _sheet_names("res://assets/sprites/jobs")
	for npc in _sheet_names("res://assets/sprites/npcs"):
		on_disk.append(npc)
	for name in EXEMPT:
		var reason: String = EXEMPT[name]
		assert_gt(reason.length(), 20,
			"EXEMPT['%s'] needs a real reason, not '%s' — an unexplained exemption is a silent to-do" % [name, reason])
		assert_true(name in on_disk,
			"EXEMPT['%s'] names a sheet that is not on disk — stale exemption, remove it" % name)
