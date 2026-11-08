extends GutTest

## main 23604: "same real time at every battle speed" is a GAME-time tween/timer at speed_scale 1/Engine.time_scale, never
## ignore_time_scale, which steps on a clock that runs ahead of Movie Maker (measured: a 0.53 s beat landed in ~3 video
## frames, cutscenes 23597) and of a hitched frame. Both spellings are derived from src (battle 23608): a tween's
## set_ignore_time_scale(true), and create_timer's 4th argument. A site passes only when DECLARED below with its owner and
## why; a declared site that no longer exists is stale and reds, so the list cannot rot.

const TWEEN_FORM := "set_ignore_time_scale(true)"
## create_timer(t, process_always, process_in_physics, ignore_time_scale): the 4th argument true.
const TIMER_RE := "create_timer\\([^)]*,[^)]*,[^)]*,\\s*true\\s*\\)"

## One entry per SITE: [path, a substring unique to that line, "KEEP|PENDING owner: why"]. KEEP = real time is correct
## (it measures the real world); PENDING = its owner converts it in .791 and deletes the line (main 23611/23615).
const DECLARED := [
	["res://src/battle/BattleManager.gd", "GLOAT_WAIT_SEC", "KEEP cowir-ai: LLM response deadline, real-time network latency"],
	["res://src/ui/Win98Menu.gd", "create_timer(0.08", "KEEP cowir-controller: input debounce, real-time player input"],
	["res://src/ui/Win98Menu.gd", "create_timer(0.05", "KEEP cowir-controller: input debounce, real-time player input"],
	["res://src/ui/Win98Menu.gd", "_readout_shake", "PENDING cowir-controller: the AP-readout shake"],
	["res://src/ui/GameOverScreen.gd", "tween.set_ignore_time_scale", "PENDING cowir-controller: the GAME OVER fades"],
	["res://src/audio/SoundManager.gd", "_kill_duck_tween", "PENDING cowir-music: mix fade, per-frame step"],
	["res://src/audio/SoundManager.gd", "_jingle_duck_tween", "PENDING cowir-music: mix fade, per-frame step"],
	["res://src/audio/SoundManager.gd", "_crossfade_tween", "PENDING cowir-music: mix fade, per-frame step"],
	["res://src/audio/SoundManager.gd", "_fade_in_tween", "PENDING cowir-music: mix fade, per-frame step"],
	["res://src/audio/SoundManager.gd", "_danger_tween", "PENDING cowir-music: mix fade, per-frame step"],
	["res://src/audio/SoundManager.gd", "_corruption_tween", "PENDING cowir-music: mix fade, per-frame step"],
	["res://src/battle/BattleManager.gd", "TRUST_INTERRUPT_WINDOW_SECONDS", "PENDING cowir-battle: the trust window"],
	["res://src/battle/BattleResultsDisplay.gd", "downbeat_wait", "PENDING cowir-battle: the downbeat wait"],
	["res://src/battle/BattleScene.gd", "var t := create_tween().set_ignore_time_scale", "PENDING cowir-battle: the chain-intro banner"],
	["res://src/GameLoop.gd", "create_timer(0.5, true", "PENDING cowir-battle: _wait_for_confirm_victory"],
	["res://src/GameLoop.gd", "create_timer(0.25, true", "PENDING cowir-battle: _wait_for_confirm_victory debounce"],
	["res://src/GameLoop.gd", "GRIND_STOP_BANNER_SEC", "PENDING cowir-autogrind: the grind stop-banner wait"],
	["res://src/battle/BattleSpeechBubble.gd", "tween.set_ignore_time_scale", "PENDING cowir-cutscenes: the bubble tween"],
	["res://src/cutscene/InnRestSequence.gd", "moon_tw", "PENDING cowir-cutscenes: the inn moon"],
	["res://src/cutscene/InnRestSequence.gd", "var tw := create_tween", "PENDING cowir-cutscenes: the inn fade"],
]


func _sites() -> Array:
	var re := RegEx.new()
	re.compile(TIMER_RE)
	var out := []
	var dirs: Array[String] = ["res://src"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			dirs.append("%s/%s" % [d, sub])
		for f in da.get_files():
			if not f.ends_with(".gd"):
				continue
			var path := "%s/%s" % [d, f]
			for line in FileAccess.get_file_as_string(path).split("\n"):
				var code := line.strip_edges()
				if code.begins_with("#"):
					continue
				if TWEEN_FORM in code or re.search(code) != null:
					out.append([path, code])
	return out


func _declared_for(site: Array) -> int:
	for i in DECLARED.size():
		if DECLARED[i][0] == site[0] and str(DECLARED[i][1]) in str(site[1]):
			return i
	return -1


func test_no_undeclared_site_steps_on_the_os_clock() -> void:
	var sites := _sites()
	assert_gt(sites.size(), 0, "CONTROL: the scan found the declared sites (an empty scan proves nothing)")
	var undeclared: Array[String] = []
	for site in sites:
		if _declared_for(site) < 0:
			undeclared.append("%s: %s" % [site[0], site[1]])
	assert_eq(undeclared, [] as Array[String],
		"use game time (speed_scale 1/Engine.time_scale, or a per-frame step if it can straddle a time_scale change), or declare the site with owner + why")


func test_no_declared_site_is_stale_or_unexplained() -> void:
	var sites := _sites()
	var matched := {}
	for site in sites:
		var i := _declared_for(site)
		if i >= 0:
			matched[i] = true
	var bad: Array[String] = []
	for i in DECLARED.size():
		var why := str(DECLARED[i][2])
		if not matched.has(i):
			bad.append("%s '%s' matches no live site: delete its line" % [DECLARED[i][0], DECLARED[i][1]])
		elif not (why.begins_with("KEEP ") or why.begins_with("PENDING ")):
			bad.append("%s '%s' must say KEEP or PENDING with owner + why" % [DECLARED[i][0], DECLARED[i][1]])
	assert_eq(bad, [] as Array[String], "the declared list must name only live sites, each KEEP/PENDING with a reason")


func test_the_scan_sees_both_spellings() -> void:
	var re := RegEx.new()
	re.compile(TIMER_RE)
	assert_true(re.search("await get_tree().create_timer(0.2, true, false, true).timeout") != null, "CONTROL: the timer spelling matches")
	assert_null(re.search("await get_tree().create_timer(0.2).timeout"), "CONTROL: a game-time timer does not")
	assert_true(TWEEN_FORM in "var t := create_tween().set_ignore_time_scale(true)", "CONTROL: the tween spelling matches")
