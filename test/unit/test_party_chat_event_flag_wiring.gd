extends GutTest

## tick 247: catches the silent-fail class where a PartyChatSystem
## REGISTRY entry references an event_flag_* that NO code path ever
## sets. The chat is dead content — visible nowhere because its
## unlock condition can never become true.
##
## Pre-tick-247: all 8 event_chat_* entries were dead (none of their
## flags were emitted). Tick 246's structural audit checked the flag
## naming convention but not whether the flag was actually fired.
##
## Now: each event_chat unlock flag is either
##   - wired (a .gd file in src/ writes it to game_constants), OR
##   - in KNOWN_UNWIRED below (acknowledged dormant content debt).
##
## When a flag gets wired up, remove it from KNOWN_UNWIRED. When a
## new event_chat entry is added without wiring, the test fails until
## either the wiring lands or the entry joins KNOWN_UNWIRED.

const PARTY_CHAT := "res://src/cutscene/PartyChatSystem.gd"

## Event flags that have a REGISTRY entry but are not yet emitted
## anywhere in src/. Acknowledged content debt — wire one per tick.
##
## tick 247 wave: removed 2 (level_10_reached, first_autobattle_enabled).
## tick 248 wave: removed 2 more (first_party_wipe, first_group_attack).
const KNOWN_UNWIRED: Array[String] = [
	"event_flag_first_magic_shop_visited",
	"event_flag_rare_drop_found",
	"event_flag_dragon_cave_entered",
	"event_flag_one_hp_victory",
]


func _system() -> Object:
	var script: GDScript = load(PARTY_CHAT)
	return script.new()


# Recursively grep src/ for a literal write to a given flag name.
# Matches either:
#   game_constants["FLAG_NAME"] =
#   game_constants.FLAG_NAME =
#   set_meta("FLAG_NAME"
# We use the conservative form "FLAG_NAME" appearing in any non-test
# .gd file in src/ AND outside PartyChatSystem.gd itself.
func _is_flag_emitted(flag_name: String) -> bool:
	var dir := DirAccess.open("res://src")
	if dir == null:
		return false
	return _walk_for_flag(dir, "res://src", flag_name)


func _walk_for_flag(dir: DirAccess, base: String, flag_name: String) -> bool:
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full: String = "%s/%s" % [base, entry]
		if dir.current_is_dir():
			var subdir := DirAccess.open(full)
			if subdir != null and _walk_for_flag(subdir, full, flag_name):
				dir.list_dir_end()
				return true
		elif entry.ends_with(".gd") and not entry.ends_with("PartyChatSystem.gd"):
			var content: String = FileAccess.get_file_as_string(full)
			if content.contains("\"" + flag_name + "\""):
				dir.list_dir_end()
				return true
	dir.list_dir_end()
	return false


# ── Audit 1: every event_flag_* in REGISTRY is wired or KNOWN_UNWIRED

func test_every_event_flag_is_wired_or_acknowledged() -> void:
	var sys: Object = _system()
	var registry: Dictionary = sys.REGISTRY
	var dead: Array[String] = []
	for id in registry.keys():
		var entry: Dictionary = registry[id]
		for flag in entry.get("unlock", []):
			var f: String = str(flag)
			if not f.begins_with("event_flag_"):
				continue
			if _is_flag_emitted(f):
				continue
			if f in KNOWN_UNWIRED:
				continue
			dead.append("%s -> %s" % [id, f])
	assert_eq(dead.size(), 0,
		"event_flag_* references with no code emitter and not in KNOWN_UNWIRED (chat will never unlock): %s" % str(dead))


# ── Audit 2: KNOWN_UNWIRED has no stale entries ─────────────────────

func test_known_unwired_entries_still_dormant() -> void:
	# If a flag is in KNOWN_UNWIRED but now HAS an emitter, the registry
	# entry got wired up — remove it from the list.
	var newly_wired: Array[String] = []
	for f in KNOWN_UNWIRED:
		if _is_flag_emitted(f):
			newly_wired.append(f)
	assert_eq(newly_wired.size(), 0,
		"KNOWN_UNWIRED entries that now have an emitter (remove from list): %s" % str(newly_wired))


# ── Audit 3: KNOWN_UNWIRED has no orphan entries ────────────────────

func test_known_unwired_entries_still_referenced_by_registry() -> void:
	# If a flag is in KNOWN_UNWIRED but no REGISTRY entry references
	# it anymore, the registry entry was removed — clean up the list.
	var sys: Object = _system()
	var registry: Dictionary = sys.REGISTRY
	var referenced: Dictionary = {}
	for id in registry.keys():
		for flag in registry[id].get("unlock", []):
			referenced[str(flag)] = true
	var orphans: Array[String] = []
	for f in KNOWN_UNWIRED:
		if not referenced.has(f):
			orphans.append(f)
	assert_eq(orphans.size(), 0,
		"KNOWN_UNWIRED entries not referenced by any REGISTRY unlock (remove from list): %s" % str(orphans))


# ── Audit 4: tick 247 wave specifically wired ──────────────────────

func test_tick_247_level_10_flag_wired() -> void:
	assert_true(_is_flag_emitted("event_flag_level_10_reached"),
		"event_flag_level_10_reached must be set by GameLoop._on_party_leveled_up")


func test_tick_247_autobattle_flag_wired() -> void:
	assert_true(_is_flag_emitted("event_flag_first_autobattle_enabled"),
		"event_flag_first_autobattle_enabled must be set by AutobattleSystem.set_autobattle_enabled")


func test_tick_248_first_party_wipe_flag_wired() -> void:
	assert_true(_is_flag_emitted("event_flag_first_party_wipe"),
		"event_flag_first_party_wipe must be set by BattleManager._check_victory_conditions when party loses")


func test_tick_248_first_group_attack_flag_wired() -> void:
	assert_true(_is_flag_emitted("event_flag_first_group_attack"),
		"event_flag_first_group_attack must be set by BattleManager._execute_group_action on any pooled strike")
