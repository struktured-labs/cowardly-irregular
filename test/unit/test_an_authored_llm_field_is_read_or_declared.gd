extends GutTest

## CLAUDE.md's precedence rule, applied to this lane's authored data: a field is READ
## by the runtime, or DECLARED inert with a note naming who holds the call. You cannot
## silence it green, only explain it green.
##
## Censused 2026-09-16 over every .gd under src/ (284 files). Two content blocks in
## boss_dialogue.json have no reader and BOTH were already declared in prose — this
## adds the ratchet that prose cannot carry:
##
##   mage_prismatic_construct.aspect_labels   on-sprite aspect overlay; its own _comment
##                                            names cowir-main (engine hook) and
##                                            cowir-sprites (font/placement). The aspect
##                                            cue itself DOES reach the player, through
##                                            the shift_aspect / punish_mismatch taunts.
##   the_calibrant.p3_mirror_barks            _META_p3_mirror: the P3 mirror is a MECHANIC
##                                            parked with cowir-battle; the pools "ship
##                                            here unused until that phase exists".
##
## Three arms matter more than the census: a SIXTH unwired key reds instead of joining a
## pile; a declared-inert key the runtime LATER starts reading reds (a declaration that
## outlives its fact is worse than none — cowir-sprites' arm, b058b6ac); and dynamically
## built keys are excused by the READER's evidence, never by an allowlist.

const BOSS_DATA := "res://data/boss_dialogue.json"
const JOB_PERSONAS := "res://data/job_personas.json"
const NPC_PERSONAS := "res://data/cutscenes/npc_showcase_personas.json"
const CONVERSATION_REWARDS := "res://data/conversation_rewards.json"

## EVERY authored file this lane's code loads. The first version of this census listed
## three and read as complete — `conversation_rewards.json` was missed, and a census with
## a hole reads exactly like a census without one (@cowir-autogrind, 11607, whose filtered
## key view hid thirty). Derived below rather than trusted: an arm greps src/llm for
## res://data paths and fails if one is not in this list.
const AUTHORED_FILES := [BOSS_DATA, JOB_PERSONAS, NPC_PERSONAS, CONVERSATION_REWARDS]

## Keys whose CHILDREN are entry ids rather than fields, at any depth.
const ID_MAP_KEYS := ["bosses", "jobs", "npcs", "by_npc"]

## Files whose ROOT is itself an id map — boss ids and npc display names sit at the top
## level, beside prose keys. Measured from the four files rather than assumed: the other
## two open with sections (`jobs`, `default`/`by_npc`).
const ROOT_IS_ID_MAP := [BOSS_DATA, NPC_PERSONAS]

## Keys with no literal mention in src/, each excused by the code that BUILDS the name.
## If that construction site goes, the excuse goes with it.
const DYNAMIC_READERS := {
	"phase_": {"file": "res://src/llm/BossDialogue.gd", "site": "\"phase_%d\" % phase"},
	"_money_pick_index": {"file": "res://src/exploration/OverworldNPC.gd",
		"site": "key_str.ends_with(\"_money_pick_index\")"},
}

## Authored, unread, and declared. The VALUE is the declaration that must survive.
const DECLARED_INERT := {
	"aspect_labels": "cowir-main wires the engine hook",
	"announce_lines": "cowir-main wires the engine hook",
	"tag": "cowir-main wires the engine hook",
	"p3_mirror_barks": "parked with cowir-battle",
	"_META_p3_mirror": "parked with cowir-battle",
	"enter": "parked with cowir-battle",
}

## Documentation keys: prose for the next reader, never runtime.
const PROSE_PREFIXES := ["_comment", "_note", "_META_", "_fallbacks_note"]

var _corpus: String = ""
var _corpus_files: int = 0


func before_each() -> void:
	if not _corpus.is_empty():
		return
	var parts: PackedStringArray = PackedStringArray()
	_walk("res://src", parts)
	_corpus = "\n".join(parts)


func _walk(dir_path: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_walk(full, out)
		elif name.ends_with(".gd"):
			out.append(FileAccess.get_file_as_string(full))
			_corpus_files += 1
		name = d.get_next()
	d.list_dir_end()


## FIELDS only — an entry id is reached by a runtime lookup from other DATA, never by
## being named in src/. Counting ids as fields reported three spotlight-duel personas as
## unread when each is named nine times in data/.
##
## MEASURED HOLE, second version: the first form REPLACED the root with the id-map
## container it found, so every SIBLING section went uncensused — adding a field to
## conversation_rewards.json's `default` block changed nothing, because the walk had
## jumped into `by_npc` and never came back. Nothing is skipped now: the walk starts at
## the root, and id maps are stepped over WHEREVER they appear.
func _keys_of(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "CONTROL: %s must parse as an object" % path)
	var root: Dictionary = parsed as Dictionary
	var acc: Dictionary = {}
	if path in ROOT_IS_ID_MAP:
		for entry_id in root:
			if _is_prose(str(entry_id)) or str(entry_id) == "version":
				continue
			_collect(root[entry_id], acc)
	else:
		_collect(root, acc)
	return acc


func _collect(v: Variant, acc: Dictionary) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in (v as Dictionary):
				acc[str(k)] = true
				# A nested ID MAP holds entry ids, not fields — `by_npc` keys are npc ids
				# reached by a runtime lookup, exactly like the top-level boss ids. Descend
				# past them or the census reports an npc as an unread field.
				if str(k) in ID_MAP_KEYS:
					for nested_id in ((v as Dictionary)[k] as Dictionary):
						_collect(((v as Dictionary)[k] as Dictionary)[nested_id], acc)
				else:
					_collect((v as Dictionary)[k], acc)
		TYPE_ARRAY:
			for item in (v as Array):
				_collect(item, acc)


func _is_prose(key: String) -> bool:
	for p in PROSE_PREFIXES:
		if key.begins_with(p):
			return true
	return false


func _dynamic_excuse(key: String) -> String:
	for frag in DYNAMIC_READERS:
		if key.begins_with(str(frag)) or key.ends_with(str(frag)):
			return str(frag)
	return ""


func _read_literally(key: String) -> bool:
	return _corpus.find("\"%s\"" % key) != -1


# ── the corpus itself, both directions ────────────────────────────────────────

func test_the_corpus_is_real() -> void:
	assert_gt(_corpus_files, 200,
		"CONTROL: the census must read the whole src/ tree — a short corpus reports zeros on load-bearing keys")
	assert_true(_read_literally("scripted_intents"),
		"FLOOR: a key known to be read must register as read, or every zero below is noise")
	assert_false(_read_literally("zzz_not_a_real_key_1f4a"),
		"FLOOR: a fabricated key must register as unread, or nothing can ever fail")


# ── the rule ──────────────────────────────────────────────────────────────────

func test_every_authored_field_is_read_or_declared() -> void:
	var undeclared: Array = []
	for path in AUTHORED_FILES:
		for key in _keys_of(path):
			var k: String = str(key)
			if _is_prose(k) or _read_literally(k) or _dynamic_excuse(k) != "" or DECLARED_INERT.has(k):
				continue
			undeclared.append("%s:%s" % [path.get_file(), k])
	assert_eq(undeclared, [],
		"authored fields with no reader and no declaration — read them or declare who holds the call: %s"
			% str(undeclared))


func test_a_declared_field_that_became_live_must_lose_its_declaration() -> void:
	## A declaration that outlives its fact is worse than none: the next reader trusts it.
	var stale: Array = []
	for k in DECLARED_INERT:
		if _read_literally(str(k)):
			stale.append(str(k))
	assert_eq(stale, [],
		"these are declared inert and the runtime now names them — delete the declaration, or say why the hit is a coincidence: %s"
			% str(stale))


func test_each_dynamic_excuse_names_code_that_still_builds_the_key() -> void:
	## The excuse is the READER, not the key's membership in a list here.
	for frag in DYNAMIC_READERS:
		var spec: Dictionary = DYNAMIC_READERS[frag]
		var src: String = FileAccess.get_file_as_string(str(spec["file"]))
		assert_false(src.is_empty(), "CONTROL: %s must be readable" % str(spec["file"]))
		assert_true(src.find(str(spec["site"])) != -1,
			"'%s' keys are excused because %s builds them — that code is gone, so the excuse is void"
				% [str(frag), str(spec["file"]).get_file()])


func test_the_declared_blocks_still_carry_their_written_declaration() -> void:
	## The note in the DATA is what tells the next author who to ask. If it is deleted,
	## this ratchet is all that is left and it names nobody.
	var raw: String = FileAccess.get_file_as_string(BOSS_DATA)
	assert_true(raw.find("cowir-main wires the engine hook") != -1,
		"aspect_labels must keep the _comment naming who wires it")
	assert_true(raw.find("parked with cowir-battle") != -1,
		"p3_mirror_barks must keep the _META note naming where the mechanic sits")


func test_the_aspect_cue_reaches_the_player_another_way() -> void:
	## Why aspect_labels being inert is not a player-facing gap: the Construct's taunts
	## carry the colour→element cue. If those go, the overlay is the only carrier and
	## the parked feature becomes urgent.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOSS_DATA))
	var bosses: Dictionary = (parsed as Dictionary).get("bosses", parsed)
	var construct: Dictionary = bosses["mage_prismatic_construct"]
	var cue_found: bool = false
	for intent in construct.get("scripted_intents", []):
		for line in (intent as Dictionary).get("taunt_lines", []):
			var l: String = str(line).to_upper()
			if l.find("RED") != -1 and l.find("BLUE") != -1 and l.find("GOLD") != -1:
				cue_found = true
	assert_true(cue_found,
		"a taunt must still spell out the colour→element mapping, or the inert overlay is the only place it exists")


func test_every_boss_persona_entry_is_reachable() -> void:
	## The entry-id half. A persona nothing can name is authored content no player meets
	## — the shape that produced today's unreachable jailbreak and the 19 undispatched
	## cutscenes. Ids are reached from DATA (monsters.json, cutscenes) as often as from
	## src/, so both are the corpus here.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOSS_DATA))
	var bosses: Dictionary = (parsed as Dictionary).get("bosses", parsed)
	var data_corpus: String = ""
	for f in ["res://data/monsters.json", "res://data/enemy_pools.json"]:
		data_corpus += FileAccess.get_file_as_string(f)
	assert_gt(data_corpus.length(), 1000, "CONTROL: the data corpus must have loaded")
	var orphans: Array = []
	var checked: int = 0
	for boss_id in bosses:
		if not (bosses[boss_id] is Dictionary):
			continue
		checked += 1
		var id: String = str(boss_id)
		if data_corpus.find(id) == -1 and _corpus.find(id) == -1:
			orphans.append(id)
	assert_gt(checked, 5, "CONTROL: several boss personas must have been examined")
	assert_eq(orphans, [],
		"a persona nothing names is content no player can meet: %s" % str(orphans))


func test_the_census_covers_every_data_file_this_lane_loads() -> void:
	## The scope arm. A census is only as good as its file list, and a missing file is
	## invisible from the green. Derive the list from the code that loads them.
	var loaded: Dictionary = {}
	var dir := DirAccess.open("res://src/llm")
	assert_not_null(dir, "CONTROL: src/llm must be readable")
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".gd"):
			var src: String = FileAccess.get_file_as_string("res://src/llm/" + fname)
			var at: int = src.find("res://data/")
			while at != -1:
				var end: int = src.find(".json", at)
				if end == -1:
					break
				loaded[src.substr(at, end - at + 5)] = fname
				at = src.find("res://data/", end)
		fname = dir.get_next()
	dir.list_dir_end()
	assert_gt(loaded.size(), 2, "CONTROL: src/llm must load several data files, or this arm is vacuous")
	var uncensused: Array = []
	for path in loaded:
		if not (str(path) in AUTHORED_FILES):
			uncensused.append("%s (loaded by %s)" % [str(path), str(loaded[path])])
	assert_eq(uncensused, [],
		"src/llm loads these and the census does not cover them: %s" % str(uncensused))


func test_every_rewarded_npc_id_is_one_an_npc_can_have() -> void:
	## Reward entries are keyed by the id derived from the NPC's own display name. A reward
	## keyed to a name no NPC has never pays out — the unreachable-content shape, in the
	## file that hands the player items.
	##
	## MEASURED WRONG FIRST: scraping the persona file line by line flagged all three real
	## NPCs. The arm was broken, not the data. Parse the file.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONVERSATION_REWARDS))
	var by_npc: Dictionary = (parsed as Dictionary).get("by_npc", {})
	assert_gt(by_npc.size(), 0, "CONTROL: some npc must have an authored reward")
	var personas: Variant = JSON.parse_string(FileAccess.get_file_as_string(NPC_PERSONAS))
	assert_true(personas is Dictionary, "CONTROL: the persona file must parse")
	var known_ids: Dictionary = {}
	for display_name in (personas as Dictionary):
		if str(display_name).begins_with("_") or str(display_name) == "version":
			continue
		known_ids[str(display_name).to_lower().replace(" ", "_")] = true
	assert_gt(known_ids.size(), 0, "CONTROL: the persona file must name some NPCs")
	var unreachable: Array = []
	for npc_id in by_npc:
		if not known_ids.has(str(npc_id)):
			unreachable.append(str(npc_id))
	assert_eq(unreachable, [],
		"a reward keyed to an npc id nothing can produce never pays out: %s" % str(unreachable))
