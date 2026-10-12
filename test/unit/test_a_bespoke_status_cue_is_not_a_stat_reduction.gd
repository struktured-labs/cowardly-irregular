extends GutTest

## BattleScene's status dispatch has an arm that routes stat reductions to the generic `debuff` cue,
## and its own comment states the rule: "bespoke cues reserved for the scary/unique statuses". Two
## effects were in that arm with a bespoke cue authored and a file on disk, so the authored file never
## played — `pacify` (status_pacify.ogg) and `amplify_poison` (status_festered.ogg, reached through
## Combatant.STATUS_ALIASES as `festered`). Neither is a stat reduction; both are unique statuses.
##
## Found by @cowir-music while fixing an adjacent alias defect — they named fester and left the
## routing call to this lane. Auditing the whole arm instead of the one named entry found pacify too,
## which is the "a fix hides its own siblings" shape: the reported instance was not the only one.
##
## DERIVED from the manifest, not a list of the two: the defect is that an effect with its own cue sat
## in the generic arm, so the guard has to ask that question of every entry. A pair of ids would be
## green on the third.
##
## ⚠️ Ordering note: `pacify` resolves by its own name and plays as soon as this lands. `amplify_poison`
## reaches `play_status` with the EFFECT name, so it needs @cowir-music's alias resolution
## (lane/audio-hourly-1434) to arrive at status_festered; until that folds it falls to the generic blip
## — which is what it did before this change, so nothing regresses either way.

const SCENE := "res://src/battle/BattleScene.gd"
const MANIFEST := "res://data/sfx_manifest.json"


func _sfx_keys() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary and (parsed as Dictionary).has("sfx"), "manifest parses to {sfx:{...}}")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


## The effects listed in the arm that plays the generic debuff cue, read from the source.
## ⛔ ANCHORED ON THE CALL, NOT ON AN EFFECT NAME. My first version searched for the first
## `"defense_down"` in the file — which is in a status-LABEL colour table, not the match arm — so it
## parsed `Color(1.0, 0.3, 0.3)` and derived "0.3". It passed with the defect present, and the
## anti-vacuity floor did not catch it because a wrong parse still yields plenty of entries: a COUNT
## floor cannot tell a wrong corpus from a right one. The floor below checks CONTENT.
func _generic_debuff_effects() -> Array:
	var src := FileAccess.get_file_as_string(SCENE)
	assert_gt(src.length(), 0, "VOID: BattleScene.gd read empty, so nothing below is checked")
	var call_at: int = src.find("SoundManager.play_battle(\"debuff\")")
	assert_gt(call_at, -1, "the generic debuff CALL is gone — this guard cannot find its subject")
	## The arm is the nearest preceding line ending in ':' — walk back from the call.
	var head: String = src.substr(0, call_at)
	var arm_end: int = head.rfind(":\n")
	assert_gt(arm_end, -1, "no match arm found above the debuff call")
	var arm_start: int = head.rfind("\n", arm_end - 1) + 1
	var arm: String = src.substr(arm_start, arm_end - arm_start)
	var out: Array = []
	for frag in arm.split(","):
		var t: String = frag.strip_edges()
		if not t.begins_with("\""):
			continue
		t = t.trim_prefix("\"").trim_suffix("\"")
		if t != "" and t == t.to_lower() and not t.contains("("):
			out.append(t)
	return out


func test_no_effect_in_the_generic_arm_has_a_bespoke_cue() -> void:
	var sfx := _sfx_keys()
	var effects := _generic_debuff_effects()
	## CONTENT, not a count: a wrong anchor derived 14 entries of colour components and passed this when
	## it was `effects.size() > 5`. Two known members of the arm must be present, and nothing may look
	## like a parsed expression.
	assert_true(effects.has("defense_down") and effects.has("debuff"),
		"VOID: the derived arm does not contain its two known members, so this is not the generic-debuff arm — got %s" % [effects])
	assert_gt(effects.size(), 5, "VOID: only %d effects derived" % effects.size())
	var swallowed: Array = []
	for e in effects:
		var canonical: String = Combatant.resolve_status_alias(str(e).to_lower())
		var key: String = "status_" + canonical
		if sfx.has(key):
			swallowed.append("%s -> %s" % [e, key])
	assert_eq(swallowed, [],
		"these effects play the GENERIC debuff cue while a bespoke cue is authored for them, so the authored file never plays (%d of %d in the arm): %s" % [swallowed.size(), effects.size(), swallowed])


func test_the_two_cues_are_still_authored_and_on_disk() -> void:
	## Without this the arm above passes if someone deletes the cues instead of fixing the routing —
	## the guard would be green and the sound still absent.
	var sfx := _sfx_keys()
	for key in ["status_pacify", "status_festered"]:
		assert_true(sfx.has(key), "%s is no longer authored; it was the point of this fix" % key)
		var path: String = str((sfx.get(key, {}) as Dictionary).get("file", ""))
		var res: String = path if path.begins_with("res://") else "res://" + path
		assert_true(ResourceLoader.exists(res) or FileAccess.file_exists(res),
			"%s is authored as %s but the file is not there" % [key, path])


func test_the_alias_still_reaches_the_festered_cue() -> void:
	## The half that is not mine: amplify_poison reaches play_status under the EFFECT name, so the cue
	## only sounds if the alias resolves. If that map loses the entry, this fix goes quiet again and
	## nothing else would say so.
	assert_eq(Combatant.resolve_status_alias("amplify_poison"), "festered",
		"the amplify_poison -> festered alias is gone, so status_festered cannot be reached from the effect name")
	assert_eq(Combatant.resolve_status_alias("pacify"), "pacify",
		"pacify must resolve to itself — it is reached by its own name, with no alias involved")
