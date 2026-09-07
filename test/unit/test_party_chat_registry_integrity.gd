extends GutTest

## tick 246: structural integrity guard for PartyChatSystem REGISTRY.
##
## Catches the silent-fail class where a registry entry exists but its
## cutscene file doesn't, or the entry shape drifts (missing title,
## bad world, malformed unlock list). UI surfaces these as "click chat,
## nothing happens" — the user sees the title but the game silently
## refuses to play it.
##
## Audits:
##   1. Every REGISTRY id has a matching res://data/cutscenes/<id>.json
##   2. Every entry has the required keys (title/world/unlock) of the
##      right type.
##   3. Every unlock flag is either a cutscene_flag_* or event_flag_*
##      (the two recognized namespaces). Misnamed flags would never
##      get set and the chat would never unlock.
##   4. World ints are in [1, 6] — out-of-range groups would orphan
##      in the menu.

const CUTSCENES_DIR := "res://data/cutscenes"
const PARTY_CHAT := "res://src/cutscene/PartyChatSystem.gd"


func _system() -> Object:
	# Use the autoload if it's available; otherwise instantiate from
	# script. Both paths share the same REGISTRY const.
	var script: GDScript = load(PARTY_CHAT)
	var sys: Object = script.new()
	return sys


# ── Audit 1: every REGISTRY id has a cutscene file ─────────────────

func test_every_registry_id_has_cutscene_json() -> void:
	var sys: Object = _system()
	var registry: Dictionary = sys.REGISTRY
	var missing: Array[String] = []
	for id in registry.keys():
		var path := "%s/%s.json" % [CUTSCENES_DIR, id]
		if not FileAccess.file_exists(path):
			missing.append(id)
	assert_eq(missing.size(), 0,
		"REGISTRY ids without a data/cutscenes/<id>.json — would crash on play: %s" % str(missing))


# ── Audit 2: each entry has the required keys / types ──────────────

func test_every_entry_has_required_keys() -> void:
	var sys: Object = _system()
	var registry: Dictionary = sys.REGISTRY
	var malformed: Array[String] = []
	for id in registry.keys():
		var entry: Dictionary = registry[id]
		if not (entry.has("title") and entry.title is String and entry.title != ""):
			malformed.append("%s: bad title" % id)
		if not (entry.has("world") and entry.world is int):
			malformed.append("%s: bad world" % id)
		if not (entry.has("unlock") and entry.unlock is Array):
			malformed.append("%s: bad unlock" % id)
	assert_eq(malformed.size(), 0,
		"REGISTRY entries with missing or wrong-type keys: %s" % str(malformed))


# ── Audit 3: unlock flags follow cutscene_flag_* / event_flag_* ────

func test_unlock_flags_match_known_namespaces() -> void:
	var sys: Object = _system()
	var registry: Dictionary = sys.REGISTRY
	var bad_flags: Array[String] = []
	for id in registry.keys():
		var entry: Dictionary = registry[id]
		for flag in entry.get("unlock", []):
			var f: String = str(flag)
			if not (f.begins_with("cutscene_flag_") or f.begins_with("event_flag_")):
				bad_flags.append("%s -> '%s'" % [id, f])
	assert_eq(bad_flags.size(), 0,
		"unlock flags must use cutscene_flag_* or event_flag_* prefix — misnamed flags never get set: %s" % str(bad_flags))


# ── Audit 4: world ints are 1..6 ───────────────────────────────────

func test_world_ints_are_in_range() -> void:
	var sys: Object = _system()
	var registry: Dictionary = sys.REGISTRY
	var oob: Array[String] = []
	for id in registry.keys():
		var w: int = registry[id].get("world", 0)
		if w < 1 or w > 6:
			oob.append("%s -> world %d" % [id, w])
	assert_eq(oob.size(), 0,
		"REGISTRY world ints must be 1..6 — out-of-range entries orphan in the menu group: %s" % str(oob))


# ── Audit 5: REGISTRY ids contain no whitespace / weird chars ──────

func test_registry_ids_are_snake_case() -> void:
	# Cutscene file paths are derived directly from REGISTRY ids; a
	# space or capital letter would break FileAccess on case-sensitive
	# filesystems (Linux/macOS-case-sensitive volumes).
	var sys: Object = _system()
	var registry: Dictionary = sys.REGISTRY
	var rx := RegEx.new()
	rx.compile("^[a-z0-9_]+$")
	var bad: Array[String] = []
	for id in registry.keys():
		if rx.search(str(id)) == null:
			bad.append(str(id))
	assert_eq(bad.size(), 0,
		"REGISTRY ids must be lowercase snake_case (matches [a-z0-9_]+): %s" % str(bad))


# ── Audit 6: mark_viewed warns on unregistered id (tick 246 fix) ───

func test_mark_viewed_does_not_write_for_unregistered_id() -> void:
	# The fix: mark_viewed now pushes a warning AND still skips the
	# write. Confirm no `party_chat_viewed_typo` key gets created.
	# Use an inline GDScript so the override holder exposes the
	# game_constants property that PartyChatSystem._flags() expects.
	var holder_script := GDScript.new()
	holder_script.source_code = "extends Node\nvar game_constants: Dictionary = {}\n"
	holder_script.reload()
	var holder: Node = holder_script.new()
	add_child_autofree(holder)
	var sys: Object = _system()
	sys.game_state_override = holder
	sys.mark_viewed("__definitely_not_registered_xyz")
	assert_false(holder.game_constants.has("party_chat_viewed___definitely_not_registered_xyz"),
		"mark_viewed must not write a flag for unregistered ids — protective skip")
