extends GutTest

## The opening scene's purpose-written theme was dropped by a refactor and the
## generic village bed took its place for five months.
##
## `b162510e` (2026-03-24, "wire 25 dedicated cutscene music tracks") gave
## world1_prologue the track `cutscene_w1_conscription` — titled "Nobody
## Special", briefed in tools/music_prompts.json as "a quiet medieval village at
## dawn, five ordinary people answer a call nobody expected them to answer".
## `c52c2e4a` (2026-04-08, "split prologue — village intro on entry, Theron
## quest on re-visit") rewrote the file, 100 insertions and 142 deletions, and
## the cue came out as `village_medieval`. That commit touched no other cutscene
## file, so the track was not relocated; it was lost.
##
## 🔑 THE TRACK WAS WRITTEN FROM THIS SCENE'S OWN TEXT. The narration reads
## "So five people showed up. Not because they were brave. Not because they were
## special. Because they were there." The theme is called "Nobody Special".
## Restoring it is repairing a regression, not making a musical choice — which
## matters, because a cue that looks like an authorial preference is exactly the
## kind nobody dares touch.
##
## ⚠️ AND IT WAS INVISIBLE FROM EITHER SIDE ALONE. The scene plays music, so
## nothing looked broken. The track exists and is healthy, so no audit flagged
## it. Only the JOIN — an authored bed that no scene names — shows it, which is
## what test_every_authored_bed_has_a_consumer computes. Of the 16 tracks
## b162510e wired, 15 are still cued and this was the only casualty.

const SCENE := "res://data/cutscenes/world1_prologue.json"
const AUTHORED_TRACK := "cutscene_w1_conscription"
const MANIFEST := "res://data/music_manifest.json"


func _scene() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(SCENE)
	assert_gt(raw.length(), 500, "SCOPE control: world1_prologue read back %d chars" % raw.length())
	return JSON.parse_string(raw) as Dictionary


func _music_cues() -> Array[String]:
	var out: Array[String] = []
	for step in (_scene().get("steps", []) as Array):
		if step is Dictionary and str((step as Dictionary).get("type", "")) == "play_music":
			out.append(str((step as Dictionary).get("track", "")))
	return out


func test_control_the_scene_is_the_one_this_test_means() -> void:
	## Pinning a cue on the wrong scene would pass forever while the opening
	## stayed generic. Anchor on the scene's own identity and its text.
	var d: Dictionary = _scene()
	assert_eq(str(d.get("id", "")), "world1_prologue",
		"SCOPE control: this file declares id '%s'" % d.get("id", ""))
	var raw: String = FileAccess.get_file_as_string(SCENE)
	assert_gt(raw.find("Not because they were special"), 0,
		"CONTROL FAILED: the narration this theme was written from is gone — if the scene was rewritten again, re-derive whether the cue still belongs here rather than making this test green")


func test_the_prologue_cues_its_authored_theme() -> void:
	var cues: Array[String] = _music_cues()
	assert_eq(cues.size(), 1,
		"expected exactly one play_music step in the prologue, found %d: %s" % [cues.size(), cues])
	assert_eq(cues[0], AUTHORED_TRACK,
		"the opening plays '%s' instead of its authored theme '%s' — this is how it regressed on 2026-04-08: a scene rewrite replaced the dedicated cue with the generic village bed, and nothing noticed for five months because the scene still had music" % [cues[0], AUTHORED_TRACK])


func test_the_authored_theme_still_exists_and_ships() -> void:
	## A cue naming a track that is not in the manifest is silence, and this one
	## is in W1 — the first music a new player hears.
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: walked %d manifest tracks" % tracks.size())
	assert_true(tracks.has(AUTHORED_TRACK),
		"%s is cued by the prologue but absent from the manifest" % AUTHORED_TRACK)
	var f: String = str((tracks[AUTHORED_TRACK] as Dictionary).get("file", ""))
	assert_true(ResourceLoader.exists(f),
		"%s is in the manifest but its file (%s) does not resolve" % [AUTHORED_TRACK, f])
