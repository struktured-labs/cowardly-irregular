extends GutTest

## tick 271: QuestLog CHAPTERS flag wiring audit.
##
## Pre-fix W2-W6 chapter entries used `w2_entered` / `w2_dungeon
## _cleared` and similar — flags NOTHING in the game ever sets.
## Every entry past Chapter 1 was permanently locked from the
## player's POV; entire QuestLog past Chapter 1 was dead config.
##
## Bug class: a static REGISTRY references string flags that no
## upstream code emits. Same pattern as tick 247-250's PartyChat
## event_flag_* sweep and tick 252's RebalanceDaemon trigger audit.
## The flag-firing audit guard pattern catches it.
##
## Audits:
##   1. Every flag referenced by CHAPTERS is either:
##      - set somewhere in src/ (the writer side exists), OR
##      - in KNOWN_DORMANT (acknowledged unimplemented content).
##   2. The 5 specific W2-W6 fixes landed (no `w2_entered` survivors).

const QUEST_LOG := "res://src/ui/QuestLog.gd"


## Flags intentionally NOT yet wired. CHAPTERS uses bare names that
## _is_quest_flag_set wraps with cutscene_flag_ — both forms count
## as "wired" when scanning src.
const KNOWN_DORMANT: Array[String] = [
	# Chapter 1 has these placeholders; none of them are needed
	# because they fire from in-game cutscenes already covered by
	# other audits.
]


func _scrape_chapter_flags() -> Array:
	# Pull every "flag": "X" reference from CHAPTERS.
	var src: String = FileAccess.get_file_as_string(QUEST_LOG)
	var rx := RegEx.new()
	rx.compile("\"flag\":\\s*\"([a-z0-9_]+)\"")
	var out: Array[String] = []
	for m in rx.search_all(src):
		var flag: String = m.get_string(1)
		if flag != "" and not (flag in out):
			out.append(flag)
	return out


func _is_flag_emitted(flag: String) -> bool:
	# Scan src/ for the flag (bare OR cutscene_flag_ prefixed form).
	# Skip QuestLog.gd itself since that's the REGISTRY, not the writer.
	var bare_quoted: String = "\"" + flag + "\""
	var prefixed_quoted: String = "\"cutscene_flag_" + flag + "\""
	var dir := DirAccess.open("res://src")
	if dir == null:
		return false
	return _walk_for_ref(dir, "res://src", bare_quoted, prefixed_quoted, flag)


func _walk_for_ref(dir: DirAccess, base: String, bare: String, prefixed: String, raw_flag: String) -> bool:
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full: String = "%s/%s" % [base, entry]
		if dir.current_is_dir():
			var sub := DirAccess.open(full)
			if sub != null and _walk_for_ref(sub, full, bare, prefixed, raw_flag):
				dir.list_dir_end()
				return true
		elif entry.ends_with(".gd") and not entry.ends_with("QuestLog.gd"):
			var content: String = FileAccess.get_file_as_string(full)
			# Match either the bare quoted form OR the cutscene_flag_-
			# prefixed form. Note: this also matches READ sites (gates)
			# not just writes — but for QuestLog the read-as-flag pattern
			# is rare; if a flag appears anywhere quoted, something cares.
			if content.contains(bare) or content.contains(prefixed):
				dir.list_dir_end()
				return true
	dir.list_dir_end()
	return false


# ── Audit 1: every CHAPTERS flag has a writer ─────────────────────

func test_every_chapters_flag_has_emitter_or_is_dormant() -> void:
	var flags: Array = _scrape_chapter_flags()
	assert_gt(flags.size(), 0, "sanity: must find at least one flag in CHAPTERS")
	var dead: Array[String] = []
	for flag in flags:
		if _is_flag_emitted(flag):
			continue
		if flag in KNOWN_DORMANT:
			continue
		dead.append(flag)
	assert_eq(dead.size(), 0,
		"QuestLog CHAPTERS flags with no emitter and not in KNOWN_DORMANT (would lock the chapter entry forever): %s" % str(dead))


# ── Audit 2: the 5 specific tick-271 fixes landed ──────────────────

func test_w2_w6_no_longer_use_dead_w_entered_flags() -> void:
	var src: String = FileAccess.get_file_as_string(QUEST_LOG)
	# Negative pins: the dead flag names must be gone.
	for dead_flag in ["w2_entered", "w3_entered", "w4_entered", "w5_entered", "w6_entered",
			"w2_dungeon_cleared", "w3_dungeon_cleared", "w4_dungeon_cleared", "w5_dungeon_cleared"]:
		assert_false(src.contains("\"" + dead_flag + "\""),
			"dead flag %s must NOT appear in CHAPTERS (was never set anywhere — chapter would lock forever)" % dead_flag)


func test_w2_w6_use_real_world_prologue_flags() -> void:
	var src: String = FileAccess.get_file_as_string(QUEST_LOG)
	for w in range(2, 7):
		var prologue: String = "world%d_prologue_complete" % w
		assert_true(src.contains("\"" + prologue + "\""),
			"CHAPTERS must reference the real W%d entry flag '%s'" % [w, prologue])


func test_w2_w5_use_real_world_complete_flags() -> void:
	# W2-W5 chapter-clear flag. W6 doesn't have a "next world" entry
	# in the current CHAPTERS so it's exempt.
	var src: String = FileAccess.get_file_as_string(QUEST_LOG)
	for w in range(2, 6):
		var complete: String = "world%d_complete" % w
		assert_true(src.contains("\"" + complete + "\""),
			"CHAPTERS must reference the real W%d clear flag '%s'" % [w, complete])
