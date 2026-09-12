extends GutTest

## A boss's authored personality is reached by a STRING MATCH across two files,
## and nothing checks that the string lands.
##
## `BossDialogue` is keyed by persona id. The runtime resolves that id two ways
## (`BattleManager:7768`, `BattleCommandMenu:463`):
##
##     enemy.get_meta("llm_persona_id")   set from monsters.json's
##                                        boss_llm_persona_id at spawn
##                                        (BattleEnemySpawner:445)
##     else monster_type                  the monsters.json key itself
##
## So Pyrroth's persona lives under `pyrroth` while the monster is `fire_dragon`,
## bridged by one field in monsters.json. Every W1 dragon works this way, and I
## spent five minutes this hour convinced they were all broken — the bridge is
## real, it is just in the data rather than in the dungeon script, and nothing
## anywhere asserts it lands.
##
## WHAT A MISS COSTS, and it is silent in both directions:
##
##     a declaration pointing at no entry   has_entry() is false, so the Address
##                                          command never appears, no jailbreak,
##                                          no phase line — and nothing errors
##     an entry nothing declares            authored persona, verbs and
##                                          vulnerabilities that never load
##
## Pyrroth, Glacius, Voltharion and Umbraxis carry 9 of the 15 authored jailbreak
## vulnerabilities between them. A renamed key or a typo'd field takes all of it
## dark with a green suite.
##
## ⚠️ NO CURRENT OCCUPANT — all 11 links resolve today, measured. This is a
## ratchet on a seam that is about to be edited: the three finale bosses
## (the_coordinator / the_regulator / the_director) have art on main and their
## monsters.json rows pending a balance ruling, and whoever writes those rows
## will be one typo away from believing they wired dialogue that never loads.

const BOSS_DIALOGUE_PATH := "res://data/boss_dialogue.json"
const MONSTERS_PATH := "res://data/monsters.json"
const DUNGEON_DIR := "res://src/maps/dungeons"


func _json(path: String) -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(path)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed as Dictionary if parsed is Dictionary else {}


## Persona ids the data declares: one field per boss monster.
func _declared_by_monsters() -> Dictionary:
	var out: Dictionary = {}
	for mid in _json(MONSTERS_PATH):
		var m: Variant = _json(MONSTERS_PATH)[mid]
		if not (m is Dictionary):
			continue
		var pid: String = str((m as Dictionary).get("boss_llm_persona_id", "")).strip_edges()
		if pid != "":
			out[pid] = "monsters.json/%s" % str(mid)
	return out


## Persona ids a dungeon script declares, e.g. CastleHarmonia's chancellor_mordaine.
func _declared_by_dungeons() -> Dictionary:
	var out: Dictionary = {}
	var d := DirAccess.open(DUNGEON_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if f.ends_with(".gd"):
			var src: String = FileAccess.get_file_as_string("%s/%s" % [DUNGEON_DIR, f])
			var at: int = src.find("boss_llm_persona_id = \"")
			while at != -1:
				var start: int = at + "boss_llm_persona_id = \"".length()
				var close: int = src.find("\"", start)
				if close > start:
					var pid: String = src.substr(start, close - start)
					if pid != "":
						out[pid] = f
				at = src.find("boss_llm_persona_id = \"", at + 1)
		f = d.get_next()
	d.list_dir_end()
	return out


func _entries() -> Array[String]:
	var out: Array[String] = []
	for k in _json(BOSS_DIALOGUE_PATH):
		var key: String = str(k)
		if key.begins_with("_"):
			continue
		if _json(BOSS_DIALOGUE_PATH)[k] is Dictionary:
			out.append(key)
	return out


# ── forward: every declaration must land ──────────────────────────────────────

func test_every_declared_persona_id_has_an_entry() -> void:
	## A typo here is silent: has_entry() returns false, the Address command does
	## not appear, and nothing errors.
	var declared: Dictionary = _declared_by_monsters()
	for pid in _declared_by_dungeons():
		declared[pid] = _declared_by_dungeons()[pid]
	assert_gte(declared.size(), 4,
		"CONTROL: only %d persona declarations derived — the scan is broken, not the data" % declared.size())
	var entries: Array[String] = _entries()
	var unresolved: Array[String] = []
	for pid in declared:
		if not entries.has(str(pid)):
			unresolved.append("%s (declared by %s)" % [str(pid), str(declared[pid])])
	assert_eq(unresolved, ([] as Array[String]),
		("these boss_llm_persona_id values name no entry in data/boss_dialogue.json: %s. "
		+ "Fix: add the entry under that exact key, or correct the declaring field to an "
		+ "existing key. Until then that boss has no Address command, no jailbreak and no "
		+ "phase lines, and nothing errors.") % ", ".join(unresolved))


# ── reverse: every authored entry must be reachable ───────────────────────────

func test_every_authored_persona_is_reachable() -> void:
	## The other direction, and it is the one I mis-diagnosed this hour: an entry
	## is reached either because a monster DECLARES it or because the entry key IS
	## the monster id. Neither, and the authoring is dead weight.
	var monsters: Dictionary = _json(MONSTERS_PATH)
	var declared: Dictionary = _declared_by_monsters()
	for pid in _declared_by_dungeons():
		declared[pid] = _declared_by_dungeons()[pid]
	var entries: Array[String] = _entries()
	assert_gte(entries.size(), 5,
		"CONTROL: only %d persona entries parsed — the reader is broken" % entries.size())
	var orphaned: Array[String] = []
	for pid in entries:
		if monsters.has(pid) or declared.has(pid):
			continue
		orphaned.append(pid)
	assert_eq(orphaned, ([] as Array[String]),
		("these boss_dialogue.json entries are reached by nothing: %s. Fix: either name the "
		+ "key on a monster's boss_llm_persona_id field (how the dragons reach theirs), or "
		+ "make the key equal a monsters.json id (how the duel bosses reach theirs), or "
		+ "delete the entry. Authored verbs and jailbreak vulnerabilities do not load "
		+ "without one of those.") % ", ".join(orphaned))


# ── controls ──────────────────────────────────────────────────────────────────

func test_both_bridges_are_actually_in_use() -> void:
	## Each arm above is only meaningful while both routes have occupants. If a
	## route empties, the arm defending it becomes vacuous rather than satisfied.
	var monsters: Dictionary = _json(MONSTERS_PATH)
	var via_field: int = _declared_by_monsters().size()
	var via_key: int = 0
	for pid in _entries():
		if monsters.has(pid):
			via_key += 1
	assert_gt(via_field, 0, "no monster declares boss_llm_persona_id — the field route is empty")
	assert_gt(via_key, 0, "no entry key is a monster id — the direct route is empty")


func test_a_fabricated_id_would_be_caught() -> void:
	## POSITIVE CONTROL on the matcher itself: the two zeros above are worth
	## nothing unless the same comparison reports a miss on an id that is absent.
	assert_false(_entries().has("zzz_not_a_real_persona"),
		"CONTROL: the entry list must not contain a fabricated id")
	assert_false(_declared_by_monsters().has("zzz_not_a_real_persona"),
		"CONTROL: the declaration scan must not invent one either")


func test_the_data_files_really_parsed() -> void:
	## CONTROL, and the reason it is here: an unparsed file yields {} and both
	## arms above pass on an empty corpus — the same clean green as correct data.
	assert_gt(_json(MONSTERS_PATH).size(), 50, "monsters.json must parse to a populated dict")
	assert_gt(_json(BOSS_DIALOGUE_PATH).size(), 5, "boss_dialogue.json must parse to a populated dict")
	assert_gt(_declared_by_dungeons().size(), 0, "the dungeon scan must find at least one declaration")
