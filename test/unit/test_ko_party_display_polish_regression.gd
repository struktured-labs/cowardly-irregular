extends GutTest

## Game-over smoke shot 2026-07-04: KO'd party still showed live
## `MP: 31/31`, `AP: +1 (-1)` — reads as "still can act" even though
## HP already said `-- KO --`. Now the whole row surfaces the KO state:
## MP → `MP: --` grayed, AP → `--` grayed, MP bar dimmed. HP behavior
## unchanged.


func test_mp_and_ap_gate_on_is_alive() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	# MP branch must check is_alive
	var mp_block_idx: int = src.find("# Update MP")
	assert_gt(mp_block_idx, -1)
	var mp_block: String = src.substr(mp_block_idx, 500)
	assert_true(mp_block.contains("if not member.is_alive:"),
		"MP branch must gate on is_alive — live-value MP on a KO'd row reads as 'still can cast'")
	assert_true(mp_block.contains("MP: --"),
		"KO'd MP label must show '--' not the live value")

	# AP block must have an early return for KO'd members
	var ap_idx: int = src.find("# Update AP and status")
	assert_gt(ap_idx, -1)
	var ap_block: String = src.substr(ap_idx, 3000)
	assert_true(ap_block.contains("# KO'd party can't act"),
		"AP block must acknowledge KO in a dedicated branch, not fall through")
	# Early return so the queued/deferring/committed math doesn't run on the dead
	var ko_branch: int = ap_block.find("not member.is_alive")
	var return_after: int = ap_block.find("return", ko_branch)
	assert_gt(return_after, -1,
		"KO'd AP path must return before the ap_value computations")


func test_hp_ko_label_unchanged() -> void:
	# The existing HP KO label is the contract everything else grays to match.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_true(src.contains("hp_label.text = \"-- KO --\""),
		"HP KO copy must remain — MP/AP polish keys off it")
