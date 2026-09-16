extends GutTest

## The Elder Theron loop: a gate returns an id, the id is missing from _CUTSCENE_COMPLETION_FLAGS, so the flag never closes and the scene replays forever. Runtime protection is a push_warning nobody reads.

const GAMELOOP := "res://src/GameLoop.gd"
const CUTSCENE_DIR := "res://data/cutscenes"


func _consts() -> Dictionary:
	var s: GDScript = load(GAMELOOP)
	assert_not_null(s, "GameLoop.gd must load")
	return s.get_script_constant_map() if s else {}


func _flag_map() -> Dictionary:
	var c := _consts()
	assert_true(c.has("_CUTSCENE_COMPLETION_FLAGS"), "the completion-flag map must exist as a const")
	return c.get("_CUTSCENE_COMPLETION_FLAGS", {})


## Ids returned as literals by the story gate, read from source — the form no const exposes.
func _literal_gate_ids() -> Array:
	var src := FileAccess.get_file_as_string(GAMELOOP)
	var i := src.find("func _get_pending_story_cutscene")
	assert_gt(i, -1, "the story gate must exist")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 4000)
	var out: Array = []
	var re := RegEx.new()
	re.compile('return "(?<id>[a-z0-9_]+)"')
	for m in re.search_all(body):
		var id := m.get_string("id")
		if not out.has(id):
			out.append(id)
	return out


## Every id the story gate can return must be able to close its own gate.
func test_every_literal_gate_id_has_a_completion_flag() -> void:
	var ids := _literal_gate_ids()
	assert_gt(ids.size(), 20, "the parser must find the gate's returns; %d reads like a broken regex" % ids.size())
	assert_true(ids.has("world1_chapter1"), "CONTROL: a known gate id must be found, else this scans nothing")
	var flags := _flag_map()
	var unmapped: Array = []
	for id in ids:
		if not flags.has(id):
			unmapped.append(id)
	assert_eq(unmapped.size(), 0,
		"these ids are returned by the story gate but absent from _CUTSCENE_COMPLETION_FLAGS, so their " +
		"flag is never written and the scene replays on every gate check: " + str(unmapped))


## The fragment loop reads a DERIVED flag name, so being in the map is not enough — it must match.
func test_every_fragment_gate_flag_matches_the_name_the_loop_reads() -> void:
	var c := _consts()
	assert_true(c.has("_FRAGMENT_GATES"), "the fragment gates must exist as a const")
	var gates: Dictionary = c.get("_FRAGMENT_GATES", {})
	assert_gt(gates.size(), 0, "there must be fragment gates, else this test is vacuous")
	var flags := _flag_map()
	var wrong: Array = []
	for fid in gates:
		var want: String = "cutscene_flag_%s_complete" % fid
		if str(flags.get(fid, "")) != want:
			wrong.append("%s -> %s (loop reads %s)" % [fid, str(flags.get(fid, "<absent>")), want])
	assert_eq(wrong.size(), 0,
		"the fragment loop checks a derived flag name; a mapped value that differs writes one flag " +
		"and reads another, which loops exactly as an absent entry does: " + str(wrong))


## A gate that fires for a scene with no file leaves the player with nothing (the Warren case).
func test_every_gate_reachable_scene_has_a_file() -> void:
	var ids := _literal_gate_ids()
	for fid in _consts().get("_FRAGMENT_GATES", {}):
		if not ids.has(fid):
			ids.append(fid)
	var missing: Array = []
	for id in ids:
		if not FileAccess.file_exists("%s/%s.json" % [CUTSCENE_DIR, id]):
			missing.append(id)
	assert_eq(missing.size(), 0,
		"these ids are reachable by a gate but have no cutscene file, so the gate fires and nothing plays: " + str(missing))


## CONTROL: the file check must be able to fail, or the assert above is free.
func test_the_file_check_reports_a_fabricated_id_as_missing() -> void:
	assert_false(FileAccess.file_exists("%s/zzz_not_a_real_cutscene.json" % CUTSCENE_DIR),
		"a fabricated id must read as missing — if this exists the detector proves nothing")
	assert_true(FileAccess.file_exists("%s/world1_chapter1.json" % CUTSCENE_DIR),
		"and a known scene must read as present")
