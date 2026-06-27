extends GutTest

## tick 273: every TeleportMenu DESTINATIONS id must have a
## corresponding match-case in GameLoop._start_exploration. Pre-fix
## audit confirmed all 41 entries are wired, but the match-default
## at the bottom of _start_exploration silently falls through to
## OverworldSceneRes.instantiate() (the W1 medieval overworld) — so
## a typo'd id or a new destination added without a handler would
## warp the player to the wrong place with NO visible error.
##
## This test pins the contract so future additions catch the silent
## fall-through.


const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"
const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# Extracts every {"id": "X"} from DESTINATIONS via regex.
func _destination_ids() -> Array:
	var src: String = _read(TELEPORT_MENU)
	var rx := RegEx.new()
	rx.compile("\"id\":\\s*\"([a-z0-9_]+)\"")
	var out: Array[String] = []
	for m in rx.search_all(src):
		var id: String = m.get_string(1)
		if id != "" and not (id in out):
			out.append(id)
	return out


# Extracts every match case "X": from _start_exploration.
func _start_exploration_match_ids() -> Array:
	var src: String = _read(GAME_LOOP)
	var fn_idx: int = src.find("func _start_exploration")
	assert_gt(fn_idx, -1, "_start_exploration must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Match case lines look like:  "harmonia_village":
	var rx := RegEx.new()
	rx.compile("^\\s*\"([a-z0-9_]+)\":")
	var out: Array[String] = []
	for line in body.split("\n"):
		var m := rx.search(line)
		if m != null:
			out.append(m.get_string(1))
	return out


# ── Every DESTINATIONS id has a match-case ─────────────────────────

func test_every_destination_has_start_exploration_handler() -> void:
	var dest_ids: Array = _destination_ids()
	assert_gt(dest_ids.size(), 0, "must find DESTINATIONS in TeleportMenu")
	var handlers: Array = _start_exploration_match_ids()
	assert_gt(handlers.size(), 0, "must find match cases in _start_exploration")
	var unwired: Array[String] = []
	for id in dest_ids:
		if not (id in handlers):
			unwired.append(id)
	assert_eq(unwired.size(), 0,
		"TeleportMenu destinations without _start_exploration handlers — match-default would silently warp to the W1 overworld: %s" % str(unwired))


# ── Default fallthrough still exists (so the bug class survives if test fails) ─

func test_start_exploration_has_overworld_default() -> void:
	# Sanity: the default fallthrough is what makes the bug class
	# silent. If it ever changes (e.g. push_warning instead), this
	# pin and the audit above can be relaxed together — but flagging
	# the default's existence keeps the rationale visible.
	var src: String = _read(GAME_LOOP)
	var fn_idx: int = src.find("func _start_exploration")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Look for the wildcard match arm followed by OverworldSceneRes.
	assert_true(body.contains("_:\n\t\t\texploration_scene = OverworldSceneRes.instantiate()") or body.contains("OverworldSceneRes.instantiate()"),
		"_start_exploration must still have the OverworldSceneRes default — if removed, this test + the audit above can both be relaxed")


# ── Count sanity: at least 30 destinations wired ──────────────────

func test_at_least_30_destinations_wired() -> void:
	# Catches accidental destination-list deletion in a refactor.
	var dest_ids: Array = _destination_ids()
	assert_gt(dest_ids.size(), 30,
		"TeleportMenu must declare at least 30 destinations (was 41 at tick 273; significant shrink should be intentional)")
