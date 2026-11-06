extends GutTest

## Five fallbacks named a Confirm or Back key by hand ("X" for cancel, "Z" for confirm), and every one still named the
## keyboard layout from before 2026-09-29, when Confirm moved to X and Back to Z: the trusted-turn offer, the post-battle
## and victory prompts, a readable sign's close key and the help screen would each have named the OPPOSITE key. They
## now ask KeyLabel, which reads the binding off InputMap with no autoload, so a future remap cannot strand them.

const SRC_ROOT := "res://src"
const GUARDED := ["ui_accept", "ui_cancel"]


## The first key bound to `action`, read independently of KeyLabel so the comparison is not KeyLabel against itself.
func _first_key_from_inputmap(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var ke := ev as InputEventKey
			var kc: Key = ke.keycode if ke.keycode != 0 else ke.physical_keycode
			if kc != 0:
				return OS.get_keycode_string(kc)
	return ""


func test_the_floor_names_every_member_this_file_drives() -> void:
	for m in ["all_keys", "first_key"]:
		assert_true(KeyLabel.new().has_method(m), "KeyLabel.%s must exist" % m)
	assert_true(InputProfileManager.has_method("get_action_key_label"), "InputProfileManager.get_action_key_label must exist")


func test_a_fallback_names_the_key_actually_bound() -> void:
	for action in GUARDED:
		var bound := _first_key_from_inputmap(action)
		assert_ne(bound, "", "CONTROL: %s has a keyboard key in the shipped map" % action)
		assert_eq(KeyLabel.first_key(action, "?"), bound, "%s's fallback names the key bound to it" % action)
	assert_ne(KeyLabel.first_key("ui_accept", "?"), KeyLabel.first_key("ui_cancel", "?"),
		"CONTROL: Confirm and Back are different keys, so a swapped fallback could not pass the arm above")


func test_an_action_with_no_key_falls_back_to_its_meaning() -> void:
	assert_eq(KeyLabel.first_key("zz_no_such_action", "Back"), "Back", "no binding names the meaning, never a guessed letter")
	assert_eq(KeyLabel.all_keys("zz_no_such_action"), "—", "and lists nothing")


func test_the_profile_manager_reads_the_same_keys() -> void:
	var actions := InputMap.get_actions()
	assert_gt(actions.size(), 10, "PRECONDITION: the input map is loaded")
	for action in actions:
		assert_eq(InputProfileManager.get_action_key_label(action), KeyLabel.all_keys(action),
			"%s: the manager's key label is KeyLabel's (one implementation, not two)" % action)


## Derived over every src script: a function that names ui_accept or ui_cancel never returns a hand-written key letter.
func test_no_source_falls_back_to_a_hand_written_key() -> void:
	var rx := RegEx.create_from_string("(return|else)\\s+\"[A-Z]\"")
	var guarded := RegEx.create_from_string("\"ui_(accept|cancel)\"")
	assert_not_null(rx.search('\treturn tok if tok != "" else "X"'), "CONTROL: the scan matches the old fallback's shape")
	var files := _gd_files(SRC_ROOT)
	assert_gt(files.size(), 100, "PRECONDITION: the scan reached the source tree")
	var offenders: Array = []
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		for fn in _functions(src):
			if guarded.search(fn) != null and rx.search(fn) != null:
				offenders.append("%s: %s" % [path, fn.get_slice("\n", 0).strip_edges()])
	assert_eq(offenders, [], "a Confirm/Back fallback must ask KeyLabel, not name a letter: %s" % [offenders])


func _functions(src: String) -> Array:
	var out: Array = []
	var cur := ""
	for line in src.split("\n"):
		if line.begins_with("func ") or line.begins_with("static func "):
			out.append(cur)
			cur = ""
		cur += line + "\n"
	out.append(cur)
	return out


func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	for sub in d.get_directories():
		out.append_array(_gd_files(dir_path + "/" + sub))
	return out
