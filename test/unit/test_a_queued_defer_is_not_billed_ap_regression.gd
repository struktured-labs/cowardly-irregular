extends GutTest

## billed_ap was declared the ONE authority for what an Advance costs, after three surfaces each
## rolled their own subtraction and disagreed. It worked — and it takes a COUNT, while a defer costs
## no AP anywhere else in the game. So all four callers then agreed on a wrong number for any queue
## holding a defer: the live engine charges per executor (_execute_attack:spend_ap(1), ability, item;
## _execute_defer charges NOTHING) while the lump billed it, and HeadlessBattleResolver uses the
## lump to CHARGE, not merely to preview.
##   [5 attacks]        @AP4  live 5 -1 refund = 4   billed_ap(4,5) = 4   agreed
##   [4 attacks, defer] @AP4  live 4 -1 refund = 3   billed_ap(4,5) = 4   off by one
##   [attack, defer]    @AP0  live 1           = 1   billed_ap(0,2) = 2   off by one
## Unifying copies removes disagreement BETWEEN them and converts it into one consistent error,
## which is harder to see: three surfaces disagreeing shows up from any two of them.

const BM = preload("res://src/battle/BattleManager.gd")

const ATTACK := {"type": "attack"}
const DEFER := {"type": "defer"}


func test_the_three_rows_bill_what_the_live_engine_charges() -> void:
	## Row 1: no defer, full bank — unchanged, and the control that proves the fix is narrow.
	assert_eq(BM.billed_ap(4, 5, 5), 4, "five attacks at a full bank still bill four")
	## Row 2: a defer inside a full bank. Four billable, minus the free fifth.
	assert_eq(BM.billed_ap(4, 5, 4), 3,
		"a defer among five is not billed, and the full bank it earned still discounts one")
	## Row 3: the plain case.
	assert_eq(BM.billed_ap(0, 2, 1), 1, "[attack, defer] costs one AP, which is what live charges")


func test_the_two_argument_form_is_unchanged() -> void:
	## Every existing caller that has only a count must keep its old answer.
	assert_eq(BM.billed_ap(0, 2), 2, "two-arg form bills the count")
	assert_eq(BM.billed_ap(4, 5), 4, "two-arg form still discounts the free fifth")
	assert_eq(BM.billed_ap(0, 0), 0, "empty queue bills nothing")


func test_billable_actions_counts_what_costs_ap() -> void:
	assert_eq(BM.billable_actions([ATTACK, DEFER]), 1, "a defer is free")
	assert_eq(BM.billable_actions([ATTACK, ATTACK]), 2, "attacks are not")
	assert_eq(BM.billable_actions([DEFER]), 0, "a lone defer costs nothing")
	assert_eq(BM.billable_actions([]), 0, "nothing costs nothing")
	## Non-dictionaries must not crash the count — shared scripts are player-editable JSON.
	assert_eq(BM.billable_actions([ATTACK, "junk"]), 2, "a malformed entry still counts as billable")


func test_the_full_bank_gate_stays_on_the_action_count() -> void:
	## The gate is an ACTION count and the bill is a BILLABLE count — the whole reason for the
	## third parameter. A reduced count passed as the second would disqualify a bank it earned.
	assert_true(BM.is_full_bank(4, 5), "five actions at +4 is a full bank")
	assert_false(BM.is_full_bank(3, 5), "below the AP floor it is not")
	assert_false(BM.is_full_bank(4, 4), "four actions is not")
	assert_eq(BM.billed_ap(4, 5, 4), 3,
		"and a defer among them keeps the bank: 4 billable - 1 free, not 4")


func test_the_full_bank_marker_does_not_key_on_a_discount() -> void:
	## Both readouts showed the star when `billed < queued_count` — a PROXY that held only while
	## the full bank was the one reason to bill less. An unbilled defer is a second reason, so the
	## proxy would promise a free fifth action to a two-action queue.
	for path in ["res://src/ui/Win98Menu.gd", "res://src/battle/BattleUIManager.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 1000, "CONTROL: read %s" % path)
		## CODE ONLY. The comment explaining the old proxy quotes it verbatim, so a raw contains()
		## would red on the explanation rather than the behaviour — and rewording a comment must
		## never fail a guard about what the code does.
		var code := ""
		for line in src.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			code += line + "\n"
		assert_true(code.contains("is_full_bank("), "%s must ask the predicate" % path)
		assert_false(code.contains("billed < queued"),
			"%s must not infer the full bank from a discount having happened" % path)


func test_every_call_site_passes_the_composition() -> void:
	## Derived, so a NEW surface that bills a bare count reds here instead of shipping the lie.
	## Scans src/ rather than listing the callers, because the list is what went stale last time.
	var dirs := ["res://src/battle", "res://src/ui", "res://src/autogrind"]
	var checked := 0
	var bare: Array[String] = []
	for d in dirs:
		for f in _gd_files(d):
			var src := FileAccess.get_file_as_string(f)
			if not src.contains("billed_ap("):
				continue
			checked += 1
			for line in src.split("\n"):
				if "billed_ap(" not in line or "static func" in line:
					continue
				## Two args and a close paren on one line = a bare count.
				var tail: String = line.substr(line.find("billed_ap(") + 10)
				if tail.count(",") < 2 and tail.contains(")"):
					bare.append("%s: %s" % [f.get_file(), line.strip_edges()])
	assert_gt(checked, 0, "CONTROL: found files calling billed_ap")
	assert_eq(bare, [] as Array[String],
		"every billed_ap call must pass the billable count — a bare count bills the defer")


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			out.append_array(_gd_files(dir_path + "/" + name))
		elif name.ends_with(".gd"):
			out.append(dir_path + "/" + name)
		name = d.get_next()
	d.list_dir_end()
	return out
