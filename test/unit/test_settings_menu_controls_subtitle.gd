extends GutTest

## tick 234: SettingsMenu's Controls action button now shows a
## LIVE subtitle of the current ui_accept / ui_cancel / ui_menu
## keybinds — "A:Z  B:X  Menu:Esc" — instead of the static
## "Remap gamepad buttons" text.
##
## Why: the previous subtitle hinted at gamepad-only intent
## (despite the menu supporting keyboard too) AND gave no
## actionable info. A player who wanted to remember "which key
## opens the menu" had to enter the submenu just to peek.
##
## The new subtitle reads live each menu rebuild so a custom
## binding configured via ControlsMenu shows up immediately on
## the next open. Falls back to the static text when
## InputProfileManager isn't reachable (test bootstrap, early
## init).

const SETTINGS_MENU := "res://src/ui/SettingsMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Helper exists ────────────────────────────────────────────────────

func test_helper_function_present() -> void:
	var src := _read(SETTINGS_MENU)
	assert_true(src.contains("func _get_controls_subtitle() -> String:"),
		"_get_controls_subtitle helper must exist")


func test_helper_reads_3_actions_live() -> void:
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _get_controls_subtitle")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("ipm.get_action_key_label(\"ui_accept\")"),
		"helper must read ui_accept binding")
	assert_true(body.contains("ipm.get_action_key_label(\"ui_cancel\")"),
		"helper must read ui_cancel binding")
	assert_true(body.contains("ipm.get_action_key_label(\"ui_menu\")"),
		"helper must read ui_menu binding")


func test_helper_uses_scene_tree_root_pattern() -> void:
	# Pin: autoload lookup via scene-tree root (Engine.has_singleton
	# lint enforces this for autoloads in Godot 4).
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _get_controls_subtitle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("get_node_or_null(\"/root/InputProfileManager\")"),
		"helper must use scene-tree-root autoload lookup")


func test_helper_falls_back_when_ipm_missing() -> void:
	# Pin: graceful fallback when InputProfileManager isn't reachable
	# (test bootstrap, early init, missing autoload).
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _get_controls_subtitle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return \"Remap gamepad buttons\""),
		"fallback must return the original static subtitle")


func test_helper_format_is_compact() -> void:
	# Pin: format reads as "A:<key>  B:<key>  Menu:<key>" — compact
	# enough to fit in the action button subtitle slot without wrapping.
	var src := _read(SETTINGS_MENU)
	var fn_idx: int = src.find("func _get_controls_subtitle")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("\"A:%s  B:%s  Menu:%s\""),
		"subtitle format must match the canonical 'A:%s  B:%s  Menu:%s' pattern")


# ── Wiring at the action-button add site ─────────────────────────────

func test_controls_button_uses_dynamic_subtitle() -> void:
	var src := _read(SETTINGS_MENU)
	# Find the Controls add_action call.
	assert_true(src.contains("add_action.call(\"Controls\", _get_controls_subtitle(), \"controls\")"),
		"Controls action button must use _get_controls_subtitle() for its subtitle")


func test_old_static_subtitle_gone_from_controls_site() -> void:
	# Negative pin: the pre-fix `"Remap gamepad buttons"` literal
	# must be gone from the Controls add_action call. (It still
	# lives in the fallback branch of the helper, which is fine.)
	var src := _read(SETTINGS_MENU)
	assert_false(src.contains("add_action.call(\"Controls\", \"Remap gamepad buttons\""),
		"pre-fix static-subtitle Controls call must be gone")


# ── Live runtime check ──────────────────────────────────────────────

func test_subtitle_is_non_empty_at_runtime() -> void:
	# Live check: when InputProfileManager IS reachable, the helper
	# returns a non-empty subtitle (even if a specific action returns
	# the "—" placeholder, the format still produces text).
	var cls = load(SETTINGS_MENU)
	var menu = cls.new()
	add_child_autofree(menu)
	# Calling the helper without going through the full SettingsMenu
	# build path — direct method access.
	var subtitle: String = menu._get_controls_subtitle()
	assert_gt(subtitle.length(), 0, "subtitle must be non-empty")


func test_subtitle_shape_at_runtime() -> void:
	# Pin: when IPM is reachable, the result follows the
	# "A:X  B:Y  Menu:Z" shape (or falls back to the static string).
	var cls = load(SETTINGS_MENU)
	var menu = cls.new()
	add_child_autofree(menu)
	var subtitle: String = menu._get_controls_subtitle()
	# Either fallback shape OR live shape.
	var is_fallback: bool = subtitle == "Remap gamepad buttons"
	var has_live_shape: bool = subtitle.begins_with("A:") and "B:" in subtitle and "Menu:" in subtitle
	assert_true(is_fallback or has_live_shape,
		"subtitle must match fallback OR 'A:X  B:Y  Menu:Z' shape, got: '%s'" % subtitle)
