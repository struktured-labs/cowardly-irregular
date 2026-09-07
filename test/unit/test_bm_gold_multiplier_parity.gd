extends GutTest

## Cadence #22 — BattleManager live-battle gold path applies
## game_constants["gold_multiplier"] to match HBR:813 + GameLoop
## _on_autogrind_battle_ended:5075. Pre-fix a Scriptweaver-set
## gold_multiplier of 2.0 doubled autogrind gold but had ZERO effect on
## live regular battles — violates the no-hidden-yield-tax pillar
## cowir-main highlighted in msg 2744.
##
## Same class as tick 341 which fixed the same asymmetry for the EXP
## side (BattleManager was correct on EXP but wrong on gold — the exp
## consumer at ~line 838 was the reference pattern).


func _get_gold_block() -> String:
	# Isolate the gold-award block in BattleManager to source-inspect.
	var src: String = load("res://src/battle/BattleManager.gd").source_code
	var marker: String = "# Collect gold from defeated enemies"
	var start: int = src.find(marker)
	assert_true(start >= 0, "setup: gold-collect block must exist")
	# End at "if total_gold > 0:" — that's the terminal of the block.
	var end: int = src.find("if total_gold > 0:", start)
	if end < 0:
		end = start + 2000  # generous fallback
	return src.substr(start, end - start)


func test_gold_block_reads_game_constants_multiplier() -> void:
	# The block must query game_constants["gold_multiplier"] to align
	# with HBR + GameLoop autogrind. Reference pattern: exp_multiplier
	# at BM line ~838.
	var body: String = _get_gold_block()
	assert_true(body.contains("gold_multiplier"),
		"BM gold-collect block must reference game_constants['gold_multiplier'] — else Scriptweaver-set gold buffs affect autogrind but not manual play (no-hidden-yield-tax violation, cadence #22)")


func test_gold_block_applies_defensive_clamp() -> void:
	# The clamp must be [0.1, 10.0] to match HBR:811, GameLoop:5060, and
	# the exp_multiplier consumer at BM:839 — the three-way parity band
	# tick 341 established.
	var body: String = _get_gold_block()
	assert_true(body.contains("clampf(") and body.contains("0.1, 10.0"),
		"BM gold_multiplier read must clampf(_, 0.1, 10.0) to match the three-way parity band (HBR + GameLoop + BM exp) — silent drift on bounds would allow degen values to slip through only in live regular battles")


func test_gold_multiplier_actually_multiplies() -> void:
	# The read is inert unless the value flows into the total_gold
	# accumulator. Source ratchet ensures the variable is USED, not just
	# declared. Grep for the actual multiply site.
	var src: String = load("res://src/battle/BattleManager.gd").source_code
	# Find the total_gold += site (the exp_multiplier consumer's parallel).
	var accum_line: int = src.find("total_gold += int(gold *")
	assert_true(accum_line >= 0, "setup: total_gold accumulator must exist")
	# Grab enough surrounding context to see the operands.
	var accum_body: String = src.substr(accum_line, 200)
	assert_true(accum_body.contains("gold_multiplier"),
		"gold_multiplier must appear in the total_gold accumulator expression — else the variable is declared but ignored (silent dead code, worse than the pre-cadence bug)")


func test_defensive_gate_on_missing_gamestate() -> void:
	# Pattern from tick 338/341: guard `if GameState and "game_constants"
	# in GameState:` so bare-instance tests without autoloads don't crash.
	# Confirms the multiplier read is behind the correct defensive gate,
	# same shape as the exp_multiplier consumer at BM:837.
	var body: String = _get_gold_block()
	assert_true(body.contains("if GameState and \"game_constants\" in GameState"),
		"gold_multiplier read must be gated on GameState existence + game_constants presence — same defensive pattern as the exp_multiplier consumer, else instance-tests crash")


func test_symmetric_with_exp_multiplier_pattern() -> void:
	# The exp_multiplier consumer in this same function is the reference
	# pattern (tick 109 + 341). Assert the gold consumer uses the same
	# grammar: clampf + game_constants.get(_, 1.0) + [0.1, 10.0] bounds.
	# Split test so a partial-match still gives a clear pinpoint.
	var body: String = _get_gold_block()
	assert_true(body.contains("float(GameState.game_constants.get(\"gold_multiplier\", 1.0))"),
		"gold_multiplier read grammar must mirror the exp_multiplier consumer verbatim (safe default 1.0, float-cast) — parity by construction, not two hand-synced patterns")
