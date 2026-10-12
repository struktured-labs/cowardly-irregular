extends GutTest

## Authored village-introduction scenes reached no player: nothing dispatched them, so their lines were unreachable and their Theater rows could never unlock.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
## Bounds the beat walk below: a scene that cannot set its own flag would spin, and a hung test
## reads as infrastructure rather than as a red.
const STORY_WALK_CAP := 12

var _loop: Node
var _saved: Dictionary = {}


func before_each() -> void:
	_saved = GameState.game_constants.duplicate(true)
	_loop = load("res://src/GameLoop.gd").new()
	## Every intro's gate flag cleared, so each arm starts from a player who has never been there.
	for map_id in _intros():
		GameState.game_constants.erase("cutscene_flag_%s_complete" % str(_intros()[map_id]))


func after_each() -> void:
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
	var code: String = GdSource.code_of("res://src/GameLoop.gd")
	assert_true(code.contains("func _get_pending_story_cutscene"), "CONTROL: GameLoop code must survive comment-stripping")
	var fn_at: int = code.find("func _get_pending_story_cutscene")
	var intro_at: int = code.find("for vid in _VILLAGE_INTROS", fn_at)
	var prologue_at: int = code.find("\"world1_prologue\"", fn_at)
	var chapter_at: int = code.find("\"world1_chapter1\"", fn_at)
	assert_gt(intro_at, -1, "the intro loop must live inside the pending-cutscene gate")
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


func test_an_intro_never_takes_a_chained_entry() -> void:
	## A story beat finishing in a village must not hand the entry straight to flavour.
	var code: String = GdSource.code_of("res://src/GameLoop.gd")
	var loop_at: int = code.find("for vid in _VILLAGE_INTROS")
	assert_gt(loop_at, -1, "CONTROL: the intro loop must exist")
	var before: String = code.substr(max(0, loop_at - 220), 220)
	assert_true(before.contains("not _chaining_story_cutscene"),
		"the intro loop must refuse to fire as a chain target, or an intro stacks on a story beat")


func test_a_new_game_cannot_land_on_a_wired_village() -> void:
	## New Game sets the map id before the opening cutscenes; if that id were ever a village key,
	## an intro would stack onto the opening and onto the web smoke's fresh-game path.
	var code: String = GdSource.code_of("res://src/GameLoop.gd")
	var at: int = code.find("func _on_title_new_game")
	assert_gt(at, -1, "CONTROL: the new-game entry point must exist")
	var body: String = code.substr(at, 2000)
	var set_at: int = body.find("_set_current_map_id(")
	assert_gt(set_at, -1, "CONTROL: New Game must set a map id")
	var landed: String = body.substr(set_at, 60)
	for vid in _intros():
		assert_false(landed.contains("\"%s\"" % str(vid)),
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
