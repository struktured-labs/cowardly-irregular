extends RefCounted
class_name Version

## Single source of truth for the game version string.
##
## Bumped at release time. TitleScreen, SaveSystem, and any future surface
## that needs to surface or persist a version MUST read from here instead
## of hard-coding their own copies — keeps every visible version label in
## lockstep across the UI and the save format without grep-and-replace.
##
## Format: semver with optional pre-release suffix. e.g. "3.26.0-alpha" or
## "3.27.0-alpha". display() prepends "v" for UI rendering; semver() returns
## the raw form for save-file persistence (where prepending "v" would break
## any downstream tooling that expects a parseable semver string).
##
## 2026-07-02: display() now appends the git short-hash in DEV runs
## ("v3.31.0-alpha (f2602525)") so F12 playtest screenshots self-document
## which build they came from — three of tonight's bug reports arrived
## with no way to tell. Exported builds can't run git (and web has no
## OS.execute at all) so they fall back to the clean semver; deploys are
## already tagged via butler --userversion.

const SEMVER := "3.32.73-alpha"

static var _dev_hash_cached: bool = false
static var _dev_hash: String = ""


static func display() -> String:
	## Player-facing string for the title screen, credits, debug overlays.
	var h := _git_short_hash()
	if h == "":
		return "v" + SEMVER
	return "v%s (%s)" % [SEMVER, h]


static func semver() -> String:
	## Raw semver — used by SaveSystem when writing the save-file
	## `game_version` field. Save tooling parses this so DO NOT prepend "v"
	## and NEVER append the dev hash.
	return SEMVER


## Git short-hash when running from a source checkout; "" in exports.
## Shelling out beats parsing .git by hand — this checkout is a worktree
## (.git is a gitdir pointer file) and refs can live in packed-refs.
static func _git_short_hash() -> String:
	if _dev_hash_cached:
		return _dev_hash
	_dev_hash_cached = true
	_dev_hash = ""
	if OS.has_feature("web"):
		return _dev_hash
	var proj: String = ProjectSettings.globalize_path("res://")
	var out: Array = []
	var code: int = OS.execute("git", ["-C", proj, "rev-parse", "--short=8", "HEAD"], out)
	if code == 0 and out.size() > 0:
		var h: String = str(out[0]).strip_edges()
		if h.length() >= 7 and h.is_valid_hex_number():
			_dev_hash = h
	return _dev_hash
