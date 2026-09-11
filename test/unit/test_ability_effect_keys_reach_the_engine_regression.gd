extends GutTest

## GLACIUS CASTS FROST ARMOR AND NOTHING HAPPENS TO THE PARTY.
##
## 2026-09-11. `frost_armor` ships this description: *"Encases itself in frost,
## raising defense and damaging attackers."* Its `effect` is `defense_up` — a defence
## buff and nothing else — and the key that carries the other half,
## `reflect_damage_element: "ice"`, is read by no code in the game.
##
## It is not latent. Glacius, the Frozen Sovereign owns it, and BattleManager's
## `defense_boost` intent selects it deliberately (`effect == "defense_up"`), so the
## cast happens in the fight. The engine HAS the mechanic — `add_status("reflect", …)`
## at BattleManager:5699, consumed at 4356 and 4779, and four other abilities use it
## (magic_reflect, port_block, prismatic_reflect, reflect_shield). Frost Armor is the
## one that declares reflection in data and never asks for it.
##
## 🔑 THE DISCRIMINATOR THIS FILE IS BUILT ON, because "unread key" alone is too blunt
## a subject — @cowir-sfx's line, earned by nearly filing 313 live manifest entries as
## orphaned: an unread key is only a defect when it STATES SOMETHING THAT HAS NOT
## HAPPENED. The five unread keys in abilities.json split cleanly on that test:
##
##   REDUNDANT   damage_reduction on `default` — take_damage:315 hardcodes `* 0.5` for
##               is_defending and the data says 0.5, so they agree TODAY by coincidence
##               of both being 0.5. Editing the data would not move the game.
##   REDUNDANT   next_crit on shadow_step — the behaviour is real, it just lives on
##               the STATUS, not the key. _calculate_crit_chance returns 1.0 for
##               has_status("shadow_step"). Nothing is missing.
##   DEFERRED    bp_gain, bp_cost — the BP bank is unbuilt, and BattleManager says so
##               in a comment at the default_stance arm: "not implemented yet … when
##               BP lands, this arm grows by one line." A recorded decision.
##   MISSING     reflect_damage_element — the description promises it, the engine can
##               do it, and nothing connects them. This is the only one that is a bug.
##
## Which way to settle it is a BALANCE call and deliberately not made here: wiring the
## reflection makes a shipped boss harder; trimming the description makes it weaker
## than authored. Both are one edit. The pin holds the state until someone chooses.

## ⚠️ WHAT THIS CHECK CANNOT SEE — and it caught me writing the file. It matches a key
## by SPELLING anywhere in src/, so a key read for a DIFFERENT SUBJECT counts as
## consumed. `evasion_bonus` is the live instance: abilities author it, and the only
## reader is `_sum_equipment_special_effect(target, "evasion_bonus")` — EQUIPMENT
## special_effects, a different corpus that happens to share the word. I listed it as
## unread on that reasoning and this file's own ratchet corrected me within a minute.
## So "consumed" here means "the string is read somewhere in the engine", never "read
## for abilities". Wrong symbol, same spelling — @cowir-ai's trap, in the guard written
## while reading about it.

const ABILITIES := "res://data/abilities.json"
const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"

## ability effect key -> why it is not read. Every entry is a claim about the ENGINE,
## so each has to be false before its line can be deleted.
##   grows   -> a new ability shipped with an effect key nothing consumes
##   shrinks -> someone wired one; delete the line
const UNREAD_EFFECT_KEYS := {
	"damage_reduction": "REDUNDANT but DIVERGENCE-PRONE — Combatant.take_damage:315 hardcodes `* 0.5` for is_defending, which happens to equal default's authored 0.5. Edit the data and nothing moves",
	"next_crit": "REDUNDANT — shadow_step's crit is guaranteed via has_status('shadow_step') in _calculate_crit_chance",
	"bp_gain": "DEFERRED — the BP bank is unbuilt; BattleManager's default_stance arm records the decision",
	"bp_cost": "DEFERRED — same BP bank",
	"reflect_damage_element": "MISSING — frost_armor's shipped description promises it, the reflect status exists, nothing connects them. A balance call, not an oversight to silently fix",
}

## Keys that are structure rather than effect, and are read by the loader or by name.
const NON_EFFECT_KEYS := ["id"]

var _cache: Dictionary = {}


func _abilities() -> Dictionary:
	if _cache.has("a"):
		return _cache["a"]
	var raw: String = FileAccess.get_file_as_string(ABILITIES)
	assert_ne(raw, "", "abilities.json must be readable")
	var parsed: Variant = JSON.parse_string(raw)
	var root: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	var inner: Variant = root.get("abilities", root)
	var out: Dictionary = inner as Dictionary if inner is Dictionary else {}
	_cache["a"] = out
	return out


func _src_blob() -> String:
	if _cache.has("src"):
		return _cache["src"]
	# The consumer corpus: every .gd under src/. A key read anywhere in the engine is
	# read. Walking the tree rather than naming files, so a consumer that moves house
	# does not turn into a false finding.
	var blob: String = ""
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name: String = dir.get_next()
		while name != "":
			var full: String = dir_path + "/" + name
			if dir.current_is_dir():
				if not name.begins_with("."):
					stack.append(full)
			elif name.ends_with(".gd"):
				blob += FileAccess.get_file_as_string(full)
			name = dir.get_next()
		dir.list_dir_end()
	_cache["src"] = blob
	return blob


## PREMISE. Both corpora have to be real, or every arm below passes on nothing.
func test_premise_both_corpora_loaded() -> void:
	assert_gt(_abilities().size(), 200,
		"only %d abilities parsed — the walk is not reading abilities.json" % _abilities().size())
	assert_gt(_src_blob().length(), 1000000,
		"the src/ walk collected only %d chars — a key would read as unconsumed because the corpus is missing, not because the engine ignores it" % _src_blob().length())


## CONTROL, both directions, on keys whose status is not in dispute.
func test_the_consumption_check_answers_both_ways() -> void:
	var blob: String = _src_blob()
	assert_true(blob.contains("\"stat_modifier\""),
		"CONTROL: stat_modifier is read all over BattleManager; if this reads as unconsumed the corpus walk is broken and every finding below is noise")
	assert_false(blob.contains("\"zzz_not_a_real_ability_key\""),
		"CONTROL: a fabricated key must read as unconsumed, or the check cannot return a positive")


## THE RATCHET, bidirectional over every key authored on an ability.
func test_every_authored_ability_key_is_consumed_or_named() -> void:
	var blob: String = _src_blob()
	var counts: Dictionary = {}
	for aid in _abilities().keys():
		var a: Variant = _abilities()[aid]
		if not (a is Dictionary):
			continue
		for k in (a as Dictionary).keys():
			var key: String = str(k)
			if NON_EFFECT_KEYS.has(key):
				continue
			counts[key] = int(counts.get(key, 0)) + 1

	var unconsumed: Array[String] = []
	var newly_consumed: Array[String] = []
	for k in counts.keys():
		var key: String = str(k)
		var is_read: bool = blob.contains("\"%s\"" % key)
		if is_read and UNREAD_EFFECT_KEYS.has(key):
			newly_consumed.append(key)
		elif not is_read and not UNREAD_EFFECT_KEYS.has(key):
			unconsumed.append("%s (on %d abilities)" % [key, int(counts[k])])
	unconsumed.sort()

	assert_eq(unconsumed.size(), 0,
		"an ability authors an effect key the engine never reads: %s — wire it, or add it to UNREAD_EFFECT_KEYS saying whether it is REDUNDANT, DEFERRED or MISSING" % ", ".join(unconsumed))
	assert_eq(newly_consumed.size(), 0,
		"GOOD NEWS, STALE LIST: %s is now read in src/. Delete the key(s) from UNREAD_EFFECT_KEYS so this file stops claiming the engine ignores them." % ", ".join(newly_consumed))


## The one that is a bug rather than bookkeeping, pinned by NAME so a reader of the
## debt list above cannot mistake it for the redundant ones. Fails when frost_armor
## gains a reflecting effect — at which point the description is finally true and the
## UNREAD_EFFECT_KEYS entry has to go with it.
func test_frost_armor_still_promises_a_reflection_it_does_not_perform() -> void:
	var a: Variant = _abilities().get("frost_armor", null)
	if not (a is Dictionary):
		pending("frost_armor is not in abilities.json")
		return
	var ability: Dictionary = a as Dictionary

	assert_eq(str(ability.get("reflect_damage_element", "")), "ice",
		"fixture drift: frost_armor should still declare reflect_damage_element")
	assert_true(str(ability.get("description", "")).to_lower().contains("damaging attackers"),
		"fixture drift: the description this file is about has changed — re-read it before trusting the verdict below")
	assert_eq(str(ability.get("effect", "")), "defense_up",
		"GOOD NEWS or BAD: frost_armor's effect is no longer defense_up. If it now reflects, delete this arm and the reflect_damage_element entry above. If it changed for another reason, re-derive the verdict.")

	# The engine's reflect vocabulary, named so this arm cannot pass by the mechanic
	# quietly disappearing instead of frost_armor gaining it.
	var blob: String = _src_blob()
	assert_true(blob.contains("\"reflect\""),
		"the reflect status is gone from the engine — frost_armor's missing half is now missing for everyone, which is a different and larger finding")
