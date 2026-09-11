extends GutTest

## Can the player always leave, and never leave by accident?
##
## struktured's requirement (2026-09-07): "you can just press b and not respond
## if you want." Two things have to hold — an exit must always be reachable, and
## a line the player meant as a QUESTION must never be read as one.
##
## 🔴 THE SECOND WAS BROKEN. _is_farewell prefix-matches, so all of these ended
## the conversation:
##     "Farewell — but first, what of the dragon?"
##     "Goodbye for now. What of the ember wyrm?"
##     "Take care of that wound of yours — how did you get it?"
##     "I should go looking for the dragon. Where is its lair?"
## The third is the one that matters most: party condition reaching the prompt is
## MY OWN feature, and it makes the model measurably more likely to write exactly
## that line. The fix made an older heuristic wrong more often.
##
## 🔑 AND THE DIRECTION IS THE WHOLE DESIGN. A missed farewell costs one extra
## turn, and the player still has B and the guaranteed exit option. A FALSE
## farewell cannot be undone: it ends the conversation, writes the memory, and
## settles the reward claim for that NPC and quest phase. So the heuristic must
## fail toward staying, and "ends with ?" is the cheapest rule that does.

const DC := preload("res://src/llm/DynamicConversation.gd")
const DCM := preload("res://src/llm/DialogueChoiceMenu.gd")
const DC_SCRIPT := preload("res://src/llm/DynamicConversation.gd")

var _dc = null


func before_each() -> void:
	_dc = DC.new()
	add_child_autofree(_dc)


# ── a real goodbye still ends the conversation ────────────────────────────────

func test_plain_farewells_still_exit() -> void:
	for line in ["Farewell.", "Farewell", "Goodbye.", "Goodbye", "Good-bye",
			"Take care", "Take care now", "I should go", "I'll be going"]:
		assert_true(_dc._is_farewell(line),
			"'%s' must still end the conversation — narrowing must not strand the player" % line)


func test_the_appended_exit_option_is_always_recognised() -> void:
	## _ensure_farewell appends this exact string, so if _is_farewell ever stopped
	## matching it the guaranteed exit would become unreachable.
	var choices: Array[String] = ["Tell me about the dragon."]
	_dc._ensure_farewell(choices)
	assert_eq(choices.size(), 2, "an exit option must be appended when none is present")
	assert_true(_dc._is_farewell(choices[-1]),
		"the option _ensure_farewell appends must be one _is_farewell recognises")


func test_an_exit_exists_even_when_the_model_fills_every_slot() -> void:
	var choices: Array[String] = []
	for i in range(DialoguePrompts.MAX_CHOICES):
		choices.append("Question %d?" % i)
	_dc._ensure_farewell(choices)
	assert_eq(choices.size(), DialoguePrompts.MAX_CHOICES,
		"capacity must be respected rather than exceeded")
	var has_exit: bool = false
	for c in choices:
		if _dc._is_farewell(c):
			has_exit = true
	assert_true(has_exit,
		"at capacity one slot must be replaced by an exit — the player must never be trapped")


# ── a question is never a goodbye ─────────────────────────────────────────────

func test_a_question_is_never_read_as_a_farewell() -> void:
	for line in [
			"Farewell — but first, what of the dragon?",
			"Goodbye for now. What of the ember wyrm?",
			"Take care of that wound of yours — how did you get it?",
			"I should go looking for the dragon. Where is its lair?",
			"I'll be going to the cave — which path is safest?",
		]:
		assert_false(_dc._is_farewell(line),
			"'%s' is a question; ending the conversation on it banks the memory and settles the reward claim" % line)


func test_ordinary_questions_are_unaffected() -> void:
	for line in ["Tell me about the dragon.", "What of the Calibrant?", "Who are you?"]:
		assert_false(_dc._is_farewell(line),
			"CONTROL: '%s' was never a farewell, so this test is about the new rule and not about breakage" % line)


func test_the_narrowing_keys_on_the_question_mark_not_on_length() -> void:
	## Discriminator. A length- or word-count-based rule would also have "fixed"
	## these cases while breaking a long, genuine goodbye.
	assert_true(_dc._is_farewell("Farewell, and may the road be kind to you and yours, traveller."),
		"a long goodbye with no question mark is still a goodbye")


# ── the cancel sentinel has two definers ──────────────────────────────────────

func test_the_cancel_sentinel_agrees_across_its_two_definers() -> void:
	## DialogueChoiceMenu.present() returns its own CHOICE_CANCELLED; the
	## conversation loop compares against a SEPARATE constant of the same name.
	## They agree today and nothing forces them to. If the menu ever changed its
	## sentinel — to tell a real cancel apart from an empty model choice, say —
	## B would silently stop ending conversations and the loop would treat the
	## cancel as a chosen line.
	assert_eq(DC.CHOICE_CANCELLED, DCM.CHOICE_CANCELLED,
		"the conversation loop and the choice menu must agree on the cancel sentinel")


func test_cancel_is_distinguishable_from_a_real_choice() -> void:
	## The property the shared value has to keep: no farewell the loop recognises
	## may equal the sentinel, or a cancel and a goodbye become the same event.
	assert_false(_dc._is_farewell(DCM.CHOICE_CANCELLED),
		"the cancel sentinel must not itself read as a farewell line")


# ── the exit slot was eating a generated choice ───────────────────────────────
#
# _ensure_farewell appends an exit when there is room and REPLACES the last
# choice when there is not. The model was asked for the full MAX_CHOICES, and
# measured against live llama3 (5 samples of the reply prompt) it returned 4
# distinct choices every time and an exit ZERO times — so the fourth was
# discarded on every turn.
#
# The prompt asks for choices "covering a range of tones: curious, cautious,
# friendly, direct" and one tone was then dropped before the player saw it.
# Requesting MAX_CHOICES - 1 costs nothing: the menu is the same size and every
# line the model writes survives.

func test_the_exit_slot_is_reserved_rather_than_taken_from_the_model() -> void:
	assert_eq(DC_SCRIPT.REQUESTED_CHOICES, DialoguePrompts.MAX_CHOICES - 1,
		"one slot must be reserved for the exit, or the model's last choice is replaced")


func test_a_full_generated_set_survives_intact() -> void:
	var generated: Array[String] = []
	for i in range(DC_SCRIPT.REQUESTED_CHOICES):
		generated.append("Generated option %d?" % i)
	var before: Array = generated.duplicate()
	_dc._ensure_farewell(generated)
	assert_eq(generated.size(), DialoguePrompts.MAX_CHOICES,
		"the menu the player sees must still be MAX_CHOICES")
	for line in before:
		assert_true(generated.has(line),
			"'%s' must survive — reserving the slot exists so nothing generated is dropped" % line)


func test_the_menu_still_ends_with_a_usable_exit() -> void:
	var generated: Array[String] = []
	for i in range(DC_SCRIPT.REQUESTED_CHOICES):
		generated.append("Generated option %d?" % i)
	_dc._ensure_farewell(generated)
	assert_true(_dc._is_farewell(generated[-1]),
		"the reserved slot must actually hold an exit the loop recognises")


func test_a_model_that_writes_its_own_exit_is_not_double_counted() -> void:
	## CONTROL: if the model does produce an exit, no second one is appended and
	## the menu stays under capacity rather than growing.
	var generated: Array[String] = ["What of the wyrm?", "Tell me more.", "Farewell."]
	_dc._ensure_farewell(generated)
	assert_eq(generated.size(), 3,
		"an exit already present must not trigger another — the menu must not grow")


func test_over_capacity_input_still_replaces_rather_than_overflowing() -> void:
	## CONTROL: the replace branch must survive, because a future caller could
	## still hand over a full set. Reserving the slot removes the CAUSE, not the
	## guard.
	var generated: Array[String] = []
	for i in range(DialoguePrompts.MAX_CHOICES):
		generated.append("Question %d?" % i)
	_dc._ensure_farewell(generated)
	assert_eq(generated.size(), DialoguePrompts.MAX_CHOICES,
		"capacity must still be respected if a full set arrives")
	assert_true(_dc._is_farewell(generated[-1]),
		"and an exit must still be guaranteed in that case")
