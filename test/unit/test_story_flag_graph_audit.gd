extends GutTest

## Permanent version of the tick-271/278/281 audits: a story flag that a gate READS but nothing ever
## WRITES is permanently-locked content — authored, shipped, and unreachable by any play.
##
## ⛔ TWO DEFECTS IN THIS FILE'S OWN INSTRUMENT, FIXED 2026-10-14, FAILING IN OPPOSITE DIRECTIONS —
## which is why only one of them could ever have been noticed.
## (1) The src writer corpus was a PINNED LIST OF 13 FILES modelling THREE src write forms —
## `set_story_flag("x"`, `fire_event_flag("x"`, and a `game_constants|story_flags|dungeon_flags["x"]
## =` assignment. SRC HAS THREE MORE: `defeat_cutscene_flags = [...]`, the boss-defeat bridge (7
## flags); the `_CUTSCENE_COMPLETION_FLAGS` map (89); and a COMPOSED name, the one still not
## modelled and stated as a blind spot below. Three of six, and the two countable ones are added
## here. A missing write form makes a WRITTEN flag look dead, so that half fails LOUD; the repair
## such a red invites is an exemption entry, which is rot.
## (2) Its fourth regex alternative was a BARE `"cutscene_flag_*"` STRING LITERAL, and a mention is
## not a write. Measured on this tree: that alternative supplied 124 of the writer set, 121 of them
## with no write shape anywhere — a `flags.get("cutscene_flag_x", false)` READ certified `x` as
## written. Three quest prereqs rested on it alone. They ARE written, by the completion map this
## file did not model, so the VERDICT was right while the reasoning was not. That is the shape that
## survives indefinitely: a green from a broken predicate is never re-examined.
##
## 🔑 AND THE SURFACES THAT HAVE ACTUALLY SHIPPED DEAD WERE NOT WATCHED HERE. The paragraph above
## said "the QuestLog W2-W6 chapters and tracker objectives all shipped dead this way once" while
## the only arm read quest prereq/required flags. Three surfaces join it below, and I checked what
## already guarded each BEFORE claiming any of them — the first version of this header called all
## three new and two of them were not:
##   party chat `unlock`   30 flags, 44 chats   GENUINELY UNGUARDED. The neighbouring guard's
##     `test_every_lock_flag_has_a_writer` iterates `lock` only, which is TWO flags. An unlock flag
##     nothing writes hides its chat forever; the `lock` arm cannot see it.
##   chapter cards         9 of 56 UNGUARDED. `test_chapter_titles_data_integrity`'s own docstring
##     promises "every flag in CHAPTERS must be SET somewhere" and NO FUNCTION IMPLEMENTS IT. Its
##     placement arm iterates DUNGEON flags and `continue`s when no card matches, so it never reads
##     a card; its completion arm covers the 47 `*_complete` entries. The other 9 — every
##     `*_defeated` card plus two event cards — had no writer arm of any kind.
##   world map             ALREADY GUARDED, by `test_every_progress_flag_has_emitter`, whose
##     predicate is `src.contains("\"<flag>\"")` — A BARE LITERAL, the same defect this file is
##     removing from itself. Both guards were green. The arm below is a stronger predicate on a
##     watched surface, not a new surface, and the weaker one is left to its own file.
## Each reads the CONSUMER's OWN const rather than re-parsing its source text.
##
## ⚠️ STATED BLIND SPOT, measured rather than left implicit: three src sites COMPOSE a flag name.
## `game_constants["cutscene_flag_" + flag] = ...` (CutsceneDirector) is the generic cutscene
## mechanism and `_is_written`'s prefix alias already covers it. `"cutscene_flag_spotlight_*" + job`
## (GameLoop) is NOT modelled, and no watched surface reads a spotlight flag today. If one ever
## does, its arm reds and the repair is to model that write form — never to exempt the flag.
##
## 📌 WHY THIS DOES NOT USE `GdSource`, which is the project's comment stripper and the obvious
## choice: its strip is a per-CHARACTER GDScript loop, and the corpus here is 307 files / 8.4 MB of
## `res://src`, walked for every arm. Instead the patterns run on RAW text in the engine's own C++
## RegEx and each HIT is then rejected if a `#` precedes it ON ITS LINE — ~200 cheap checks instead
## of 8.4 M interpreted iterations. 🔑 AND THE COST WAS THE WEAKER HALF OF THAT ARGUMENT: this file
## USES POSITIONS (`get_start` -> `rfind` -> `substr`), and `GdSource.split()` REJOINS its kept
## parts, so the line map does not survive it — @cowir-battle measured +57 lines of drift on
## `BattleManager.gd` and +4 on `HeadlessBattleResolver.gd`, 2026-10-14, in an arm that printed
## `i + 1` as a source line and therefore named healthy code. Rejecting per HIT on the RAW text
## keeps every offset true by construction, which is the correctness reason rather than the
## performance one. `strip_comments` alone IS line-preserving and would also serve; `code_of` is
## the one that cannot. Measured: full-strip, line-strip and no-strip all yield the same
## 58 src writers TODAY — and that is the WRITER patterns only. 🔑 ON THE SHIPPED TREE THE RULE HAS
## EXACTLY ONE LIVE INSTANCE, found by @cowir-sfx's direct test (run each pattern over RAW and over
## COMMENT-STRIPPED source and diff the results — a delta of zero IS the absence of exposure, with
## no predicate to be wrong about, which beats every filter five lanes wrote on 2026-10-14):
##     writer patterns      raw 30 / 22 / 7   stripped 30 / 22 / 7    delta 0
##     mention_all          raw 129           stripped 128            delta 1
##     the one: `cutscene_flag_wardin_industrial_defeated`, GameLoop.gd:4163 — a comment that
##     quotes a DELIBERATELY MISSPELLED flag as an example of the very defect it warns about
##     ("a subclass typo sets the wrong flag silently"). Without `_is_commented` that fake name
##     enters the mention arm's population.
## So the rule is not kept for a state that will arrive; it is already earning its place once.
## `test_control_a_commented_write_is_not_a_writer` proves BOTH directions on planted text, because
## the real corpus contains no instance and a rule with no instance cannot be proven by the corpus.

const GAME_LOOP := preload("res://src/GameLoop.gd")
## PRELOADED rather than read off the autoload, which is the house idiom in three existing party-chat
## guards and is also the louder call shape (@cowir-adhoc / @cowir-ai, 2026-10-14): a const on a
## preloaded script resolves at PARSE time, so a rename is EC=3 and nothing ran, while
## `PartyChatSystem.REGISTRY` through the autoload INSTANCE raises mid-arm and GUT scores the
## aborted body as a PASS. `_party_chat_flags()` would then return {} and its arm would pass by
## judging nothing — the reader floor does catch that, but EC=3 needs no floor to be read correctly.
const PARTY_CHAT := preload("res://src/cutscene/PartyChatSystem.gd")
const SRC_ROOT := "res://src"

## ⛔ THE `INTENTIONALLY_UNWRITTEN` EXEMPTION IS GONE, MEASURED DEAD 2026-10-14. It held
## `quest_wiring_chicken_catch_ready` and `quest_wiring_light_spell_ready` — the 2026-07 convention
## of OVERWRITING a quest's `prereq_flag` with a never-set `quest_wiring_*_ready` gate to withhold
## unwired content. Both flags now have **ZERO occurrences anywhere in `data/quests/` or `src/`**,
## and neither appears in any of the four reader populations, so removing the list changes no
## verdict. 🔑 It is the same convention this lane's `wiring_pending` key replaces, for the reason
## that five of the ten withheld quests have a REAL prereq an overwrite would have destroyed — so
## the exemption outlived not just its entries but its whole mechanism. An exemption's stated
## condition is a claim about something OUTSIDE the guard, and nothing here was ever going to notice
## it expiring. If either flag returns as a gate with no writer, an arm reds and NAMES it, which is
## the outcome the list was suppressing.

## EVERY MODELLED FORM MUST CONTRIBUTE AT LEAST ONE, and the TOTAL carries the only numeric floor.
## A dead write form does not fail this file — it certifies fewer flags and makes every reader arm
## quietly GREENER — so the contribution has to be asserted. But the floor is 1 rather than ~80% of
## today's count, because @cowir-adhoc and @cowir-controller measured the other failure this hour:
## A NUMBER DESCRIBING A POPULATION SEVERAL LANES ARE DELIBERATELY CHANGING CANNOT BE A FLOOR. Their
## case was 25 test files with an untied preset ladder while three lanes were converting them; mine
## would be a refactor migrating `game_constants["x"] = true` sites to `set_story_flag("x")` — the
## counts move BETWEEN forms, the total does not, and a per-form floor of 17 would red on a correct
## change while a floor of 1 still reds on the thing it exists for. A form reaching 0 means the form
## is gone from the project, and the right repair is then to delete it from the model, not to lower
## a number. Measured 2026-10-14 (identical on `.693` and `.694`): cutscene_set_flag 197 ·
## quest_flag_on_complete 123 · completion_map 89 · constants_assign 22 · set_story_flag 19 ·
## fire_event_flag 11 · defeat_bridge 7 · 458 distinct flags written.
const MODELLED_FORMS := [
	"cutscene_set_flag",
	"quest_flag_on_complete",
	"set_story_flag",
	"fire_event_flag",
	"constants_assign",
	"defeat_bridge",
	"completion_map",
]
const TOTAL_WRITER_FLOOR := 360

## Same idea on the reader side: an empty parse makes an arm pass by having nothing to judge.
const READER_FLOORS := {"quest": 60, "chapter_title": 45, "world_map": 30, "party_chat": 20}

var _writers_cache: Dictionary = {}


func _gd_files() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [SRC_ROOT]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		var d := DirAccess.open(cur)
		if d == null:
			continue
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			var full: String = "%s/%s" % [cur, n]
			if d.current_is_dir():
				if not n.begins_with("."):
					stack.append(full)
			elif n.ends_with(".gd"):
				out.append(full)
			n = d.get_next()
		d.list_dir_end()
	return out


func _json_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n.ends_with(".json"):
			out.append("%s/%s" % [dir_path, n])
		n = d.get_next()
	d.list_dir_end()
	return out


func _add(w: Dictionary, flag: String, form: String) -> void:
	if flag == "":
		return
	if not w.has(flag):
		w[flag] = []
	if not (form in w[flag]):
		w[flag].append(form)


## True when a `#` opens a comment before `at` on that line, so the hit is prose about the code.
## A `#` inside a string literal earlier on the same line would reject a real write — that LOSES a
## writer and reds, the direction worth failing in, and no line in src has that shape today.
func _is_commented(text: String, at: int) -> bool:
	var line_start: int = text.rfind("\n", at)
	line_start = 0 if line_start < 0 else line_start + 1
	return text.substr(line_start, at - line_start).contains("#")


## The src half of the writer set, as a pure function of TEXT so a control can plant its own.
func _writers_in_text(text: String, w: Dictionary) -> void:
	var rx_call := RegEx.create_from_string("(set_story_flag|fire_event_flag)\\(\\s*\"([a-z0-9_]+)\"")
	var rx_assign := RegEx.create_from_string(
		"(?:game_constants|story_flags|dungeon_flags)\\[\\s*\"([a-z0-9_]+)\"\\s*\\]\\s*=[^=]")
	var rx_bridge := RegEx.create_from_string("defeat_cutscene_flags\\s*=\\s*\\[([^\\]\\n]*)\\]")
	var rx_quoted := RegEx.create_from_string("\"([a-z0-9_]+)\"")
	for m in rx_call.search_all(text):
		if not _is_commented(text, m.get_start()):
			_add(w, m.get_string(2), m.get_string(1))
	for m in rx_assign.search_all(text):
		if not _is_commented(text, m.get_start()):
			_add(w, m.get_string(1), "constants_assign")
	for m in rx_bridge.search_all(text):
		if _is_commented(text, m.get_start()):
			continue
		for inner in rx_quoted.search_all(m.get_string(1)):
			_add(w, inner.get_string(1), "defeat_bridge")


## {flag: [forms that WRITE it]}. Cached: five arms ask, and the walk is the expensive part.
func _writers() -> Dictionary:
	if not _writers_cache.is_empty():
		return _writers_cache
	var w: Dictionary = {}
	for f in _json_files("res://data/cutscenes"):
		var d = JSON.parse_string(FileAccess.get_file_as_string(f))
		if d is Dictionary:
			for s in d.get("steps", []):
				if s is Dictionary and str(s.get("type", "")) == "set_flag":
					_add(w, str(s.get("flag", "")), "cutscene_set_flag")
	for f in _json_files("res://data/quests"):
		var q = JSON.parse_string(FileAccess.get_file_as_string(f))
		if q is Dictionary:
			_add(w, str(q.get("flag_on_complete", "")), "quest_flag_on_complete")
			for o in q.get("objectives", []):
				if o is Dictionary:
					_add(w, str(o.get("flag_on_complete", "")), "quest_flag_on_complete")
	for path in _gd_files():
		_writers_in_text(FileAccess.get_file_as_string(path), w)
	for cutscene_id in GAME_LOOP._CUTSCENE_COMPLETION_FLAGS:
		_add(w, str(GAME_LOOP._CUTSCENE_COMPLETION_FLAGS[cutscene_id]), "completion_map")
	_writers_cache = w
	return w


## A cutscene's `set_flag: "x"` step lands in `game_constants["cutscene_flag_x"]`, so the two
## spellings are one flag. This alias is also what covers CutsceneDirector's composed write.
##
## 📌 WHICH OF THE THREE CLAUSES IS LOAD-BEARING. ⚠️ MEASURED BY A PYTHON REPLICA DISABLING EACH,
## NOT BY THE ENGINE — the earlier wording said "measured by disabling each", which reads as an
## engine measurement and is the one over-claiming sentence in this file. A replica cannot fail the
## way the guard would (@cowir-ai, 2026-10-14, whose own replica and guard disagreed about a
## reachable state), so these three numbers are PREDICTIONS from an instrument that has agreed with
## the engine on fourteen other measurements, not results. (@cowir-adhoc's test for
## "leave it alone"): exact-only leaves 20 reader flags dead (quest 2 · chapter 12 · worldmap 4 ·
## partychat 2), and all 20 are recovered by the TRIMMED alias — readers spell `cutscene_flag_X`
## while the cutscene JSON writes `X`. ⚠️ The PREFIXED alias is a BELT: disabling it changes no
## verdict today. Its case is real — PartyChat's `lock` spells `world1_mordaine_defeated` unprefixed
## while the defeat bridge writes it prefixed — but that flag ALSO has an unprefixed writer, so the
## redundancy covers it. Kept deliberately and claimed accurately: it costs nothing and proves
## nothing until that redundancy goes away.
func _is_written(flag: String, w: Dictionary) -> bool:
	return w.has(flag) or w.has("cutscene_flag_" + flag) \
		or w.has(flag.trim_prefix("cutscene_flag_"))


func _quest_gate_flags() -> Dictionary:
	var out: Dictionary = {}
	for f in _json_files("res://data/quests"):
		var q = JSON.parse_string(FileAccess.get_file_as_string(f))
		if not (q is Dictionary):
			continue
		var qid: String = str(q.get("id", f))
		if str(q.get("prereq_flag", "")) != "":
			out[str(q["prereq_flag"])] = "%s prereq_flag" % qid
		for o in q.get("objectives", []):
			if o is Dictionary and str(o.get("required_flag", "")) != "":
				out[str(o["required_flag"])] = "%s step %s required_flag" % [qid, o.get("step", "?")]
	return out


func _chapter_title_flags() -> Dictionary:
	var out: Dictionary = {}
	for row in ChapterTitles.CHAPTERS:
		if row is Dictionary and str(row.get("flag", "")) != "":
			out[str(row["flag"])] = "chapter card W%s ch%s %s" \
				% [row.get("world", "?"), row.get("chapter", "?"), row.get("title", "?")]
	return out


func _world_map_flags() -> Dictionary:
	var out: Dictionary = {}
	for world in WorldMapMenu.PROGRESS_FLAGS:
		for flag in WorldMapMenu.PROGRESS_FLAGS[world]:
			out[str(flag)] = "world map W%s progress row" % world
	return out


func _party_chat_flags() -> Dictionary:
	var out: Dictionary = {}
	for chat_id in PARTY_CHAT.REGISTRY:
		var chat = PARTY_CHAT.REGISTRY[chat_id]
		if not (chat is Dictionary):
			continue
		for key in ["unlock", "lock"]:
			for flag in chat.get(key, []):
				out[str(flag)] = "party chat %s %s" % [chat_id, key]
	return out


func _dead(readers: Dictionary) -> Dictionary:
	var w := _writers()
	var dead: Dictionary = {}
	for flag in readers:
		if not _is_written(flag, w):
			dead[flag] = readers[flag]
	return dead


## CONTROL, BOTH DIRECTIONS, ON PLANTED TEXT. The negative is the rule this file replaced the bare
## literal with; the positive is what stops an always-empty extractor from satisfying the negative.
## Planted rather than sampled, and the reason is itself a measurement: src DOES hold one commented
## write shape — `GameLoop.gd`'s note on `_KNOWN_DEFEAT_CUTSCENE_FLAGS` reads
## `defeat_cutscene_flags = ["cutscene_flag_X"]` — but its placeholder is UPPERCASE, so the
## lowercase-only flag class excludes it for a reason that has nothing to do with the comment rule.
## Sampling it would prove the wrong clause; planted text proves the one this file relies on.
func test_control_a_commented_write_is_not_a_writer() -> void:
	var seen: Dictionary = {}
	_writers_in_text("\tvar x := 1  # game_constants[\"planted_comment_flag\"] = true\n", seen)
	_writers_in_text("\t## set_story_flag(\"planted_docstring_flag\")\n", seen)
	assert_false(seen.has("planted_comment_flag"),
		"a write shape inside a trailing comment registered as a writer — prose about the code is "
		+ "exactly how 121 flags once had a 'writer' that was really a read")
	assert_false(seen.has("planted_docstring_flag"),
		"a write shape inside a `##` docstring registered as a writer")
	var live: Dictionary = {}
	_writers_in_text("\tgame_constants[\"planted_code_flag\"] = true\n", live)
	_writers_in_text("\tset_story_flag(\"planted_call_flag\")\n", live)
	assert_true(live.has("planted_code_flag"),
		"the extractor missed an UNcommented assignment, so the two asserts above pass by matching "
		+ "nothing at all and this control is vacuous")
	assert_true(live.has("planted_call_flag"), "the extractor missed an UNcommented call")


## A write form whose pattern dies contributes 0 and makes every arm below GREENER. Nothing else in
## this file can see that, so the per-form count is asserted rather than merely computed.
func test_control_every_modelled_write_form_still_contributes() -> void:
	var w := _writers()
	var per_form: Dictionary = {}
	for flag in w:
		for form in w[flag]:
			per_form[form] = int(per_form.get(form, 0)) + 1
	gut.p("writer forms: %s · distinct flags written: %d" % [str(per_form), w.size()])
	for form in MODELLED_FORMS:
		assert_gt(int(per_form.get(form, 0)), 0,
			"write form '%s' contributed NOTHING — its pattern no longer matches, or the form has " % form
			+ "left the project. Either way every reader arm below is quietly greener. Fix the "
			+ "pattern, or delete the form from MODELLED_FORMS and say which commit retired it")
	assert_gte(w.size(), TOTAL_WRITER_FLOOR,
		"only %d distinct flags have a writer, floor %d — the per-form arms tolerate a MIGRATION "
		% [w.size(), TOTAL_WRITER_FLOOR]
		+ "between forms, so this total is what catches a broad breakage none of them sees")


## The readers are the population every arm divides. An empty parse passes by judging nothing.
func test_control_every_reader_surface_resolves() -> void:
	var counts := {
		"quest": _quest_gate_flags().size(),
		"chapter_title": _chapter_title_flags().size(),
		"world_map": _world_map_flags().size(),
		"party_chat": _party_chat_flags().size(),
	}
	gut.p("reader surfaces: %s" % str(counts))
	for surface in READER_FLOORS:
		assert_gte(int(counts[surface]), int(READER_FLOORS[surface]),
			"reader surface '%s' resolved %d flags, floor %d — its arm is vacuous below this"
			% [surface, int(counts[surface]), int(READER_FLOORS[surface])])


## THE ARM THE OLD INSTRUMENT COULD NOT HAVE HAD: a flag whose EVERY src occurrence is a read must
## not be in the writer set. Today that is 6 flags — five composed `spotlight_unlocked_<job>` keys
## read in GameLoop's story gates, plus `cutscene_flag_fool_card_marks` — and the retired bare
## literal counted all of them as written on the strength of the literal alone.
##
## ⛔ THE FIRST VERSION OF THIS ARM COULD NOT FAIL, AND IT WAS FOUND BY TRYING TO WRITE ITS MUTATION
## RATHER THAN BY READING IT. The population was filtered with `not _is_written(flag, w)`, and
## `_is_written` returns true when `w.has(flag)` — so membership in `read_only` ALREADY IMPLIED
## `not w.has(flag)` and the per-flag `assert_false` below was true by construction. The `>= 3`
## floor was the only live clause, and the loop read like the real assertion. It is the evening's
## own shape (@cowir-adhoc's blind pin, @cowir-deploy's builtin pause) in the guard written to
## expose that shape. 🔑 THE REPAIR IS THAT THE POPULATION COMES FROM OCCURRENCE SHAPE ALONE — every
## quoted occurrence of the flag, versus the subset preceded by `.get(` / `.has(` — with no
## reference to the writer set, so the assert is free to disagree with it.
func test_a_literal_mention_is_not_counted_as_a_write() -> void:
	var w := _writers()
	var rx_all := RegEx.create_from_string("\"(cutscene_flag_[a-z0-9_]+)\"")
	var rx_read := RegEx.create_from_string("(?:\\.get\\(|\\.has\\()\\s*\"(cutscene_flag_[a-z0-9_]+)\"")
	var total: Dictionary = {}
	var reads: Dictionary = {}
	for path in _gd_files():
		var text: String = FileAccess.get_file_as_string(path)
		for m in rx_all.search_all(text):
			if not _is_commented(text, m.get_start()):
				total[m.get_string(1)] = int(total.get(m.get_string(1), 0)) + 1
		for m in rx_read.search_all(text):
			if not _is_commented(text, m.get_start()):
				reads[m.get_string(1)] = int(reads.get(m.get_string(1), 0)) + 1
	var read_only: Array[String] = []
	for flag in total:
		if int(total[flag]) > 0 and int(reads.get(flag, 0)) == int(total[flag]):
			read_only.append(str(flag))
	gut.p("read-only flag literals in src: %d of %d distinct" % [read_only.size(), total.size()])
	assert_gte(read_only.size(), 3,
		"no flag in src is read as a literal and never written in one — so this arm judges nobody. "
		+ "Re-derive the population from occurrence shape before trusting its green")
	for flag in read_only:
		assert_false(w.has(flag),
			"'%s' appears in src ONLY inside a .get()/.has() READ and is in the writer set — a " % flag
			+ "mention is being counted as a write, which is how 121 flags once had a 'writer'")


func test_every_quest_gate_flag_has_a_writer() -> void:
	var dead := _dead(_quest_gate_flags())
	assert_eq(dead.size(), 0,
		"quest gate flags with NO writer anywhere (flag → where it is read): %s — such a quest can "
		% str(dead) + "be offered and accepted and then never advances, and there is no abandon")


## A chapter card is the player's own record of where they are. W3 ch4 "Tempo Falls" is written by
## SteampunkMechanism's `defeat_cutscene_flags` bridge — a form this file did not model until today,
## so this surface had no guard AND the only write reaching it was invisible to the guard it lacked.
func test_every_chapter_title_flag_has_a_writer() -> void:
	var dead := _dead(_chapter_title_flags())
	assert_eq(dead.size(), 0,
		"chapter title cards whose flag NOTHING writes: %s — the card never shows" % str(dead))


func test_every_world_map_progress_flag_has_a_writer() -> void:
	var dead := _dead(_world_map_flags())
	assert_eq(dead.size(), 0,
		"world-map progress rows whose flag NOTHING writes: %s — the row never lights" % str(dead))


func test_every_party_chat_gate_flag_has_a_writer() -> void:
	var dead := _dead(_party_chat_flags())
	assert_eq(dead.size(), 0,
		"party chats gated on a flag NOTHING writes: %s — an `unlock` miss hides the chat forever, "
		% str(dead) + "a `lock` miss leaves it offered past the point it was meant to retire")
