extends GutTest

## Approaching a boss area must play the danger bed, not peaceful overworld music.
##
## DangerZone ("pulsing red vignette + danger music near boss areas") calls
## SoundManager.play_area_music("danger") at :65. _start_area_music_deferred's
## `match area_type:` had no "danger" arm, so it fell to `_:` ->
## _start_overworld_music(), which hardcodes overworld_medieval. The vignette
## pulsed and the music stayed peaceful — for every approach, in the only world
## that has a DangerZone.
##
## 🔑 WHY IT SURVIVED: THE BUG'S OUTPUT WAS THE STATUS QUO. The player is on the
## overworld when they walk toward a boss, so overworld music is ALREADY
## playing. Falling through to _start_overworld_music() re-plays the bed that
## was playing anyway — an inaudible failure. A wrong arm would have been heard
## in a second; the missing arm sounded exactly like nothing happening.
##
## ⚠️ AND `_start_danger_music()` EXISTED AND WAS CORRECT THE WHOLE TIME —
## world-aware, `danger_<suffix>` then `danger` then procedural. Six danger beds
## are authored (29s-149s). Nothing was missing except the one line that reaches
## them. The other caller, BattleScene:5817, uses play_music("danger") — a
## DIFFERENT API whose generic-rewrite arm has always resolved it, which is why
## danger music works at low HP in battle and never worked on the overworld.
## Two entry points, one key, one of them wired: [[project_music_two_api_hazard]].

const SOUNDMANAGER := "res://src/audio/SoundManager.gd"


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager._current_area = ""


func _play_area_and_settle(area: String) -> String:
	## play_area_music defers the actual start so scene setup is not blocked.
	SoundManager.play_area_music(area)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: AudioStreamPlayer = SoundManager._music_player
	if p == null or p.stream == null:
		return ""
	return p.stream.resource_path


func test_control_a_known_area_key_loads_its_own_bed() -> void:
	## If this fails the probe is broken, not the subject — read it before
	## trusting the arm below. It also proves resource_path DISCRIMINATES, which
	## is the whole basis of the next test.
	var path: String = await _play_area_and_settle("overworld")
	assert_ne(path, "", "SCOPE control: overworld produced no stream at all — the probe measures nothing")
	assert_true(path.contains("overworld"),
		"CONTROL FAILED: area 'overworld' loaded %s, which is not an overworld bed — the probe cannot tell beds apart" % path)


func test_danger_zone_gets_the_danger_bed_not_the_overworld() -> void:
	var path: String = await _play_area_and_settle("danger")
	assert_ne(path, "", "SCOPE control: 'danger' produced no stream at all")
	assert_false(path.contains("overworld"),
		"approaching a boss loaded %s — the missing `danger` arm fell through to `_:` and re-played the bed that was already playing, so the danger music never fires and the failure is INAUDIBLE" % path)
	assert_true(path.contains("danger"),
		"expected a danger_* bed, got %s" % path)


func test_every_area_key_the_game_asks_for_has_an_arm() -> void:
	## The structural half: this is the check that would have caught it. A key
	## with no arm is not an error — `_:` swallows it and plays medieval
	## overworld — so nothing anywhere reports the miss.
	var src: String = FileAccess.get_file_as_string(SOUNDMANAGER)
	assert_gt(src.length(), 5000, "SCOPE control: SoundManager.gd read back %d chars" % src.length())
	var start: int = src.find("func _start_area_music_deferred")
	assert_gt(start, 0, "SCOPE control: _start_area_music_deferred not found")
	var blk: String = src.substr(start, 4000)
	blk = blk.substr(blk.find("match area_type:"))

	## ⚠️ Arms are grouped ("village", "harmonia_village":) and tab-indented.
	## A `\t` inside a grep -E pattern matches a literal 't' on this box, which
	## is how an earlier pass here parsed ZERO arms and reported all 11 call
	## sites as unwired. Match the quoted keys, not the indentation.
	var arms: Array[String] = []
	var re := RegEx.new()
	re.compile("\"([a-z_0-9]+)\"\\s*(?:,\\s*\"[a-z_0-9]+\"\\s*)*:")
	for line in blk.split("\n"):
		var t: String = line.strip_edges()
		if not t.ends_with(":") or t.begins_with("#"):
			continue
		var q := RegEx.new()
		q.compile("\"([a-z_0-9]+)\"")
		for m in q.search_all(t):
			if not arms.has(m.get_string(1)):
				arms.append(m.get_string(1))
	assert_gt(arms.size(), 10,
		"SCOPE control: parsed only %d arms — the walk is broken and a green here would be vacuous" % arms.size())
	assert_true(arms.has("overworld"),
		"CONTROL FAILED: 'overworld' missing from the parsed arms %s — the parse found something, but not the area keys" % [arms])

	var asked: Dictionary = {}
	var call_re := RegEx.new()
	call_re.compile("play_area_music\\(\\s*\"([a-z_0-9]+)\"\\s*\\)")
	for f in _gd_files("res://src"):
		var body: String = FileAccess.get_file_as_string(f)
		for m in call_re.search_all(body):
			asked[m.get_string(1)] = f
	assert_gt(asked.size(), 5,
		"SCOPE control: found only %d literal play_area_music keys" % asked.size())

	var unwired: Array[String] = []
	for k in asked.keys():
		## interior_* is resolved by _resolve_interior_track, not the match.
		if str(k).begins_with("interior_"):
			continue
		if not arms.has(str(k)):
			unwired.append("%s (called from %s)" % [k, asked[k]])
	assert_eq(unwired.size(), 0,
		"area keys the game asks for with no match arm (%d of %d): %s — these fall to `_:` and silently play medieval overworld music" % [unwired.size(), asked.size(), unwired])


func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		var p: String = root + "/" + n
		if d.current_is_dir():
			out.append_array(_gd_files(p))
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()
	return out
