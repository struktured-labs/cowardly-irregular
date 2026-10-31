extends GutTest

## Authored village-introduction scenes reached no player: nothing dispatched them, so their lines were unreachable and their Theater rows could never unlock.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
## Bounds the beat walk below: a scene that cannot set its own flag would spin, and a hung test
## reads as infrastructure rather than as a red.
const STORY_WALK_CAP := 12
## Named once so the arm and the teardown cannot drift apart, and named for THIS file:
## two guards sharing one probe path is shared mutable state keyed by nothing.
const PROBE := "user://village_intro_strip_probe.gd"

var _loop: Node
var _saved: Dictionary = {}
## A retired intro mirrors its flag into story_flags too, so that store is restored as well or it leaks into later files.
var _saved_story: Dictionary = {}


func before_each() -> void:
	_saved = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	_loop = load("res://src/GameLoop.gd").new()
	## Every intro's gate flag cleared, so each arm starts from a player who has never been there.
	for map_id in _intros():
		GameState.game_constants.erase("cutscene_flag_%s_complete" % str(_intros()[map_id]))


func after_each() -> void:
	## Erased FIRST: free() below can abort this function, which would strand the plant.
	if FileAccess.file_exists(PROBE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROBE))
	GameState.story_flags = _saved_story
	if is_instance_valid(_loop):
		_loop.free()
	GameState.game_constants = _saved


## The real gate, driven exactly as GameLoop drives it on a map entry.
func _pending_on(map_id: String) -> String:
	_loop._current_map_id = map_id
	return _loop._get_pending_story_cutscene()


func _intros() -> Dictionary:
	return load("res://src/GameLoop.gd").get_script_constant_map()["_VILLAGE_INTROS"]


func _completion_flags() -> Dictionary:
	return load("res://src/GameLoop.gd").get_script_constant_map()["_CUTSCENE_COMPLETION_FLAGS"]


## The flag the scene's own set_flag step writes, which is what must stop it re-firing.
func _authored_flag(cid: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % cid))
	if not (parsed is Dictionary):
		return ""
	for step in (parsed as Dictionary).get("steps", []):
		if step is Dictionary and str((step as Dictionary).get("type", "")) == "set_flag":
			return "cutscene_flag_%s" % str((step as Dictionary).get("flag", ""))
	return ""


func test_every_wired_intro_names_a_scene_on_disk() -> void:
	var intros: Dictionary = _intros()
	assert_gt(intros.size(), 4, "CONTROL: the village intro table must be populated, saw %d" % intros.size())
	var missing: Array = []
	for map_id in intros:
		if not FileAccess.file_exists("res://data/cutscenes/%s.json" % str(intros[map_id])):
			missing.append("%s -> %s" % [map_id, intros[map_id]])
	assert_eq(missing, [], "a village intro names a scene that is not on disk: %s" % [missing])


func test_each_intro_can_stop_itself_re_firing() -> void:
	## The gate reads cutscene_flag_<id>_complete; the scene writes its own set_flag. If those two
	## disagree the scene replays on every entry to that village — the Elder Theron loop.
	var mismatched: Array = []
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		var gate_flag: String = "cutscene_flag_%s_complete" % cid
		var authored: String = _authored_flag(cid)
		assert_ne(authored, "", "CONTROL: %s must author a set_flag step" % cid)
		if authored != gate_flag:
			mismatched.append("%s writes %s, the gate reads %s" % [cid, authored, gate_flag])
	assert_eq(mismatched, [], "an intro that cannot set its own gate flag replays forever: %s" % [mismatched])


func test_each_intro_is_in_the_completion_flag_map() -> void:
	var absent: Array = []
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		if not _completion_flags().has(cid):
			absent.append(cid)
	assert_eq(absent, [], "a scene the engine fires must carry a completion flag or it loops: %s" % [absent])


func test_an_intro_cannot_pre_empt_a_story_beat() -> void:
	## Ordering is the whole safety property: every story gate returns before the intro loop, so
	## an intro can never take an entry a chapter beat wanted.
	var code: String = _gameloop_code()
	assert_true(code.contains("func _get_pending_story_cutscene"), "CONTROL: GameLoop code must survive comment-stripping")
	var fn_at: int = code.find("func _get_pending_story_cutscene")
	var intro_at: int = code.find("for vid in _VILLAGE_INTROS", fn_at)
	var prologue_at: int = code.find("\"world1_prologue\"", fn_at)
	var chapter_at: int = code.find("\"world1_chapter1\"", fn_at)
	## ⛔ EVERY OFFSET NEEDS ITS OWN FLOOR, AND THIS ARM SHIPPED WITHOUT TWO OF THEM. `find` returns
	## -1 when the anchor is gone, and -1 compares as EARLIER THAN EVERYTHING — so `intro_at >
	## prologue_at` is satisfied by a prologue anchor that no longer exists. MEASURED: renaming every
	## `"world1_prologue"` inside the gate left this file 15 passing / 0 failing, with the ordering
	## claim asserting nothing. A sentinel read as data, which is the shape four lanes spent tonight on.
	assert_gt(intro_at, -1, "the intro loop must live inside the pending-cutscene gate")
	assert_gt(prologue_at, -1, "the prologue gate is no longer found inside the gate, so the ordering claim below would compare against -1 and pass for free")
	assert_gt(chapter_at, -1, "the chapter-1 gate is no longer found inside the gate, so the ordering claim below would compare against -1 and pass for free")
	assert_gt(intro_at, prologue_at, "the prologue gate must be reached before any village intro")
	assert_gt(intro_at, chapter_at, "the chapter-1 gate must be reached before any village intro")


func test_no_two_villages_claim_the_same_scene() -> void:
	var seen: Dictionary = {}
	var dupes: Array = []
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		if seen.has(cid):
			dupes.append("%s is claimed by %s and %s" % [cid, seen[cid], map_id])
		seen[cid] = map_id
	assert_eq(dupes, [], "two maps firing one scene means the second can never play it: %s" % [dupes])


## The ONE accessor for GameLoop's code: every arm below reads through this, so swapping the strip is
## visible to an arm rather than only to a helper nobody asserts about.
func _code_of(path: String) -> String:
	return GdSource.code_of(path)


func _gameloop_code() -> String:
	return _code_of("res://src/GameLoop.gd")


## The body of one function: anchor to the next `func ` rather than a character count.
##
## ⛔ A FIXED-WIDTH WINDOW REDS ON AN UNRELATED INSERTION AND NAMES THIS FILE. @cowir-music measured
## it on their own branch 2026-10-12: a hold added to the TOP of show_victory_results pushed the
## subject of a 1200-char window from +607 to +1690, and the arm went red in a file whose subject
## nothing had touched. This file had two such windows (220 back from the intro loop, 2000 forward
## from _on_title_new_game). A function-bounded slice cannot drift: it grows with its function.
func _function_body(code: String, signature: String) -> String:
	var at: int = code.find(signature)
	if at < 0:
		return ""
	var end: int = code.find("\nfunc ", at + 1)
	return code.substr(at, (end - at) if end > at else -1)


## Walks the beats a map offers until the intro is what the gate returns; "" if it never is.
func _walk_to_intro(map_id: String, cid: String) -> bool:
	var seen: Array[String] = []
	for _step in STORY_WALK_CAP:
		var got: String = _pending_on(map_id)
		if got == cid:
			return true
		if got == "" or seen.has(got):
			return false
		seen.append(got)
		GameState.game_constants[_completion_flag_of(got)] = true
	return false


func test_an_intro_never_takes_a_chained_entry() -> void:
	## A story beat finishing in a village must not hand the entry straight to flavour.
	##
	## ⛔ THIS WAS A SOURCE-ORDER ASSERT AND IT HAD NO TEETH. It searched the gate's body for
	## `not _chaining_story_cutscene` before the loop — and that function contains SEVEN of them
	## (four spotlight gates, a comment, the loop's own, the declaration). Deleting the loop's guard
	## left the arm satisfied by a spotlight gate's: mutant M3 stayed GREEN with the refusal gone.
	## Behaviour instead — set the flag the chain sets and ask the gate.
	##
	## ⛔ AND THE CORPUS IS ASSERTED INSIDE THE ARM, which it was not when this shipped. Every village
	## whose walk fails is `continue`d, so if cross-test state stopped the walk reaching ANY intro the
	## arm passed having tested NOTHING. MEASURED by making _walk_to_intro return false: 13 passing,
	## 1 failing — and the one that spoke was the CONTROL in the next function, not this arm.
	## A neighbouring control is weaker than an in-arm count: it is a separate test that a reasonable
	## cleanup can prune as "duplicate", and this arm would then go silent with nothing saying so.
	## (@cowir-overworld, 2026-10-12: a behavioural arm is loud only about a corpus that could have
	## contained the defect — theirs covered 1 castle floor of 4, chosen by whatever ran before it.)
	var blocked_ok: Array[String] = []
	var reached: Array[String] = []
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		if not _walk_to_intro(str(map_id), cid):
			continue
		reached.append(str(map_id))
		_loop._chaining_story_cutscene = true
		var got: String = _pending_on(str(map_id))
		_loop._chaining_story_cutscene = false
		if got == cid:
			blocked_ok.append(str(map_id))
	assert_eq(reached.size(), _intros().size(),
		"this arm only speaks about villages whose walk reached the intro, and it reached %d of %d — the rest were skipped, so a pass here would assert nothing about them: %s" % [reached.size(), _intros().size(), reached])
	assert_eq(blocked_ok, ([] as Array[String]),
		"an intro fires as a chain target on these maps, so it stacks onto the story beat that just ended: %s" % [blocked_ok])


func test_control_the_chain_flag_is_the_only_thing_that_changed() -> void:
	## Pairs with the arm above: without the flag the intro IS returned, so a green there means the
	## refusal works and not that the walk failed to reach an intro.
	var reached := 0
	for map_id in _intros():
		if _walk_to_intro(str(map_id), str(_intros()[map_id])):
			reached += 1
	assert_eq(reached, _intros().size(),
		"CONTROL: the walk must reach every intro with the chain flag down, reached %d of %d" % [reached, _intros().size()])


func test_a_new_game_cannot_land_on_a_wired_village() -> void:
	## New Game sets the map id before the opening cutscenes; if that id were ever a village key,
	## an intro would stack onto the opening and onto the web smoke's fresh-game path.
	var code: String = _gameloop_code()
	var body: String = _function_body(code, "func _on_title_new_game")
	assert_ne(body, "", "CONTROL: the new-game entry point must exist")
	## EVERY map id New Game sets, not just the first — a second call below the first was outside the
	## old 2000-char window entirely, and the arm would have had nothing to say about it.
	var rx := RegEx.create_from_string('_set_current_map_id\\(\\s*"([a-z0-9_]+)"')
	var landed: Array[String] = []
	for m in rx.search_all(body):
		landed.append(m.get_string(1))
	assert_gt(landed.size(), 0, "CONTROL: New Game must set a map id")
	for vid in _intros():
		assert_false(landed.has(str(vid)),
			"New Game lands on %s, which is wired to an intro — it would stack on the opening" % [vid])


## The village arms its OWN bed on entry (village_harmonia, village_maple_heights...). An intro that
## plays a generic world bed scores the player's first impression with the wrong music and only hands
## the village its theme back when the scene ends.
func test_an_intro_does_not_score_itself_with_the_generic_bed() -> void:
	var wrong: Array = []
	var checked := 0
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % cid))
		assert_true(parsed is Dictionary, "CONTROL: %s must parse" % cid)
		var data: Dictionary = parsed
		checked += 1
		var beds: Array = []
		for step in data.get("steps", []):
			if step is Dictionary and str((step as Dictionary).get("type", "")) == "play_music":
				beds.append(str((step as Dictionary).get("track", "")))
		var village: String = str(map_id).trim_suffix("_village")
		for bed in beds:
			if bed != "village_%s" % village:
				wrong.append("%s plays %s" % [cid, bed])
		if beds.is_empty() and not bool(data.get("keep_music", false)):
			wrong.append("%s names no bed and does not keep_music, so it plays to dead air" % cid)
	assert_gt(checked, 4, "CONTROL: every wired intro must be read, saw %d" % checked)
	assert_eq(wrong, [], "an intro must keep the village's bed or name that village's own theme: %s" % [wrong])


## ⛔ MEASURED, not stylistic: an overworld is where the world-TRANSITION scenes queue, and
## test_world_transition_scenes_wired_regression requires NOTHING pending on suburban_overworld
## both before and after W2 completes. Keying world2_oak_street_npcs there red it twice on the fold
## — on a surface this file cannot see, because it reads the intro table and never the transitions.
func test_no_intro_is_keyed_to_an_overworld() -> void:
	var wrong: Array = []
	for map_id in _intros():
		if str(map_id) == "overworld" or str(map_id).ends_with("_overworld"):
			wrong.append("%s -> %s" % [map_id, _intros()[map_id]])
	assert_eq(wrong, [], "an intro on an overworld competes with that world's transition scenes: %s" % [wrong])


## The other half of the same ruling: a scene nothing dispatches must not keep a completion flag,
## because _epilogue_done_or_unwired reads absence as "unwired" and a stale entry would hold a chain
## open for a flag that can never be set.
func test_an_unwired_intro_keeps_no_completion_flag() -> void:
	var wired: Array = _intros().values().map(func(c): return str(c))
	var flags: Dictionary = _completion_flags()
	var stale: Array = []
	for cid in flags:
		if str(cid).ends_with("_npcs") and not (str(cid) in wired):
			stale.append(str(cid))
	assert_eq(stale, [], "a village intro nothing fires still carries a completion flag: %s" % [stale])


# ── BEHAVIOUR, not shape: the arms above prove the table is well-formed, which is not the same ────

## The flag that stops a scene being offered again: the engine's own map where it has one.
func _completion_flag_of(cid: String) -> String:
	var flags: Dictionary = _completion_flags()
	return str(flags[cid]) if flags.has(cid) else "cutscene_flag_%s_complete" % cid


func test_a_village_eventually_introduces_itself() -> void:
	## ⛔ THE ARM THIS FILE WAS MISSING, AND ITS FIRST VERSION WAS WRONG IN A WAY WORTH KEEPING IN
	## THE HEADER. Everything above reads the table, the flags and the source ORDER; none of it asks
	## the gate what it RETURNS. A table can be perfect and the scene still unreachable — which is
	## exactly how these scenes sat unplayed for months. But asserting the intro is pending on the
	## FIRST entry is false by design: the prologue claims harmonia_village and story beats must win,
	## which test_an_intro_cannot_pre_empt_a_story_beat requires. So this walks the player's real
	## path — play whatever the gate offers, let it set its flag, enter again — and asserts the intro
	## is reached. Bounded, because a scene that cannot set its own flag would otherwise spin here.
	var unreachable: Array[String] = []
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		var seen: Array[String] = []
		var reached := false
		for _step in STORY_WALK_CAP:
			var got: String = _pending_on(str(map_id))
			if got == cid:
				reached = true
				break
			if got == "" or seen.has(got):
				break
			seen.append(got)
			GameState.game_constants[_completion_flag_of(got)] = true
		if not reached:
			unreachable.append("%s: played %s and never reached %s" % [map_id, seen, cid])
	assert_eq(unreachable, ([] as Array[String]),
		"a player who plays every beat these maps offer never gets the introduction: %s" % [unreachable])


func test_an_intro_does_not_come_back_after_it_has_played() -> void:
	## The Elder Theron loop: a scene whose gate flag it cannot set replays on every entry.
	var looping: Array[String] = []
	for map_id in _intros():
		var cid: String = str(_intros()[map_id])
		GameState.game_constants["cutscene_flag_%s_complete" % cid] = true
		if _pending_on(str(map_id)) == cid:
			looping.append(cid)
	assert_eq(looping, ([] as Array[String]), "these intros stay pending after completing: %s" % [looping])


func test_no_intro_is_pending_on_a_map_it_was_not_written_for() -> void:
	## The Oak Street failure in behavioural form: an intro answering on the wrong map takes an entry
	## some other scene wanted. Overworlds are the ones that matter — transitions queue there.
	var leaked: Array[String] = []
	for map_id in ["overworld", "suburban_overworld", "steampunk_overworld", "industrial_overworld",
			"futuristic_overworld", "abstract_overworld", "whispering_cave", "castle_harmonia"]:
		var got: String = _pending_on(map_id)
		if got != "" and (got in _intros().values()):
			leaked.append("%s -> %s" % [map_id, got])
	assert_eq(leaked, ([] as Array[String]), "a village intro is pending on a map that is not its village: %s" % [leaked])


## ⛔ THE STRIP, PINNED IN BOTH DIRECTIONS AND AT THE CALLER. Measured on a sibling guard the same
## hour: swapping the accessor to a raw read left that file 7 passing / 0 failing. Three lanes hit the
## identical hole tonight and in every case the control called GdSource DIRECTLY, certifying the
## helper while saying nothing about what the arm used. Both directions, because either assertion
## alone is satisfied by a defect in the other: "real code survives" passes a strip that never
## happened, "the comment is gone" passes a strip that ate the file.
func test_the_accessor_these_arms_use_strips_prose_both_ways() -> void:
	var probe := PROBE
	var f := FileAccess.open(probe, FileAccess.WRITE)
	assert_not_null(f, "CONTROL: the probe file must be writable")
	f.store_string("\n".join([
		"extends Node",
		"## prose naming for vid in _VILLAGE_INTROS and not _chaining_story_cutscene",
		"func zz_real_site() -> void:",
		"\tpass",
		"\"\"\"",
		"a docstring naming zz_doc_only_site",
		"\"\"\"",
	]))
	f.close()
	var code: String = _code_of(probe)
	assert_true(code.contains("zz_real_site"),
		"real code did not survive the strip, so every source arm in this file is vacuous")
	assert_false(code.contains("for vid in _VILLAGE_INTROS"),
		"a `#` comment reached the code half — the ordering and chain-refusal arms read prose as code")
	assert_false(code.contains("zz_doc_only_site"),
		"a \"\"\" docstring reached the code half; strip_comments is a LINE pass, split() drops the region")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe))
	## ⛔ A FOURTH ASSERTION, AND IT CAME FROM A MUTANT WALKING PAST THE THREE ABOVE. An accessor that
	## keeps only the lines these arms NAME satisfies every one of them — real site present, no
	## comment, no docstring — and left this file 15 passing / 0 failing. @cowir-autogrind predicted
	## it and @cowir-deploy named why a `> 0` floor is gameable: the mutant can read your control.
	## A PROPORTIONAL floor cannot be gamed that way. Measured on GameLoop.gd 2026-10-12:
	## raw 393,035 chars -> code 247,795 = 0.630, with 119 `\"\"\"` lines. The bar is 0.40, far below
	## the real ratio and far above anything a keep-the-named-lines strip can produce (~0.001).
	var raw_len: int = FileAccess.get_file_as_string("res://src/GameLoop.gd").length()
	var code_len: int = _gameloop_code().length()
	assert_gt(raw_len, 100000, "CONTROL: GameLoop.gd must be read at all, got %d chars" % raw_len)
	assert_gt(float(code_len) / float(maxi(raw_len, 1)), 0.40,
		"the strip left only %d of %d chars (%.3f): it is keeping the named lines and discarding the file, so every source arm here reads a corpus chosen by its own assertions" % [code_len, raw_len, float(code_len) / float(maxi(raw_len, 1))])


## Plays whatever the gate offers on map_id, finishing each scene, and returns every id it offered (bounded).
func _offered_on(map_id: String) -> Array[String]:
	var offered: Array[String] = []
	for _step in STORY_WALK_CAP:
		var got: String = _pending_on(map_id)
		if got == "" or offered.has(got):
			break
		offered.append(got)
		GameState.game_constants[_completion_flag_of(got)] = true
	return offered


func test_an_intro_that_has_lost_its_moment_retires_instead_of_playing() -> void:
	## struktured 2026-10-30: "some dialogue replayed all of a sudden, after leaving mystic remedies". His save
	## had finished the prologue, chapter1 and the Cleric spotlight, which between them put 3 of Harmonia's 5
	## locals on screen, and the intro then played as if they were strangers. The gate must retire it instead.
	var intro := "world1_harmonia_npcs"
	for done in ["world1_prologue", "world1_chapter1", "world1_spotlight_cleric_ch1"]:
		assert_true(_completion_flags().has(done), "CONTROL: %s must be in the completion map, or this arm is not his save" % done)
		GameState.game_constants[_completion_flag_of(done)] = true
	assert_false(bool(GameState.game_constants.get(_completion_flag_of(intro), false)), "CONTROL: the intro must start unplayed")
	var offered := _offered_on("harmonia_village")
	assert_false(offered.has(intro), "an intro whose locals were already met was offered anyway: %s" % [offered])
	assert_true(bool(GameState.game_constants.get(_completion_flag_of(intro), false)),
		"a retired intro must close its own gate, or it waits to fire on some later entry instead")


func test_an_intro_among_strangers_still_plays() -> void:
	## POSITIVE CONTROL. The rule must not swallow every intro that arrives after a chapter: Maple Heights'
	## chapter1 meets none of the intro's four locals, and Harmonia right after the prologue has met nobody.
	GameState.game_constants[_completion_flag_of("world2_prologue")] = true
	GameState.game_constants[_completion_flag_of("world2_chapter1")] = true
	assert_true(_offered_on("maple_heights_village").has("world2_maple_heights_npcs"),
		"Maple Heights' intro must still play after its chapter1, whose cast it does not share")
	GameState.game_constants = _saved.duplicate(true)
	for map_id in _intros():
		GameState.game_constants.erase(_completion_flag_of(str(_intros()[map_id])))
	GameState.game_constants[_completion_flag_of("world1_prologue")] = true
	assert_true(_offered_on("harmonia_village").has("world1_harmonia_npcs"),
		"Harmonia's intro must still play on an entry where nobody it introduces has spoken yet")


func test_party_members_never_count_as_already_met() -> void:
	## Every chapter has the party talking, so counting them would retire intros that introduce real strangers.
	## Maple Heights' intro and chapter1 share Fighter/Cleric/Mage lines and no local.
	var met: Vector2i = _loop._intro_locals_already_met("world2_maple_heights_npcs",
		{_completion_flag_of("world2_chapter1"): true})
	assert_gt(met.y, 0, "CONTROL: the intro must have locals at all, read %d" % met.y)
	assert_lt(met.y, _loop._scene_speakers("world2_maple_heights_npcs").size(),
		"CONTROL: the intro's own party lines must be excluded from its locals, so locals < speakers")
	assert_eq(met.x, 0, "a party member counted as an already-met local: %d of %d" % [met.x, met.y])


func test_most_means_more_than_half() -> void:
	assert_true(_loop._intro_has_lost_its_moment(Vector2i(3, 5)), "3 of 5 met is most: his Harmonia save")
	assert_false(_loop._intro_has_lost_its_moment(Vector2i(1, 2)), "half is not most: Brasston after its chapter1")
	assert_false(_loop._intro_has_lost_its_moment(Vector2i(1, 3)), "a minority is not most: Rivet Row after its chapter1")
	assert_false(_loop._intro_has_lost_its_moment(Vector2i(0, 0)), "an intro with no locals has no one to have met")
