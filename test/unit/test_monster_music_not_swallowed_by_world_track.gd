extends GutTest

## struktured 2026-08-29, playing v3.33.212-alpha: "The goblin music is gone and defaults to
## something else. I wanted it replaced not removed entirely."
##
## 7e6c50d2 recast battle_goblin.ogg as battle_brute.ogg on his earlier note that the theme was
## "too barbarian sounding". Correct call — but nothing replaced the goblin's manifest key, and
## play_music rewrites ANY manifest-less `battle_*` to the world battle track BEFORE reaching the
## `match` that dispatches procedural monster themes. So the goblin's own arm became unreachable
## and it played battle_medieval like every ordinary fight.
##
## The fix exempts tracks that have a procedural generator. This pins BOTH directions of that
## list, because a hand-maintained set of names that must mirror a `match` block is exactly the
## thing that drifts silently.

const SM_SRC := "res://src/audio/SoundManager.gd"


func _src() -> String:
	var s := FileAccess.get_file_as_string(SM_SRC)
	assert_gt(s.length(), 5000, "CONTROL: read a real file")
	return s


func _play_music_body(src: String) -> String:
	var i: int = src.find("func play_music(")
	assert_gt(i, -1, "play_music must exist")
	var e: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (e - i) if e > -1 else src.length() - i)


func test_the_exemption_list_exists_and_names_the_goblin() -> void:
	var src := _src()
	assert_true(src.contains("PROCEDURAL_BATTLE_TRACKS"), "the exemption list must exist")
	assert_true(src.contains('"battle_goblin"'), "battle_goblin must be exempt — it is the reported bug")


func test_every_procedural_arm_is_in_the_exemption_list() -> void:
	# Direction 1. A monster with a generator but no exemption loses its theme to the world
	# rewrite — silently, exactly as the goblin did.
	var src := _src()
	var body := _play_music_body(src)
	var re := RegEx.create_from_string('"(battle_[a-z_]+)"')
	var arms: Array = []
	for m in re.search_all(body):
		arms.append(m.get_string(1))
	assert_gt(arms.size(), 8, "CONTROL: found %d battle_* names in play_music — a low count means the parse broke" % arms.size())
	var li: int = src.find("PROCEDURAL_BATTLE_TRACKS")
	var lend: int = src.find("]", li)
	var listed: String = src.substr(li, lend - li)
	var missing: Array = []
	for a in arms:
		# only names routed to a procedural generator need the exemption
		var idx: int = body.find('"%s"' % a)
		var after: String = body.substr(idx, 220)
		if after.contains("_start_monster_music") and not listed.contains('"%s"' % a):
			missing.append(a)
	assert_eq(missing.size(), 0, "procedural themes NOT exempt from the world rewrite: %s" % str(missing))


func test_every_listed_name_actually_has_an_arm() -> void:
	# Direction 2. A stale name in the list exempts a track that has no generator, so it would
	# fall through to silence instead of the world track. Both arrows, so neither side can rot.
	var src := _src()
	var body := _play_music_body(src)
	var li: int = src.find("PROCEDURAL_BATTLE_TRACKS")
	var lend: int = src.find("]", li)
	var re := RegEx.create_from_string('"(battle_[a-z_]+)"')
	var stale: Array = []
	var listed_count := 0
	for m in re.search_all(src.substr(li, lend - li)):
		listed_count += 1
		if not body.contains('"%s"' % m.get_string(1)):
			stale.append(m.get_string(1))
	assert_gt(listed_count, 8, "CONTROL: parsed %d listed names" % listed_count)
	assert_eq(stale.size(), 0, "listed but no arm in play_music: %s" % str(stale))


func test_the_world_rewrite_is_actually_guarded() -> void:
	# The fix itself. Without the guard the rewrite is unconditional and every assertion above
	# still passes — the list would be correct and unused.
	var body := _play_music_body(_src())
	assert_true(body.contains("PROCEDURAL_BATTLE_TRACKS.has(track)"),
		"the world-battle rewrite must consult the exemption list, or the list is decorative")


func test_the_goblin_has_no_manifest_key_so_this_path_is_live() -> void:
	# Why the guard matters TODAY rather than in principle: with a manifest key the composed
	# track would win first and none of this would run. Delete this test when a goblin track ships.
	var f := FileAccess.open("res://data/music_manifest.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	var found := false
	var stack: Array = [d]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Dictionary:
			var nd: Dictionary = n
			if nd.has("battle_goblin"):
				found = true
				break
			for k in nd:
				stack.append(nd[k])
	assert_false(found, "a battle_goblin manifest key now exists — the composed track landed, retire this test")
