extends GutTest

## Both derivation passes pick a cue from an ORDERED list of candidates, and both gave up on the
## whole id the moment the FIRST candidate was absent from the manifest — instead of trying the
## next one, which was sitting right there and perfectly valid.
##
## ⚠️ THE PRECEDENCE ITSELF IS CORRECT AND IS NOT WHAT THIS FILE IS ABOUT. Element outranks type
## by a deliberate ruling (test_song_summon_revive_cues_regression pins it by name: summon_ifrit
## should read as fire, not as a generic summon), and _ITEM_EFFECT_SFX is priority-ordered so a
## hybrid elixir takes the MP cue over the HP one. I started by "fixing" the summon precedence
## and that regression test stopped me — the loser of a precedence is still a CANDIDATE, which is
## the whole and only defect here.
##
## Latent today: all 8 item cues and all 15 element/type cues resolve in the current manifest, so
## nothing is silent in a shipped build. It is the fallback path that was wrong, the same way the
## synth fallbacks were.

const HYBRID_ITEM := "elixir"                # heal_mp_percent then heal_hp_percent
const HYBRID_FIRST_CUE := "ability_mp_restore"
const HYBRID_SECOND_CUE := "heal"

var _saved_ability: Dictionary = {}
var _saved_item: Dictionary = {}
var _saved_manifest: Dictionary = {}


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _abilities() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	if not (parsed is Dictionary):
		return {}
	var inner: Variant = (parsed as Dictionary).get("abilities", parsed)
	return inner if inner is Dictionary else {}


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	_saved_ability = sm._ability_sounds.duplicate(true)
	_saved_item = sm._item_sounds.duplicate(true)


## Restores come FIRST and are each self-contained: these arms edit the autoload's own derivation
## tables and its static manifest, and a leak would mis-cue abilities in every file that runs after.
func after_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	for k in _saved_manifest.keys():
		sm._sfx_manifest[k] = _saved_manifest[k]
	_saved_manifest = {}
	if not _saved_ability.is_empty():
		sm._ability_sounds = _saved_ability
		_saved_ability = {}
	if not _saved_item.is_empty():
		sm._item_sounds = _saved_item
		_saved_item = {}


## Takes a cue out of the manifest for one arm, remembering it for the restore above.
func _hide_cue(sm: Node, cue: String) -> void:
	if not sm._sfx_manifest.has(cue):
		return
	_saved_manifest[cue] = (sm._sfx_manifest[cue] as Dictionary).duplicate(true)
	sm._sfx_manifest.erase(cue)


## The subject, derived: a summon that declares an element has BOTH candidates, so hiding the
## winner is the only way to observe whether the loser is still reachable.
func _elemental_summon() -> String:
	for aid in _abilities().keys():
		var e: Variant = _abilities()[aid]
		if e is Dictionary and str((e as Dictionary).get("type", "")) == "summon" \
				and str((e as Dictionary).get("element", "")).to_lower() == "fire":
			return str(aid)
	return ""


func test_an_ability_falls_through_to_its_type_cue() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var subject: String = _elemental_summon()
	assert_ne(subject, "", "CONTROL: no fire summon in abilities.json, so this arm measures nothing")
	if subject == "":
		return
	assert_eq(str(sm._ability_sounds.get(subject, "")), "ability_fire",
		"CONTROL: %s must normally take its ELEMENT cue, or there is no winner to hide" % subject)
	_hide_cue(sm, "ability_fire")
	assert_false(sm._sfx_manifest.has("ability_fire"), "CONTROL: the element cue must actually be hidden")
	sm._ability_sounds.erase(subject)
	sm._derive_ability_sounds_from_data()
	assert_eq(str(sm._ability_sounds.get(subject, "")), "ability_summon",
		"%s went silent when ability_fire was absent — it is a SUMMON and ability_summon was the next candidate" % subject)


func test_an_item_falls_through_to_its_next_effect_cue() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	assert_eq(str(sm._item_sounds.get(HYBRID_ITEM, "")), HYBRID_FIRST_CUE,
		"CONTROL: %s must normally take %s, or the fallthrough has nothing to demote from" % [HYBRID_ITEM, HYBRID_FIRST_CUE])
	_hide_cue(sm, HYBRID_FIRST_CUE)
	sm._item_sounds.erase(HYBRID_ITEM)
	sm._derive_item_sounds_from_data()
	assert_eq(str(sm._item_sounds.get(HYBRID_ITEM, "")), HYBRID_SECOND_CUE,
		"%s went silent when %s was absent — it also restores HP and %s was right there below it" % [
			HYBRID_ITEM, HYBRID_FIRST_CUE, HYBRID_SECOND_CUE])


func test_the_precedence_is_unchanged_with_every_cue_present() -> void:
	## Anti-overcorrection, and the arm I would have needed two hours ago: reordering the candidates
	## passes both arms above and silently reverses a ruling. Swept over the whole population rather
	## than the three names the sibling regression pins, so a spell added tomorrow is covered.
	var sm: Node = _sm()
	if sm == null:
		return
	var elements: Dictionary = {"fire": "ability_fire", "ice": "ability_ice", "lightning": "ability_lightning",
		"dark": "ability_dark", "holy": "ability_holy", "poison": "ability_poison",
		"earth": "ability_earth", "wind": "ability_wind"}
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/audio/SoundManager.gd")
	assert_ne(code, "", "CONTROL: SoundManager code must survive the comment strip")
	## The hand map OUTRANKS derivation by design, so only the derivation's own answers are on
	## trial. DERIVED from the source — a before_each snapshot of _ability_sounds is the fully
	## POPULATED table, hand map AND derived, and filtering on it excludes every mapped id and
	## leaves the arm unable to report an offender at all.
	var hand: Dictionary = {}
	for m in RegEx.create_from_string("_ability_sounds\\[\"(\\w+)\"\\]\\s*=").search_all(code):
		hand[m.get_string(1)] = true
	assert_gt(hand.size(), 5, "CONTROL: the hand map derived empty, so every exemption below is vacuous")
	var checked: int = 0
	var offenders: Array = []
	for aid in _abilities().keys():
		var e: Variant = _abilities()[aid]
		if not (e is Dictionary):
			continue
		var el: String = str((e as Dictionary).get("element", "")).to_lower()
		if not elements.has(el) or hand.has(str(aid)):
			continue
		var got: String = str(sm._ability_sounds.get(str(aid), ""))
		if got == "":
			continue   # a type with no _TYPE_SFX arm and no element cue never mapped; not this arm's subject
		checked += 1
		if got != str(elements[el]):
			offenders.append("%s(%s)->%s" % [aid, el, got])
	assert_gt(checked, 10, "CONTROL: too few elemental abilities swept to tell the orders apart")
	assert_eq(offenders, [],
		"%d ability(s) lost their ELEMENT cue — element outranks type by ruling, and reordering the candidates reverses it silently: %s" % [
			offenders.size(), offenders])


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ A SNAPSHOT of this file's own sm. reaches, not a live derivation.
	for m in ["_derive_ability_sounds_from_data", "_derive_item_sounds_from_data"]:
		assert_true(sm.has_method(m), "SoundManager has no method %s — this file CALLS it" % m)
	for n in ["_ability_sounds", "_item_sounds", "_sfx_manifest"]:
		assert_true(sm.get(n) != null, "SoundManager has no %s — this file reaches for it directly" % n)
	var consts: Dictionary = sm.get_script().get_script_constant_map()
	for c in ["_ELEMENT_SFX", "_TYPE_SFX", "_ITEM_EFFECT_SFX"]:
		assert_true(consts.has(c), "%s is gone — this file's arms are about the tables it defines" % c)
