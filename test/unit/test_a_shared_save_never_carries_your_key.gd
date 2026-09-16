extends GutTest

## A BYOK api key is a per-machine secret. Saves are not per-machine — players
## share them, and this project's own sharing pillar trains them to.
##
## The split is already correct: the key rides `user://settings.json`, and
## GameState's save payload never mentions it. Nothing pinned that. The existing
## BYOK guards cover the panel and the log (`test_byok_config_panel`,
## `test_the_byok_log_never_carries_the_key`); the save was the third surface and
## the only one whose leak travels to another person.
##
## This scans the SERIALISED payload for the secret's value rather than reading the
## source, so it sees the key however it arrives — a new field, a blanket property
## dump, a nested dictionary someone adds later.

const SENTINEL := "sk-test-DO-NOT-SHIP-8b41f0e2c7"

var _gs: Node = null
var _orig_key: String = ""
var _had_key: bool = false


func before_each() -> void:
	_gs = get_tree().root.get_node_or_null("GameState")
	assert_not_null(_gs, "CONTROL: GameState autoload must be reachable")
	_had_key = "llm_custom_api_key" in _gs
	if _had_key:
		_orig_key = str(_gs.llm_custom_api_key)
		_gs.llm_custom_api_key = SENTINEL


func after_each() -> void:
	if _gs != null and _had_key:
		_gs.llm_custom_api_key = _orig_key


## Every string anywhere in the payload, however deeply nested.
func _all_strings(v: Variant, out: Array) -> void:
	match typeof(v):
		TYPE_STRING:
			out.append(v)
		TYPE_DICTIONARY:
			for k in (v as Dictionary):
				out.append(str(k))
				_all_strings((v as Dictionary)[k], out)
		TYPE_ARRAY:
			for item in (v as Array):
				_all_strings(item, out)


func test_the_save_payload_does_not_contain_the_key() -> void:
	assert_true(_had_key, "CONTROL: GameState must carry llm_custom_api_key, or this measures nothing")
	assert_eq(str(_gs.llm_custom_api_key), SENTINEL, "CONTROL: the sentinel must be set for this test")
	var payload: Dictionary = _gs.to_dict()
	assert_gt(payload.size(), 0, "CONTROL: the save payload must not be empty")
	var strings: Array = []
	_all_strings(payload, strings)
	var leaked: Array = []
	for s in strings:
		if str(s).find(SENTINEL) != -1:
			leaked.append(str(s))
	assert_eq(leaked, [],
		"a save is shareable — the api key must never be inside it; found %d occurrence(s)" % leaked.size())


func test_the_scan_would_actually_find_it() -> void:
	## Anti-vacuity: the scan above proves nothing unless it can see a string this
	## deep. Plant the sentinel at the same depth a real leak would sit at.
	var planted: Dictionary = {"a": {"b": [{"c": SENTINEL}]}}
	var strings: Array = []
	_all_strings(planted, strings)
	var found: bool = false
	for s in strings:
		if str(s).find(SENTINEL) != -1:
			found = true
	assert_true(found, "the payload scan must be able to see a nested value, or the guard is vacuous")


func test_the_key_is_not_serialised_under_any_name() -> void:
	## Value-based, so renaming the field does not evade it. This is the arm that
	## survives a refactor: the secret's CONTENT is what must not travel.
	var json: String = JSON.stringify(_gs.to_dict())
	assert_eq(json.find(SENTINEL), -1,
		"the serialised save must not contain the key under any field name")


func test_settings_is_where_it_belongs() -> void:
	## The counterpart: the key IS meant to persist per-machine. If SaveSystem stopped
	## writing it to settings, BYOK would silently forget the key every launch — and a
	## test that only checks the save would call that a pass.
	var src: String = FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	assert_false(src.is_empty(), "CONTROL: SaveSystem must be readable")
	var at: int = src.find("func save_settings")
	assert_gt(at, -1, "CONTROL: save_settings must exist")
	var end: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, (end - at) if end > at else -1)
	assert_true(body.find("llm_custom_api_key") != -1,
		"settings.json is the key's home — it must still be written there")
