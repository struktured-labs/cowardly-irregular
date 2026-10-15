extends GutTest

## A reward that credited nothing still consumed the player's one claim.
##
## ConversationRewards._grant appended `"%d gold" % add_gold(gold)` unconditionally whenever the
## table entry had gold > 0. GameState.gold_to_credit is `int(amount * multiplier)` -- TRUNCATING
## -- with the multiplier clamped to [0.1, 10.0], so any entry under 10 gold credits ZERO at the
## floor. `parts` then held "0 gold", so the summary was non-empty, grant_if_earned called
## mark_claimed, and the NPC's one payout for that quest phase was spent on nothing.
##
## ⚠️ LATENT, NOT LIVE, and measured rather than assumed: the shipped
## data/conversation_rewards.json holds 40 / 90 / 50 / 60 gold, which credit 4 / 9 / 5 / 6 at the
## floor -- never zero. The clamp also stops Scriptweaver driving the multiplier below 0.1. So
## today only a FUTURE table entry under 10 gold reaches it, which is why this ships as a closed
## hole rather than as a player-visible fix.
##
## The file's own docstring already stated the rule it did not implement: "a table entry of all
## zeroes must not consume the claim". A payout that ROUNDS to zero leaves the player with exactly
## the same nothing, and that is the case the code missed.

const Rewards := preload("res://src/llm/ConversationRewards.gd")

## Stands in for GameState: credits `rate` of what is asked, truncated, like gold_to_credit.
class FakeGS:
	extends Node
	var rate: float = 1.0
	var added: int = 0
	func add_gold(amount: int) -> int:
		var credited: int = int(float(amount) * rate)
		added += credited
		return credited


func _gs(rate: float) -> FakeGS:
	var g := FakeGS.new()
	g.rate = rate
	add_child_autofree(g)
	return g


func test_a_full_credit_is_announced_with_the_credited_amount() -> void:
	var gs := _gs(1.0)
	var out: String = Rewards._grant(gs, {"gold": 40, "items": []})
	assert_true(out.contains("40 gold"), "a full credit must name what landed, got: %s" % out)
	assert_eq(gs.added, 40, "and the gold must actually be credited")


## CONTROL for the arithmetic this whole file is about: a REDUCED but non-zero credit must be
## announced as the CREDITED figure, never the table's. This already worked and must keep working.
func test_a_reduced_credit_names_the_reduced_figure() -> void:
	var gs := _gs(0.1)
	var out: String = Rewards._grant(gs, {"gold": 40, "items": []})
	assert_true(out.contains("4 gold"), "must announce the credit, not the table amount: %s" % out)
	assert_false(out.contains("40 gold"), "the table amount must not be announced: %s" % out)


func test_a_credit_that_rounds_to_zero_is_not_announced() -> void:
	var gs := _gs(0.1)
	var out: String = Rewards._grant(gs, {"gold": 9, "items": []})
	assert_eq(gs.added, 0, "FIXTURE: 9 at 0.1 must truncate to 0 or this arm measures nothing")
	assert_false(out.contains("0 gold"), "THE DEFECT: a zero credit was announced as a reward")
	assert_eq(out, "", "nothing landed, so the summary must be empty and the claim must survive")


## The claim-burn is the consequence that matters: grant_if_earned calls mark_claimed only on a
## non-empty summary, so an empty one is what protects the player's one payout.
func test_nothing_landed_means_nothing_to_announce() -> void:
	var gs := _gs(0.1)
	for gold in [1, 3, 5, 9]:
		var out: String = Rewards._grant(gs, {"gold": gold, "items": []})
		assert_eq(out, "", "%d gold at the 0.1 floor credits nothing, so it must announce nothing" % gold)
	assert_eq(gs.added, 0, "and across every one of them the party gained nothing")


## The shipped table must stay clear of the latent case, so a future edit that walks into it reds
## here with the reason rather than silently burning a claim in a player's save.
func test_the_shipped_table_credits_something_at_the_floor() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/conversation_rewards.json")
	assert_gt(raw.length(), 0, "FIXTURE: the reward table must be readable")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "the table must parse to a Dictionary")
	var checked: int = 0
	for entry in _entries(parsed):
		var gold: int = int(entry.get("gold", 0))
		if gold <= 0:
			continue
		checked += 1
		assert_gt(int(float(gold) * 0.1), 0,
			"gold=%d credits 0 at the clamp floor, which would burn the player's one claim" % gold)
	assert_gt(checked, 0, "FIXTURE: the table must hold at least one positive gold entry")


func _entries(d: Dictionary) -> Array:
	var out: Array = []
	if d.has("gold"):
		out.append(d)
	for k in d.keys():
		var v: Variant = d[k]
		if v is Dictionary:
			out.append_array(_entries(v))
	return out
