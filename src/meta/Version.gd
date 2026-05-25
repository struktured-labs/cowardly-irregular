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

const SEMVER := "3.26.0-alpha"


static func display() -> String:
	## Player-facing string for the title screen, credits, debug overlays.
	return "v" + SEMVER


static func semver() -> String:
	## Raw semver — used by SaveSystem when writing the save-file
	## `game_version` field. Save tooling parses this so DO NOT prepend "v".
	return SEMVER
