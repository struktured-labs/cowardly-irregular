extends GutTest

## A world variant whose own OGG sits on disk but which names a DIFFERENT file is either a
## registration slip (silent authored asset) or a deliberate repoint. w2_ability_heal and
## w3_ability_heal are the deliberate case: struktured rejected both for brightness on 2026-09-10
## and they were pointed back at the W1 cue, with the measurement recorded in their own prompt.
## So this cannot assert "always names its own file" — 34 of 36 do and two must not.
## It requires the EXPLANATION instead: you can't silence this green, only explain it green.

const SFX_DIR := "res://assets/audio/sfx/"
## The deliverable — a repoint has to say why, so a SILENT one is what reds.
const REPOINT_MARKER := "REPOINTED"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _variant_keys(sm: Node) -> Array:
	var out: Array = []
	for k in sm._sfx_manifest.keys():
		var s: String = str(k)
		if s.length() > 3 and s[0] == "w" and s[1] >= "2" and s[1] <= "6" and s[2] == "_":
			out.append(s)
	out.sort()
	return out


func test_a_repointed_world_variant_records_why() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var checked := 0
	var repointed := 0
	for key in _variant_keys(sm):
		var own: String = SFX_DIR + str(key) + ".ogg"
		if not ResourceLoader.exists(own):
			continue
		checked += 1
		var entry: Dictionary = sm._sfx_manifest[str(key)]
		var named: String = str(entry.get("file", ""))
		if named.get_file() == str(key) + ".ogg":
			continue
		repointed += 1
		assert_true(str(entry.get("prompt", "")).contains(REPOINT_MARKER),
			"%s names %s with its own variant on disk and no recorded reason — a silent repoint is indistinguishable from a registration slip" % [str(key), named.get_file()])
	assert_gt(checked, 0, "CONTROL: no world variant has its own file on disk, so this arm checked nothing")
	assert_gt(repointed, 0, "CONTROL: nothing is repointed, so the explanation requirement was never exercised")


func test_the_heal_repoint_is_still_the_recorded_decision() -> void:
	# Pins the 2026-09-10 ruling itself: these two play the W1 cue BY DECISION. If someone
	# re-lands the bright variants, this reds and points at the measurement that rejected them.
	var sm: Node = _sm()
	if sm == null:
		return
	for key in ["w2_ability_heal", "w3_ability_heal"]:
		assert_true(sm._sfx_manifest.has(key), "CONTROL: %s must exist for this arm to mean anything" % key)
		if not sm._sfx_manifest.has(key):
			continue
		var named: String = str(sm._sfx_manifest[key].get("file", ""))
		assert_eq(named.get_file(), "ability_heal.ogg",
			"%s now names %s — struktured rejected the bright variant on 2026-09-10; re-land it only once it measures warm" % [key, named.get_file()])


func test_every_world_still_resolves_a_heal() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	var restore = sm._current_area
	for area in ["overworld_medieval", "suburban_overworld", "steampunk_overworld"]:
		sm._current_area = area
		sm._sfx_cooldowns.clear()
		sm._ability_player.stream = null
		sm.play_ability("cure")
		assert_not_null(sm._ability_player.stream, "no heal cue resolved at all in %s" % area)
	sm._current_area = restore


func test_what_a_world_plays_is_what_its_entry_names() -> void:
	# The resolution path must honour the manifest, whichever file the manifest names.
	var sm: Node = _sm()
	if sm == null:
		return
	var heal_ability := ""
	for ability_id in sm._ability_sounds.keys():
		if str(sm._ability_sounds[ability_id]) == "ability_heal":
			heal_ability = str(ability_id)
			break
	assert_ne(heal_ability, "", "CONTROL: no ability maps to ability_heal, so this arm cannot fire")
	if heal_ability == "":
		return
	var restore = sm._current_area
	sm._current_area = "suburban_overworld"
	sm._sfx_cooldowns.clear()
	sm._ability_player.stream = null
	sm.play_ability(heal_ability)
	var played: String = str(sm._ability_player.stream.resource_path) if sm._ability_player.stream else ""
	sm._current_area = restore
	var declared: String = str(sm._sfx_manifest["w2_ability_heal"].get("file", "")).get_file()
	assert_eq(played.get_file(), declared,
		"W2 played %s while its entry names %s — the lookup and the manifest disagree" % [played.get_file(), declared])


func test_no_manifest_entry_names_a_file_that_is_not_there() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	# FLOOR FIRST, so a void corpus blames itself rather than reading as clean: this arm asserts an
	# ABSENCE, and an empty manifest produces the same empty `missing` list as a correct one.
	assert_gt(sm._sfx_manifest.size(), 0, "VOID, not clean: the sfx manifest read back 0 keys")
	assert_true(sm._sfx_manifest.has("attack_hit"), "VOID, not clean: the manifest lacks a key every build has")
	var missing: Array = []
	for key in sm._sfx_manifest.keys():
		var f: String = str(sm._sfx_manifest[key].get("file", ""))
		if f == "":
			continue
		var path: String = f if f.begins_with("res://") else "res://" + f
		if not ResourceLoader.exists(path):
			missing.append("%s -> %s" % [str(key), f])
	assert_eq(missing.size(), 0, "manifest keys name files that are not on disk: %s" % str(missing))


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## A direct `sm._x` on a RENAMED member raises at runtime and ABORTS the arm. An abort after
	## that arm's last assert scores PASSING — measured 2026-09-16: renaming the dedicated voice
	## this file exists to defend gave EXIT=0, Failing 0, NO Risky line, and moved only the assert
	## count. `get()` returns null for an absent name instead of raising, so the rename fails loudly
	## here and names itself before any other arm gets the chance to go quiet.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## Methods are NOT properties: get() returns null for a method name, so the loop below cannot
	## see a renamed METHOD. has_method ANSWERS instead of raising, same reason.
	## ⚠️ BOTH LISTS ARE A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT a
	## live derivation. Add a new sm. reach to this file and it is NOT covered until you add it here.
	## A runtime derivation would self-maintain but would read this arm's own body as corpus
	## (cowir-sprites' tautology class), needing cowir-ai's bare-Object exclusion to stay honest.
	## Convert it the next time this file gains a reach; until then the list is correct by being fresh.
	## ⚠️ IF YOU REGENERATE THIS LIST, STRIP COMMENTS FIRST (test/unit/helpers/gd_source.gd). The
	## generator that produced it read RAW source, so a trailing `# was sm.old_name()` — precisely
	## what a rename commit writes — becomes a listed member that never existed, and the floor then
	## REDS ON CORRECT CODE. cowir-music demonstrated that false red in their own floors 2026-09-16.
	## This list is ghost-free only because no such comment existed when it was generated.
	for method_name in ["play_ability"]:
		assert_true(sm.has_method(method_name),
			"SoundManager has no method %s — this file CALLS it, and whether that shows as Risky or as a silent pass is decided by arm ORDER, not by care" % method_name)
	## ⚠️ get() CANNOT DISTINGUISH ABSENT FROM LEGITIMATELY NULL (@cowir-sprites): it returns null
	## for both. Every member below is a player, a Dictionary or a String — none is ever null once
	## _ready has run — so the check is sound HERE. If you add a nullable member to this list
	## (_crossfade_tween and the other _*_tween members are EXAMPLES, not an exhaustive list — check
	## the declaration), switch to get_property_list(), which answers about existence rather than value.
	for member_name in ["_ability_player", "_ability_sounds", "_current_area", "_sfx_cooldowns", "_sfx_manifest"]:
		## assert_true on an explicit `!= null`: assert_ne deep-compares, and three of these members
		## are Dictionaries, which it refuses with "Only Arrays and Dictionaries are supported".
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly, and a rename would abort its arms SILENTLY" % member_name)
