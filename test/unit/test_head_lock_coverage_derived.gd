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
## Sheets deliberately outside the head-lock gate, each with a reason.
## A bare name is not acceptable — an unexplained exemption is how a to-do list
## forms — and test_every_exemption_is_still_EARNED makes a stale entry FAIL.
##
## EMPTY, and the emptying is the point. I first listed five named-NPC sheets
## here at "32 diffs, pending struktured's eye". That 32 came from a CORRECTED
## largest-band anchor I measured with; the gate itself still uses the
## first-opaque-row anchor, which I deliberately left alone. Under the gate's
## OWN helpers all five measure 0, so they never failed it and the exemptions
## were unearned the moment I wrote them. Caught by the expiry test, not by
## re-reading — which is the whole argument for having one.
const EXEMPT := {}


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


func test_every_exemption_is_still_EARNED() -> void:
	# THE EXPIRY. Without this, EXEMPT is a note that waits: repair bram and the
	# entry silently becomes false, because nothing re-reads a dated comment.
	#
	# I fixed exactly this shape in KNOWN_HEAVY_TOP this morning -- a drained
	# exemption list whose earned invariant went unguarded -- and then created a
	# new list the same afternoon without one. cowir-cutscenes 2026-07-30: an
	# artifact's own account of itself is the thing that misleads the next
	# reader, and "open the file" is the remedy that fails there. A comment
	# cannot expire; a test can.
	#
	# Measured through the HEAD-LOCK TEST'S OWN helpers, not a copy of them, so
	# the exemption is earned by the gate's metric rather than by my
	# re-derivation of it. A duplicate could drift and then exempt on grounds
	# the gate no longer uses.
	var gate = load("res://test/unit/test_overworld_head_lock_regression.gd").new()
	assert_ne(gate, null, "the head-lock test must instantiate — its helpers are the metric")
	if gate == null:
		return
	autofree(gate)

	var unearned: Array = []
	for name in EXEMPT:
		var path := "res://assets/sprites/npcs/%s/overworld.png" % name
		if not ResourceLoader.exists(path):
			continue  # the other test reports a missing sheet
		var img: Image = (load(path) as Texture2D).get_image()
		var worst := 0
		for row in range(4):
			var bbox: Vector2i = gate._frame_bbox_y(img, row, 0)
			if bbox.x < 0:
				continue
			var head_h: int = maxi(1, int(float(bbox.y - bbox.x + 1) * 0.65))
			var lock_end: int = mini(32, bbox.x + head_h)
			for col in [1, 2, 3]:
				var d: int = gate._head_pixels_match(img, row, 0, col, bbox.x, lock_end)
				for dy in [-1, 1]:
					d = mini(d, gate._head_pixels_match_shifted(img, row, 0, col, bbox.x, lock_end, dy))
				worst = maxi(worst, d)
		if worst < 4:
			unearned.append("%s now measures %d diffs (< 4)" % [name, worst])

	assert_eq(unearned, [],
		("exemption(s) no longer earned — the sheet passes the gate now, so the " +
		 "EXEMPT entry is stale and must be DELETED and the name added to " +
		 "NPC_ARCHETYPES instead. An exemption that outlives its reason is how " +
		 "a to-do list forms: %s") % [unearned])


func test_exempt_entries_all_carry_a_reason_and_still_exist() -> void:
	# Both directions: an exemption with no reason is a hole, and an exemption
	# for a sheet that no longer exists is stale coverage claiming to be real.
	var on_disk := _sheet_names("res://assets/sprites/jobs")
	for npc in _sheet_names("res://assets/sprites/npcs"):
		on_disk.append(npc)
	# COLLECT, then assert ONCE — so this still asserts with EXEMPT empty.
	# Asserting inside the loop made it score [Risky] the moment my own fix
	# emptied the list: the KNOWN_HEAVY_TOP defect I repaired this morning,
	# recreated this afternoon, and caught by the detector rather than by me.
	# An assertion inside a loop over a list that can drain is a guard that
	# retires itself on success.
	var bad: Array = []
	for name in EXEMPT:
		var reason: String = EXEMPT[name]
		if reason.length() <= 20:
			bad.append("%s: reason too thin ('%s')" % [name, reason])
		if not (name in on_disk):
			bad.append("%s: names a sheet not on disk — stale exemption" % name)
	assert_eq(bad, [],
		("every EXEMPT entry must carry a real reason (>20 chars) and name a " +
		 "sheet that exists — an unexplained exemption is a silent to-do: %s") % [bad])
