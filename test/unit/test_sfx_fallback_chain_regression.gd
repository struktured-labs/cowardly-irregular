extends GutTest

## A manifest entry whose `file` is missing on disk used to push a warning
## on every play() call (menu_error fires from inn-deny / shop-deny /
## item-deny / overworld-menu paths — easily 5+ times per minute of play).
## The fallback_to field lets the manifest declare "if my file is missing,
## route to this other key" — silencing the warning AND giving the user a
## coherent SFX instead of nothing.

const SFX_MANIFEST := "res://data/sfx_manifest.json"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"


func _manifest() -> Dictionary:
	var f := FileAccess.open(SFX_MANIFEST, FileAccess.READ)
	assert_not_null(f, "sfx_manifest.json must be readable")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary and (parsed as Dictionary).has("sfx"),
		"sfx_manifest.json must have a top-level 'sfx' Dictionary")
	return (parsed as Dictionary)["sfx"]


func _source() -> String:
	return FileAccess.get_file_as_string(SOUND_MANAGER)


func test_known_missing_sfx_have_fallback_or_exist() -> void:
	# Every manifest entry either has a real file on disk OR declares a
	# fallback_to that exists in the manifest. Anything else WILL warn.
	var sfx := _manifest()
	for key in sfx.keys():
		var entry: Dictionary = sfx[key]
		var path: String = str(entry.get("file", ""))
		if path == "":
			continue
		if not path.begins_with("res://"):
			path = "res://" + path
		if FileAccess.file_exists(path):
			continue
		var fallback: String = str(entry.get("fallback_to", ""))
		assert_ne(fallback, "", "%s has missing file %s — declare fallback_to" % [key, path])
		assert_true(sfx.has(fallback), "%s.fallback_to='%s' must exist in manifest" % [key, fallback])


func test_menu_error_falls_back_to_menu_cancel() -> void:
	var sfx := _manifest()
	assert_true(sfx.has("menu_error"), "menu_error entry must exist")
	var entry: Dictionary = sfx["menu_error"]
	assert_eq(str(entry.get("fallback_to", "")), "menu_cancel",
		"menu_error must fall back to menu_cancel until a real menu_error.ogg lands")


func test_sound_manager_honors_fallback_to() -> void:
	var src := _source()
	assert_ne(src, "", "SoundManager.gd must be readable")
	var idx := src.find("func _try_play_sfx_from_manifest")
	assert_gt(idx, -1, "_try_play_sfx_from_manifest must exist")
	var rest := src.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("fallback_to"),
		"_try_play_sfx_from_manifest must read the 'fallback_to' field when load() returns null")
	# Must guard against self-loops — fallback_to: <self> would recurse forever.
	assert_true(body.contains("fallback_key != sound_key") or body.contains("fallback_key != resolved_key"),
		"fallback chain must skip self-references to avoid infinite recursion")
