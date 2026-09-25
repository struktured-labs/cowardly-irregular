extends GutTest

## `ConversationRewards._entry_for` hands out the process-wide table BY REFERENCE, and
## the only thing that made that safe was a hand audit.
##
## The file says so itself, at the function:
##
##     "handing an entry out IS handing out write access — a caller that mutates the
##      result corrupts every later lookup in the process, with NO assignment anywhere
##      for anyone to grep. The safety today lives entirely in the one consumer:
##      `_grant` reads gold/items and writes nothing (verified line by line, 0 writes)."
##
## ⛔ THAT IS A PROPERTY VERIFIED BY READING, HELD BY NOTHING. Measured: 7 test files
## drive ConversationRewards and not one asserts the table survives a grant. A second
## consumer — or one line added to `_grant` — silently rewrites the payout table for
## every later NPC in the process, and in a suite for every later FILE.
##
## The comment is also the reason a guard is cheap here: it already names the exact
## property to pin, so this file is that sentence made executable.

class FakeGameState:
	extends Node
	var game_constants: Dictionary = {}
	var battles_won: int = 0
	var gold: int = 0
	func add_gold(amount: int) -> int:
		gold += amount
		return amount


const NPC := "elder_theron"

var _gs: FakeGameState = null
var _before: Dictionary = {}


func before_each() -> void:
	_gs = FakeGameState.new()
	add_child_autofree(_gs)
	_gs.battles_won = 999  # past the battle backstop, as the sibling wiring guard does
	ConversationRewards.reset_table_cache()
	_before = ConversationRewards._entry_for(NPC).duplicate(true)


func after_each() -> void:
	## NET, because the control arm below mutates the shared static on purpose. Reloading
	## from disk restores it whatever the arm did — and it runs even when an arm aborts,
	## which an inline restore at the end of that arm would not.
	ConversationRewards.reset_table_cache()


func test_a_grant_does_not_mutate_the_shared_table() -> void:
	## THE PROPERTY THE COMMENT ASSERTS BY HAND. Compared against a deep copy taken
	## before the grant, so any write through the handed-out reference shows up here.
	var line: String = ConversationRewards.grant_if_earned(_gs, NPC, "phase_a", 4)
	assert_ne(line, "", "the grant did not land — this arm needs a real payout to be about anything")
	var after: Dictionary = ConversationRewards._entry_for(NPC)
	assert_eq(after, _before,
		("granting rewrote the shared reward table for '%s'. _entry_for returns the static BY "
		+ "REFERENCE, so a consumer that writes to its result corrupts every later lookup in "
		+ "the process. before=%s after=%s") % [NPC, _before, after])


func test_the_table_survives_a_grant_for_a_second_npc_too() -> void:
	## One NPC's entry could be left alone while a shared sub-object is not. `default` is
	## the fallback every unlisted NPC resolves to, so it is the one most likely to be
	## quietly shared between lookups.
	var default_before: Dictionary = ConversationRewards._entry_for("nobody_in_the_table").duplicate(true)
	ConversationRewards.grant_if_earned(_gs, NPC, "phase_b", 4)
	assert_eq(ConversationRewards._entry_for("nobody_in_the_table"), default_before,
		"granting to one NPC altered the shared `default` entry every other NPC falls back to")


# ── control: the hazard channel must be shown to be real ─────────────────────

func test_the_handle_really_is_shared_so_the_arms_above_are_not_vacuous() -> void:
	## FLOOR, and the whole reason the arms above mean something. If `_entry_for` returned
	## a COPY, they would pass no matter what any consumer did — a guard about a channel
	## that does not exist. This proves the channel exists by writing through it.
	##
	## The mutation is deliberate and `after_each` reloads the table from disk.
	var handle: Dictionary = ConversationRewards._entry_for(NPC)
	handle["__probe__"] = 1
	var seen_again: Dictionary = ConversationRewards._entry_for(NPC)
	assert_true(seen_again.has("__probe__"),
		("_entry_for returned a COPY, not the shared static — the two arms above cannot fail "
		+ "and this file is decorative. Either the function changed (good, delete this file) "
		+ "or the lookup no longer reaches the same table."))


func test_the_entry_under_test_is_really_in_the_table() -> void:
	## FLOOR on the FIXTURE. An NPC absent from the table resolves to `default`, and the
	## arms above would then compare the fallback with itself — green for every possible
	## implementation. Pinned by CONTENT, not by the id being spelled right.
	assert_false(_before.is_empty(),
		"'%s' resolves to an empty entry — the arms above are comparing nothing" % NPC)
	assert_true(_before.has("gold") or _before.has("items"),
		"'%s' has no payout fields, so a grant through it cannot write anything: %s"
			% [NPC, _before])
