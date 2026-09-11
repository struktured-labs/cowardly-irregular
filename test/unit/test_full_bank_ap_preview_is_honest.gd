extends GutTest

## The Advance menu told the player the fifth action would cost them a turn. It does not.
##
## Win98Menu's AP readout previews the turn as `current_ap - queued_count`. Full Bank refunds the
## fifth action, so at +4 with five queued the preview read "+4→-1 [5]" for a turn that actually
## ends at 0. It overstated the cost of the exact move the mechanic exists to reward — and the
## player has no way to discover the number is wrong, because the only way to check is to spend the
## turn and watch a different result.
##
## A cost readout that overstates cost is worse than one that understates: understating gets
## discovered the moment it bites, overstating just quietly suppresses the choice.
##
## The second half is discoverability. A full bank was invisible until the fifth press succeeded,
## so the mechanic was a secret. The label now says FULL BANK before the first press.

const MENU := "res://src/ui/Win98Menu.gd"
const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

func _preview_body() -> String:
	var src := FileAccess.get_file_as_string(MENU)
	assert_gt(src.length(), 1000, "CONTROL: read Win98Menu")
	## GDScript's rfind takes at most 2 args (unlike Python's 3) — my first version parse-errored and
	## run_tests.sh exited 3, NOTHING RAN, which is exactly the vacuity the exit code exists for.
	var marker: int = src.find("_ap_label.text = \"%+d AP\"")
	assert_gt(marker, -1, "CONTROL: located the AP readout")
	var i: int = src.rfind("func ", marker)
	assert_gt(i, -1, "CONTROL: located the enclosing function")
	var j: int = src.find("\nfunc ", i + 10)
	return src.substr(i, j - i) if j > i else src.substr(i)

func test_the_preview_discounts_the_free_fifth_action() -> void:
	var body := _preview_body()
	## ⚠️ REWRITTEN. This asserted `billed = queued_count - 1` — the menu's own inline arithmetic at
	## the time — and then RED-FLAGGED my own better fix an hour later, when all three readouts moved
	## to the shared BattleManager.billed_ap authority. Second time today a guard I wrote around one
	## implementation voted against a superior one; the first was cowir-sfx's walk-down. Asserting
	## the PROPERTY: the preview must not do its own subtraction, whatever the authority is called.
	assert_string_contains(body, "BattleManager.billed_ap(",
		"the preview must ask the one authority what the turn costs")
	assert_false(body.contains("_current_ap - queued_count"),
		"and must not keep a private subtraction — that copy reported a cost the turn does not charge")

func test_the_arithmetic_matches_the_engine() -> void:
	## The engine side, so the two cannot drift: five actions from +4 nets 4 AP spent, leaving 0.
	##
	## ⚠️ LIMIT, measured: this computes the expected number from the CONSTANTS, not from the menu,
	## so re-billing the full queue in Win98Menu fails only the source-text test above, not this one.
	## I predicted this arm would take two tests and it took one. What this guards is that the
	## constants still describe what the engine does — if FULL_BANK_ACTIONS or the refund changes,
	## the preview's whole premise moves and this reds first.
	var bm = BattleManagerScript.new()
	add_child_autofree(bm)
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Mira"
	c.max_hp = 500; c.current_hp = 500
	c.current_ap = BattleManagerScript.FULL_BANK_AP
	var target := Combatant.new()
	autofree(target)
	target.combatant_name = "Dummy"
	target.max_hp = 999999; target.current_hp = 999999
	bm.player_party.append(c)
	bm.enemy_party.append(target)
	var actions: Array = []
	for i in BattleManagerScript.FULL_BANK_ACTIONS:
		actions.append({"type": "attack", "target": target})
	await bm._execute_advance(c, {"type": "advance", "combatant": c, "actions": actions, "full_bank": true})
	var engine_result: int = c.current_ap
	var previewed: int = BattleManagerScript.FULL_BANK_AP - (BattleManagerScript.FULL_BANK_ACTIONS - 1)
	assert_eq(previewed, engine_result,
		"the preview's arithmetic (%d) must equal what the engine actually leaves (%d)" % [previewed, engine_result])

func test_a_short_queue_at_a_full_bank_is_billed_in_full() -> void:
	## The discriminator. Only the FIFTH action is free — if the discount applied to any queue at
	## +4, a two-action Advance would preview as costing one and the whole economy would drift.
	var body := _preview_body()
	## The gate moved into billed_ap with the rest; the menu's job is to ASK, so this pins the
	## authority's shape rather than the caller's.
	var mgr := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_string_contains(mgr, "queued >= FULL_BANK_ACTIONS",
		"the discount must be gated on a full FIVE-action queue, not merely on having the AP")

func test_the_full_bank_is_telegraphed_before_the_first_press() -> void:
	## Discoverability. Until this, a full bank looked identical to +3 until the fifth press landed.
	var body := _preview_body()
	assert_string_contains(body, "FULL BANK",
		"the readout must name the state while the queue is still empty")

func test_the_free_action_is_named_not_just_silently_cheaper() -> void:
	var body := _preview_body()
	assert_string_contains(body, "5th FREE",
		"the payoff should be legible in the readout — a smaller number alone reads as a bug")

func test_an_ordinary_turn_is_unchanged() -> void:
	## CONTROL: below a full bank the readout keeps its existing shape and colours, so this is
	## additive rather than a rewrite of the AP display everyone already reads.
	var body := _preview_body()
	assert_string_contains(body, "\"%+d AP\" % _current_ap", "the plain readout survives")
	assert_string_contains(body, "\"%+d→%+d [%d]\" % [_current_ap, new_ap, queued_count]",
		"and so does the ordinary preview format")
