extends GutTest

## BAL_FROM_SAVE rebuilds his party from a save, so the harness must refuse his live profile and read only a copy.

const HARNESS := "res://tools/balance_harness.gd"
const HIS_LIVE_SAVE := "/home/struktured/.local/share/godot/app_userdata/Cowardly Irregular/saves/save_00.json"

var _h: GDScript


func before_all() -> void:
	_h = load(HARNESS)


func _refuse(path: String, user_dir: String) -> String:
	return str(_h.call("save_path_refusal", path, user_dir))


func test_the_refusal_exists_on_the_harness() -> void:
	## THE FLOOR: every arm below calls through a helper whose default "" reads as ACCEPT, so a renamed method would pass them.
	var names: Array = []
	for m in _h.get_script_method_list():
		names.append(str(m.get("name", "")))
	assert_true(names.has("save_path_refusal"), "balance_harness.gd has no save_path_refusal -- the copy-only rule is gone")


func test_his_live_profile_is_refused() -> void:
	assert_ne(_refuse(HIS_LIVE_SAVE, "/srv/sandbox/xdg/godot/app_userdata/Cowardly Irregular"), "",
		"his real save was accepted as BAL_FROM_SAVE input; the harness must only ever read a copy")
	assert_ne(_refuse(HIS_LIVE_SAVE, ""), "", "and it must be refused even when the run's own user dir is unknown")


func test_user_scheme_is_refused() -> void:
	assert_ne(_refuse("user://saves/save_00.json", ""), "", "a user:// path is the run's live profile, never a copy")


func test_a_path_under_this_runs_user_dir_is_refused() -> void:
	assert_ne(_refuse("/srv/run/userdata/saves/save_00.json", "/srv/run/userdata"), "",
		"a save under the run's own user dir is a profile, not a copy")


func test_a_sibling_of_the_user_dir_is_not_refused_by_prefix() -> void:
	## Prefix with the slash, so /srv/run/userdata2 is not mistaken for /srv/run/userdata.
	assert_eq(_refuse("/srv/run/userdata2/save_00.json", "/srv/run/userdata"), "", "a sibling directory is not inside the user dir")


func test_an_empty_path_is_refused() -> void:
	assert_ne(_refuse("", ""), "", "an empty path must be named, not read")


func test_a_copy_is_accepted() -> void:
	## THE CONTROL: without it every refusal arm passes on a function that refuses everything.
	assert_eq(_refuse("res://tmp/savecopy/save_00.json", "/srv/run/userdata"), "", "a res:// copy must be accepted")
	assert_eq(_refuse("/home/struktured/projects/x/tmp/savecopy/save_00.json", "/srv/run/userdata"), "",
		"an absolute copy outside every profile must be accepted")


func test_the_refusal_runs_before_the_save_is_read() -> void:
	var src := FileAccess.get_file_as_string(HARNESS)
	var start := src.find("func _build_party_from_save(")
	assert_gt(start, -1, "FIXTURE: _build_party_from_save is gone from the harness")
	var body := src.substr(start, src.find("\nfunc ", start + 1) - start)
	var guard := body.find("save_path_refusal(")
	var read := body.find("get_file_as_string(")
	assert_gt(guard, -1, "_build_party_from_save never calls save_path_refusal")
	assert_gt(read, -1, "FIXTURE: _build_party_from_save no longer reads the save")
	assert_lt(guard, read, "the save is read before the refusal runs, so his live file could be opened")
