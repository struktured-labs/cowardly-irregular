extends GutTest

## Referential guard on the two joins that make LLM content reachable.
##
## THE CLASS (cowir-overworld msg 3188, AreaTransition): a reference that is
## *present but unresolvable* fails differently from one that's absent. An empty
## id gets refused; a TYPO'd id sails through every check and fails silently at
## runtime. Both of my domain's joins are string-keyed and have exactly that
## shape — a boss whose persona id is misspelled simply never speaks, and an NPC
## whose name stops matching a persona key silently reverts to scripted lines.
## Nothing crashes. Nothing warns. The content is just gone.
##
## WHY NOW: five world-finale bosses and nine new monster sheets are inbound
## (cowir-main msg 3183). Every new boss with an llm_persona_id is a fresh
## instance of this join. A guard is worth more before the authoring than after.
##
## WHY NOT THE EXISTING TESTS — they cover these joins with HAND-MAINTAINED
## TABLES, and only from one side:
##   test_boss_dialogue_dragons_regression  hardcodes 4 dragon→persona pairs.
##                                          A 5th boss is unguarded.
##   test_llm_persona_persistence           asserts the JSON contains 3 names.
##                                          It does NOT assert the CODE builds
##                                          NPCs with those names — so renaming
##                                          "Scholar Milo" in HarmoniaVillage.gd
##                                          keeps that test green while Milo
##                                          silently loses his persona.
## Those tables also rot: cowir-story adds NPCs faster than anyone re-registers
## them (cowir-cutscenes msg 2936, same conclusion for theme canon). So this
## ratchet derives both directions from the data and needs no list to maintain.
##
## Shape borrowed from cowir-autogrind's roster↔reward coverage guard: pin the
## JOIN, not either side. Each side can be individually valid while the
## relationship between them is broken.

const MONSTERS_PATH: String = "res://data/monsters.json"
const BOSS_DIALOGUE_PATH: String = "res://data/boss_dialogue.json"
const PERSONA_PATH: String = "res://data/cutscenes/npc_showcase_personas.json"

## Fields a monster may use to point at a boss_dialogue section.
const PERSONA_ID_FIELDS: Array[String] = ["llm_persona_id", "boss_llm_persona_id"]


func _load(path: String) -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(path)
	assert_false(raw.is_empty(), "must be readable: %s" % path)
	var json := JSON.new()
	assert_eq(json.parse(raw), OK, "%s must parse: %s" % [path, json.get_error_message()])
	assert_true(json.data is Dictionary, "%s root must be a Dictionary" % path)
	return json.data as Dictionary


func _boss_sections() -> Array:
	var out: Array = []
	for k in _load(BOSS_DIALOGUE_PATH).keys():
		if not str(k).begins_with("_"):
			out.append(str(k))
	return out


# ── JOIN 1: monster → boss_dialogue section ─────────────────────────────────

func test_every_monster_persona_reference_resolves() -> void:
	# The typo case. A misspelled id means has_entry() returns false and the
	# boss fights in total silence — no error, no warning, no crash.
	var mons: Dictionary = _load(MONSTERS_PATH)
	var sections: Array = _boss_sections()
	var checked: int = 0
	for mid in mons.keys():
		var m: Variant = mons[mid]
		if not (m is Dictionary):
			continue
		for field in PERSONA_ID_FIELDS:
			var ref: String = str((m as Dictionary).get(field, ""))
			if ref == "":
				continue
			checked += 1
			assert_true(sections.has(ref),
				("monster '%s'.%s points at boss_dialogue section '%s', which does not exist. " +
				"This fails SILENTLY at runtime — the boss simply never speaks.") % [mid, field, ref])
	assert_gt(checked, 0, "sanity: the scan must actually find references, or it is guarding nothing")


func test_every_boss_dialogue_section_is_reachable() -> void:
	# The reverse: an authored section nothing can route to is dead content.
	# Two legitimate paths reach a section — an explicit persona-id field, or
	# the monster's own id used as the key (how the minibosses and Mordaine
	# resolve). A section matching NEITHER can never be spoken.
	var mons: Dictionary = _load(MONSTERS_PATH)
	var referenced: Dictionary = {}
	for mid in mons.keys():
		var m: Variant = mons[mid]
		if not (m is Dictionary):
			continue
		for field in PERSONA_ID_FIELDS:
			var ref: String = str((m as Dictionary).get(field, ""))
			if ref != "":
				referenced[ref] = true
	for section in _boss_sections():
		var reachable: bool = referenced.has(section) or mons.has(section)
		assert_true(reachable,
			("boss_dialogue section '%s' is unreachable: no monster names it via %s, " +
			"and no monster has that id. The dialogue is authored and can never play.")
			% [section, str(PERSONA_ID_FIELDS)])


# ── JOIN 2: dynamic NPC name → persona key ──────────────────────────────────

func _persona_keys() -> Array:
	# Entries carrying a "persona" field — skips metadata keys like "version".
	var out: Array = []
	var d: Dictionary = _load(PERSONA_PATH)
	for k in d.keys():
		var v: Variant = d[k]
		if v is Dictionary and (v as Dictionary).has("persona"):
			out.append(str(k))
	return out


func test_every_persona_key_is_constructed_somewhere_in_src() -> void:
	# THE DIRECTION THE EXISTING TEST MISSES. _setup_persona_data() looks the
	# persona up by npc_name, so the JSON key and the constructed name must
	# match EXACTLY. Renaming the NPC in code orphans the persona and the
	# JSON-side test stays green — the NPC just quietly stops being dynamic.
	var keys: Array = _persona_keys()
	assert_gt(keys.size(), 0, "sanity: persona JSON must contain entries")
	var sources: PackedStringArray = _gd_sources("res://src")
	for key in keys:
		var needle: String = '"%s"' % key
		var found: bool = false
		for path in sources:
			if FileAccess.get_file_as_string(path).find(needle) != -1:
				found = true
				break
		assert_true(found,
			("persona '%s' is authored but no source file constructs an NPC with that exact name. " +
			"Either the NPC was renamed (persona now orphaned and that NPC is silently non-dynamic) " +
			"or the persona is dead content.") % key)


func test_persona_keys_have_the_fields_the_loader_reads() -> void:
	# A key that resolves but lacks what _setup_persona_data consumes is the
	# same silence by a different route.
	#
	# DELIBERATELY NOT ASSERTING `fallbacks`. My first draft required it, and it
	# failed on Theron and Boris — correctly, because their absence is a SHIPPED
	# FIX, not an omission: `af4782eb` ("delete Theron's persona fallbacks —
	# silent override killed the rewrite") and `7b24e29a` ("Boris post-cave
	# dialogue + delete shadow fallbacks"). fallbacks[] silently outranks the
	# constructor's dialogue_lines at _ready, so authoring them re-creates the
	# override that killed a dialogue rewrite. Requiring them here would have
	# pressured the next author to reintroduce a bug two lanes removed on
	# purpose — a ratchet demanding the presence of a deleted defect. Only Milo
	# carries them, which is exactly why he needs the _fallbacks_note annotation
	# (pinned separately in test_persona_shadow_annotation_ratchet).
	var d: Dictionary = _load(PERSONA_PATH)
	for key in _persona_keys():
		var e: Dictionary = d[key]
		assert_ne(str(e.get("persona", "")).strip_edges(), "",
			"persona '%s' must be non-empty — an empty persona reaches the LLM as no character at all" % key)
		var op: Variant = e.get("openings", [])
		assert_true(op is Array and not (op as Array).is_empty(),
			"persona '%s' must carry openings — the LLM-off opening turn samples them (Wave F R3)" % key)


func _gd_sources(root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dirs: Array = [root]
	while not dirs.is_empty():
		var cur: String = str(dirs.pop_back())
		var d := DirAccess.open(cur)
		if d == null:
			continue
		d.list_dir_begin()
		var name: String = d.get_next()
		while name != "":
			if name.begins_with("."):
				name = d.get_next()
				continue
			var full: String = cur.path_join(name)
			if d.current_is_dir():
				dirs.append(full)
			elif name.ends_with(".gd"):
				out.append(full)
			name = d.get_next()
		d.list_dir_end()
	return out
