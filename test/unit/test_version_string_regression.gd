extends GutTest

## Regression: Version is the single source of truth for the game version
## string. TitleScreen and SaveSystem (and any future surface that needs
## a version label) MUST read from Version instead of hard-coding their
## own copies. Pins both the contract (display = "v" + semver) AND the
## wiring (no stale string literals left in either consumer).

const VERSION_PATH := "res://src/meta/Version.gd"
const TITLE_SCREEN_PATH := "res://src/ui/TitleScreen.gd"
const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_version_display_prefixes_semver_with_v() -> void:
	var v = load(VERSION_PATH)
	assert_not_null(v, "Version.gd must load")
	# 2026-07-02: display() may append " (githash)" in dev runs so
	# playtest screenshots self-document the build — the pin is now
	# prefix + optional dev-marker shape (exact values in
	# test_version_display_regression).
	assert_true(v.display().begins_with("v" + v.semver()),
		"Version.display() must start with 'v' + Version.semver()")
	var suffix: String = v.display().trim_prefix("v" + v.semver())
	assert_true(suffix == "" or (suffix.begins_with(" (") and suffix.ends_with(")")),
		"display() may only append the ' (githash)' dev marker, got: '%s'" % suffix)
	assert_false(v.semver().begins_with("v"),
		"Version.semver() must NOT include the 'v' prefix — save tooling parses this as raw semver")


func test_semver_follows_x_y_z_optional_suffix_format() -> void:
	var v = load(VERSION_PATH)
	var sv: String = v.semver()
	# Loose format check: at minimum X.Y.Z, possibly with -suffix. We're not
	# imposing strict semver here, just rejecting obvious garbage like
	# empty / placeholder strings.
	var parts = sv.split(".")
	assert_true(parts.size() >= 3,
		"Version.semver() must have at least three dot-separated components, got: %s" % sv)
	assert_true(sv.length() >= 5,
		"Version.semver() must be a real version string (len >= 5), got: %s" % sv)


func test_title_screen_reads_from_version_not_hardcoded() -> void:
	var text = _read(TITLE_SCREEN_PATH)
	assert_true(text.find("Version.display()") > -1,
		"TitleScreen must read from Version.display()")
	# Catch the most likely stale literal patterns. If the version label ever
	# gets re-hardcoded, this fails loud.
	assert_false(text.find("\"v0.5.0\"") > -1,
		"TitleScreen must not contain the stale hard-coded 'v0.5.0' literal")
	assert_false(text.find("\"v0.1.0\"") > -1,
		"TitleScreen must not contain a hard-coded 'v0.1.0' literal")


func test_save_system_writes_version_from_version_helper() -> void:
	var text = _read(SAVE_SYSTEM_PATH)
	assert_true(text.find("Version.semver()") > -1,
		"SaveSystem must populate game_version from Version.semver()")
	assert_false(text.find("\"game_version\": \"0.1.0\"") > -1,
		"SaveSystem must not contain the stale hard-coded '0.1.0' game_version literal")
