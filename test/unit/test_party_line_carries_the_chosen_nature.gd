extends GutTest

## The player picks a Nature and the AI voicing them never heard it.
##
## _build_party_line_context read `combatant.get_meta("personality")`. Measured:
## NOTHING IN THE REPO EVER CALLS set_meta("personality", ...) — zero writers. So
## ctx.speaker_personality was always "" and the prompt's "Personality trait:"
## line never rendered, for every party member, in every battle line.
##
## Meanwhile CharacterCreationScreen shows "Nature: Brave (+2 ATK, Power Drink)"
## as an explicit player choice, CharacterCustomization holds it, and Combatant
## already carries the customization reference (GameLoop populates it for all five
## starters). The data was one hop away from a prompt with a slot for it.
##
## The NAME is the cue, not the description: "Brave" is a temperament a model can
## voice; "+2 ATK, Power Drink" is a stat line and would be noise in a dialogue
## prompt. That distinction is what the test below pins.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const CC := preload("res://src/character/CharacterCustomization.gd")


class FakeCustom:
	extends RefCounted
	var personality: int = 0


func _combatant_with(nature: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Rilla"
	var custom := FakeCustom.new()
	custom.personality = nature
	c.customization = custom
	return c


# ── the data reaches the prompt ───────────────────────────────────────────────

func test_the_chosen_nature_reaches_the_party_line_prompt() -> void:
	var prompt: String = DP.build_party_line(
		"a cleric", [],
		{"speaker_name": "Rilla", "speaker_job_id": "cleric", "speaker_personality": "Brave"})
	assert_true(prompt.find("Personality trait: Brave") != -1,
		"the Nature the player chose must reach the model that voices them")


func test_no_nature_leaves_the_block_out_entirely() -> void:
	## CONTROL: an empty personality must not render an empty trait line — that is
	## the state EVERY party member was in before this fix.
	var prompt: String = DP.build_party_line(
		"a cleric", [], {"speaker_name": "Rilla", "speaker_job_id": "cleric"})
	assert_eq(prompt.find("Personality trait:"), -1,
		"with no Nature the block must be absent, not present-and-blank")


# ── the resolver prefers the right source ─────────────────────────────────────

func test_every_authored_nature_resolves_to_a_voiceable_word() -> void:
	## All five must produce a temperament, or some players get the empty state
	## the fix was written to remove.
	var seen: Dictionary = {}
	for nature in [CC.Personality.BRAVE, CC.Personality.CAUTIOUS,
			CC.Personality.SCHOLARLY, CC.Personality.QUICK, CC.Personality.CHARISMATIC]:
		var name: String = str(CC.get_personality_name(nature))
		assert_ne(name, "", "Nature %d must have a name" % nature)
		seen[name] = true
	assert_eq(seen.size(), 5,
		"CONTROL: all five Natures must be DISTINCT, or the cue carries no information")


func test_the_cue_is_the_name_not_the_stat_line() -> void:
	## The discriminator. get_personality_description returns "+2 ATK, Power Drink"
	## — mechanically true and useless to a model asked for in-character dialogue.
	var name: String = str(CC.get_personality_name(CC.Personality.BRAVE))
	var desc: String = str(CC.get_personality_description(CC.Personality.BRAVE))
	assert_eq(name, "Brave", "the name is a temperament")
	assert_true(desc.find("+") != -1,
		"CONTROL: the description really is a stat line, so preferring the name is a choice with a reason")
	var prompt: String = DP.build_party_line(
		"a cleric", [], {"speaker_name": "Rilla", "speaker_personality": name})
	assert_eq(prompt.find("+2 ATK"), -1,
		"the stat line must never reach a dialogue prompt")


# ── source precedence ─────────────────────────────────────────────────────────

func test_an_explicit_meta_still_wins() -> void:
	## Backwards compatibility: nothing sets this today, but if something starts,
	## an explicit override must beat the derived Nature.
	var bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	var c := _combatant_with(CC.Personality.BRAVE)
	c.set_meta("personality", "Haunted")
	assert_eq(bm._resolve_speaker_personality(c), "Haunted",
		"an explicit meta must take precedence over the derived Nature")


func test_the_derived_nature_is_used_when_no_meta_is_set() -> void:
	var bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	assert_eq(bm._resolve_speaker_personality(_combatant_with(CC.Personality.CAUTIOUS)), "Cautious",
		"with no meta the player's chosen Nature must be used — this is the whole fix")


func test_a_combatant_with_no_customization_is_empty_not_broken() -> void:
	var bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	var c := Combatant.new()
	autofree(c)
	assert_eq(bm._resolve_speaker_personality(c), "",
		"a combatant with no customization must yield empty, not crash or invent a Nature")
	assert_eq(bm._resolve_speaker_personality(null), "",
		"and null must be handled — this runs on every party line in every battle")


# ── the bigger defect the same run exposed ────────────────────────────────────
#
# The prompt listed the authored signature phrases under "use the rhythm — do NOT
# copy verbatim every turn". Measured against live llama3 with the REAL cleric
# persona and its four authored phrases:
#
#     before   10 of 12 samples were an authored phrase VERBATIM
#     after     0 of 8 verbatim, 0 near-verbatim
#
# So party combat dialogue was largely reciting four canned lines — an expensive
# random phrase picker. "every turn" implicitly permits copying sometimes, and
# four listed phrases under a 140-char cap anchor hard. After: "A wound noted.
# Prayers recalibrated." / "Mercy's account is dwindling..." — in-register, new,
# and about the moment.
#
# ⚠️ n=12 before / n=8 after, one model, one scenario. Large and one-directional,
# but a demonstration; re-measure with tools/llm_prompt_preview.sh party --ask.

func test_the_phrases_are_labelled_examples_not_lines_to_say() -> void:
	var prompt: String = DP.build_party_line(
		"a cleric", ["Stitched. Logged. Forgiven."], {"speaker_name": "Rilla"})
	assert_true(prompt.find("EXAMPLES OF VOICE, not lines to say") != -1,
		"the phrases must be framed as voice examples — listing them as 'signature phrases' got them recited verbatim 10 of 12 times")


func test_the_prompt_forbids_reworded_copies_too() -> void:
	var prompt: String = DP.build_party_line(
		"a cleric", ["Stitched. Logged. Forgiven."], {"speaker_name": "Rilla"})
	assert_true(prompt.find("lightly reworded version") != -1,
		"forbidding only verbatim leaves 'Mercy is a stat... mine is capped.' — which the model produced when hedged")
	assert_true(prompt.find("Write a NEW line") != -1,
		"the instruction must say what to do, not only what to avoid")


func test_the_authored_phrases_are_still_shown() -> void:
	## CONTROL: the fix must not remove the voice cue it reframes. The phrases are
	## how the model learns the register; the defect was their LABEL, not their
	## presence.
	var prompt: String = DP.build_party_line(
		"a cleric", ["Stitched. Logged. Forgiven.", "Mercy is a stat. Mine is capped."],
		{"speaker_name": "Rilla"})
	assert_true(prompt.find("Stitched. Logged. Forgiven.") != -1,
		"the authored phrases must still reach the model as register cues")
	assert_true(prompt.find("Mercy is a stat. Mine is capped.") != -1,
		"all of them, not just the first")


func test_no_phrases_means_no_block() -> void:
	## CONTROL: a job with no authored phrases must not render an empty heading.
	var prompt: String = DP.build_party_line("a cleric", [], {"speaker_name": "Rilla"})
	assert_eq(prompt.find("EXAMPLES OF VOICE"), -1,
		"with nothing to exemplify the block must be absent")
