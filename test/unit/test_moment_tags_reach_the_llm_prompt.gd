extends GutTest

## .739/.741 added crit_landed, enemy_felled and six victory keys to PartyCombatLineContext, and
## the SCRIPTED trigger_voices path read them correctly. DialoguePrompts._party_line_event_hint
## still had five arms, so on the LLM path those moments arrived as PARTY_LINE_GENERIC_HINT and the
## payload died at that one seam -- after surviving _fire_moment_line, _maybe_fire_party_line,
## _build_party_line_context and to_dict() intact.
##
## Measured before the fix: free-write carried the kind but not the target, the choice prompt
## carried neither, and all six victory keys were absent from both.

const PERSONA := "a tired mercenary who counts coins"
const CTX_SCRIPT := "res://src/battle/PartyCombatLineContext.gd"


func _ctx(kind: String, data: Dictionary) -> Dictionary:
	var c := PartyCombatLineContext.new()
	c.event_kind = kind
	c.event_data = data
	c.speaker_name = "Bram"
	c.speaker_job_id = "fighter"
	c.speaker_hp_pct = 60.0
	c.party = [{"name": "Bram", "job_id": "fighter", "hp_pct": 60, "is_alive": true}]
	c.enemies = [{"name": "Cave Rat", "hp_pct": 100}]
	## to_dict() is what BattleManager actually hands both builders; a hand-built dict could diverge.
	return c.to_dict()


## DERIVED from the context's own constants. The defect WAS a match with fewer arms than the
## context declares kinds, so a hand-listed guard would go blind on the next kind someone adds.
func _event_kinds() -> Array:
	var cmap: Dictionary = load(CTX_SCRIPT).get_script_constant_map()
	var out: Array = []
	for key in cmap.keys():
		if str(key).begins_with("EVENT_"):
			out.append(str(cmap[key]))
	return out


func _payload_for(kind: String) -> Dictionary:
	match kind:
		"big_hit_taken": return {"damage": 4242}
		"used_signature_ability": return {"ability_id": "cleave_xyz"}
		"crit_landed", "enemy_felled": return {PartyCombatLineContext.MOMENT_TARGET: "Grimewing"}
		"victory": return {"rounds": 17, "low_water_pct": 4.0, "anyone_fell": true}
		_: return {}


# ── the derived arm check: the shape that would have caught this bug ──────────

func test_every_declared_event_kind_has_its_own_hint() -> void:
	var kinds: Array = _event_kinds()
	## FLOOR: a broken derivation yields nothing, iterates zero times and passes vacuously.
	assert_gt(kinds.size(), 5, "FLOOR: derived only %d event kinds, so the derivation is broken" % kinds.size())
	assert_true(kinds.has("crit_landed") and kinds.has("enemy_felled"),
		"FLOOR: the two kinds this fix is about must appear in the derived set")
	for kind in kinds:
		if kind in DialoguePrompts.PARTY_LINE_GENERIC_EVENTS:
			continue
		var p: String = DialoguePrompts.build_party_line(PERSONA, [], _ctx(kind, _payload_for(kind)))
		assert_false(p.contains(DialoguePrompts.PARTY_LINE_GENERIC_HINT),
			"'%s' falls through to the generic hint: add an arm, or declare it in PARTY_LINE_GENERIC_EVENTS with a reason" % kind)


# ── controls: an assertion that a payload IS present has no loud direction alone ──

func test_control_an_event_that_always_read_its_payload_still_does() -> void:
	var p: String = DialoguePrompts.build_party_line(PERSONA, [], _ctx("big_hit_taken", {"damage": 4242}))
	assert_true(p.contains("4242"),
		"CONTROL: without this, a dropped payload and a broken probe both read FALSE")
	var q: String = DialoguePrompts.build_party_line(PERSONA, [], _ctx("used_signature_ability", {"ability_id": "cleave_xyz"}))
	assert_true(q.contains("cleave_xyz"), "CONTROL: the signature ability id must still reach the prompt")


# ── the two new moment kinds, on BOTH prompt paths ───────────────────────────

func test_a_moment_kind_names_its_target_in_both_prompts() -> void:
	for kind in ["crit_landed", "enemy_felled"]:
		var d: Dictionary = _ctx(kind, {PartyCombatLineContext.MOMENT_TARGET: "Grimewing"})
		var p: String = DialoguePrompts.build_party_line(PERSONA, [], d)
		var c: String = DialoguePrompts.build_party_line_choice(PERSONA, [], d, ["a", "b"])
		assert_true(p.contains("Grimewing"), "free-write prompt must name the %s target" % kind)
		assert_true(c.contains("Grimewing"), "choice prompt must name the %s target" % kind)
		assert_true(c.contains(kind), "choice prompt must carry the kind; it printed only the hint before")


## A moment with no target must not render an empty name, and must still be non-generic.
func test_a_moment_without_a_target_degrades_without_a_hole() -> void:
	for kind in ["crit_landed", "enemy_felled"]:
		var p: String = DialoguePrompts.build_party_line(PERSONA, [], _ctx(kind, {}))
		assert_false(p.contains(DialoguePrompts.PARTY_LINE_GENERIC_HINT),
			"%s with no target must still get its own hint" % kind)
		## The DEGENERATE shapes an empty interpolation makes, not the fallback wording itself:
		## the no-target branch legitimately says "just dropped", so keying on that was my bug.
		assert_false(p.contains("hit on ."), "%s must not interpolate an empty target name" % kind)
		assert_false(p.contains(".  "), "%s must not leave the double space an empty name produces" % kind)


# ── the victory payload ──────────────────────────────────────────────────────

func test_the_victory_shape_reaches_both_prompts() -> void:
	var data := {
		"self_leveled": true, "self_learned_ability": true,
		"rounds": 17, "one_shot": false, "low_water_pct": 4.0, "anyone_fell": true,
	}
	var d: Dictionary = _ctx("victory", data)
	var p: String = DialoguePrompts.build_party_line(PERSONA, [], d)
	var c: String = DialoguePrompts.build_party_line_choice(PERSONA, [], d, ["a", "b"])
	for prompt_name in ["free-write", "choice"]:
		var s: String = p if prompt_name == "free-write" else c
		assert_true(s.contains("17"), "%s: the round count must reach the prompt" % prompt_name)
		assert_true(s.contains("4%"), "%s: the low-water mark must reach the prompt" % prompt_name)
		assert_true(s.contains("went down"), "%s: a party member falling must reach the prompt" % prompt_name)
		assert_true(s.contains("levelled"), "%s: the speaker's own level-up must reach the prompt" % prompt_name)
		assert_true(s.contains("learned"), "%s: the speaker's new ability must reach the prompt" % prompt_name)


## NEGATIVE CONTROL: a routine win must stay short, or the renderer is always-on rather than selective.
func test_a_routine_win_adds_no_shape_clause() -> void:
	var d: Dictionary = _ctx("victory", {"rounds": 0, "one_shot": false, "low_water_pct": 100.0,
		"anyone_fell": false, "self_leveled": false, "self_learned_ability": false})
	var p: String = DialoguePrompts.build_party_line(PERSONA, [], d)
	assert_false(p.contains("How it went"),
		"a win with nothing notable must not append an empty shape clause")
	assert_false(p.contains(DialoguePrompts.PARTY_LINE_GENERIC_HINT), "victory keeps its own hint regardless")


## The one-shot fact has its own wording, and rounds==1 must read singular.
func test_a_one_shot_win_says_so() -> void:
	var p: String = DialoguePrompts.build_party_line(PERSONA, [],
		_ctx("victory", {"one_shot": true, "rounds": 1}))
	assert_true(p.contains("single blow"), "a one-shot win must say so")
	assert_true(p.contains("1 round") and not p.contains("1 rounds"), "one round must read singular")
