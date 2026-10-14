extends GutTest

## 🐛 A CHEST CLAIMED A FIND IT HAD NOT MADE, AND THE REPAIR WAS ALREADY IN THE FILE NEXT TO TWO
## COPIES OF THE BUG. `TreasureChest._open_chest`'s item arm wrote `contents_text = "Found %s x%d!"`
## FIRST and then called `add_item`, discarding the result, behind `if game_loop and
## party.size() > 0`. Four separate nothing-happened paths each printed a find:
##
##   no GameLoop · an empty party · add_item's negative-quantity refusal · its empty-id refusal
##
## The equipment arm had the same shape (announce, then append behind `if game_loop`), and the
## `match contents_type` had NO default arm — while `WhisperingCave:749` assigns `contents_type`
## straight from `data["type"]`, so an unrecognised type fell through with an EMPTY panel.
##
## ⛔ THE GOLD ARM HAD ALREADY BEEN REPAIRED FOR EXACTLY THIS, and its own comment records the
## shipped bug: *"players saw 'Found 100 Gold!' but party_gold stayed unchanged"*. It reads the
## effect via `credited = int(GameState.add_gold(...))`. So the fix and two live copies of the bug
## it fixes sat in one `match`, which is why a per-arm reading found it and a file-level one did not.
## ⚠️ And the repaired arm still claimed in ONE direction: `credited` was SEEDED with `gold_amount`,
## so an absent `GameState.add_gold` announced the whole find having credited nothing.
##
## 🔑 THE STAKE IS NOT A WRONG CAPTION. `_is_opened = true` and the save-persisted
## `GameState.set_story_flag("chest_" + chest_id)` are written at the TOP of `_open_chest`, before
## the grant — so a grant that did nothing left a permanently-opened chest and the item gone.
## ⚠️ THAT HALF IS NOT FIXED HERE and is deliberately not claimed: moving the consumption below the
## grant changes the sprite/label path and needs a run to verify. This change makes the panel stop
## LYING; it does not yet stop the chest being consumed. Named rather than implied.
##
## 📌 EXPOSURE TODAY IS ZERO, derived not assumed: all 39 chest configuration sites in `src/` were
## read — the six overworlds constrain the type with an `if c["type"] == "gold" … else` so nothing
## falls through, and WhisperingCave's five floors are all `item`/`gold` with valid ids and positive
## amounts. So the arms below could not have failed before this change. That is the normal case for
## a latent defect of this class and it is what makes the mutations load-bearing.

const SRC := "res://src/exploration/TreasureChest.gd"


func _source() -> String:
	var f := FileAccess.open(SRC, FileAccess.READ)
	assert_not_null(f, "TreasureChest.gd must be readable at %s" % SRC)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## FLOOR. `TreasureChest.claim_for` and `NOTHING_ADDED` are reached through a `class_name`, so they
## resolve at PARSE time and a rename exits 3 (nothing ran) rather than aborting an arm — no floor
## can improve on that. `Combatant.add_item` and `.inventory` are INSTANCE reaches, which abort
## their enclosing function and leave a later assert unreached, so they get one. Derived from what
## the real-effect arm below actually drives, not hand-listed.
func test_the_instance_symbols_this_file_drives_exist() -> void:
	var c := Combatant.new()
	autofree(c)
	assert_true(c.has_method("add_item"), "Combatant.add_item must exist — the chest measures its effect")
	assert_true("inventory" in c, "Combatant.inventory must exist — it is the delta the chest reads")


func test_the_claim_is_decided_by_the_effect_not_the_configuration() -> void:
	## The whole defect in one line: every kind, nothing granted, nothing claimed.
	for kind in ["gold", "item", "equipment", "mystery_meat", ""]:
		assert_eq(TreasureChest.claim_for(kind, "Potion", 0), TreasureChest.NOTHING_ADDED,
			"kind '%s' granted 0 and must not claim a find" % kind)
		assert_eq(TreasureChest.claim_for(kind, "Potion", -3), TreasureChest.NOTHING_ADDED,
			"kind '%s' granted a negative and must not claim a find" % kind)


func test_a_claim_names_the_number_that_was_granted() -> void:
	## A partial grant is the case the old code could not express: it printed `contents_amount`, what
	## the chest was CONFIGURED with, rather than what landed.
	##
	## ⛔ THE ASSERT THAT USED TO SIT HERE COULD NOT FAIL, and its own comment called it "the
	## discriminator". It read `assert_false(said.contains("x5"))` — to catch the seam naming a
	## configured 5 — but `claim_for` only ever RECEIVES `granted`, and this arm passes 1, so the only
	## `%d` in the seam can never render 5. No configured value reaches it; "x5" was unreachable for
	## every input. Found by @cowir-controller's decidable property — an assert red by NO mutant —
	## reasoning per-assert rather than scanning, because the tautology is semantic and my regex for
	## it inverted (it flagged a real assertion and missed this shape).
	##
	## ✅ The live form asserts the seam's output DEPENDS on `granted`: a mutant that ignores the
	## amount makes these two calls agree, and this reds. That is the property the old line was
	## reaching for, stated so it can actually be violated.
	var said := TreasureChest.claim_for("item", "Potion", 1)
	assert_string_contains(said, "x1", "the claim must name what was granted")
	assert_ne(said, TreasureChest.claim_for("item", "Potion", 5),
		"the claim must VARY with the amount granted; if 1 and 5 produce the same string the seam is ignoring it")
	assert_string_contains(said, "Potion", "the claim must name the item")
	assert_string_contains(TreasureChest.claim_for("gold", "", 50), "50",
		"the gold claim must name the credited amount")
	assert_string_contains(TreasureChest.claim_for("equipment", "Iron Mail", 1), "Iron Mail",
		"the equipment claim must name the piece")


func test_add_items_own_refusals_leave_the_zero_delta_the_chest_reads() -> void:
	## The REAL effect path, on a real Combatant, so the measurement the chest performs is driven
	## rather than restated. add_item returns `void`, which is why the chest reads an inventory
	## delta: that covers both of its documented refusals and any added later.
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "ChestProbe"

	var before_neg: int = int(c.inventory.get("potion", 0))
	c.add_item("potion", -1)
	var neg_delta: int = int(c.inventory.get("potion", 0)) - before_neg
	assert_eq(neg_delta, 0, "a negative quantity must add nothing")
	assert_eq(TreasureChest.claim_for("item", "Potion", neg_delta), TreasureChest.NOTHING_ADDED,
		"and a zero delta must not be announced as a find")

	var before_empty: int = c.inventory.size()
	c.add_item("", 2)
	assert_eq(c.inventory.size(), before_empty, "an empty item_id must add no slot")

	## CONTROL: the same path must LAND when the input is good, or the two asserts above pass
	## because nothing works rather than because the refusals work.
	var before_ok: int = int(c.inventory.get("potion", 0))
	c.add_item("potion", 2)
	var ok_delta: int = int(c.inventory.get("potion", 0)) - before_ok
	assert_eq(ok_delta, 2, "a good grant must actually land — the control for the two refusals")
	assert_string_contains(TreasureChest.claim_for("item", "Potion", ok_delta), "x2",
		"and a real grant must be announced with its real amount")


func test_every_find_claim_in_the_source_lives_in_the_one_seam() -> void:
	## A source pin, and the weak kind — it certifies SPELLING, not that the arms route through the
	## seam at runtime. It is here for the one thing only source can say: that a FIFTH arm cannot
	## quietly spell its own claim again, which is exactly how the equipment arm came to carry the
	## bug the gold arm beside it had already fixed.
	var lines := _source().split("\n")
	var seam_from := -1
	var seam_to := -1
	for i in lines.size():
		var raw: String = lines[i]
		var body: String = raw.strip_edges()
		if body.begins_with("static func claim_for("):
			seam_from = i
		elif seam_from >= 0 and seam_to < 0 and body.begins_with("func ") and i > seam_from:
			seam_to = i
	assert_gt(seam_from, -1, "claim_for must exist — it is the one place a find is claimed")
	if seam_to < 0:
		seam_to = lines.size()

	var strays: Array[String] = []
	for i in lines.size():
		var raw: String = lines[i]
		if raw.strip_edges().begins_with("#"):
			continue        # the arms' comments QUOTE the old spellings on purpose
		if not raw.contains("\"Found "):
			continue
		if i >= seam_from and i < seam_to:
			continue
		strays.append("%d: %s" % [i + 1, raw.strip_edges()])
	assert_eq(strays.size(), 0, "a find may only be claimed inside claim_for; stray: %s" % str(strays))

	## PRECONDITION, so the sweep above cannot pass by finding nothing anywhere.
	var in_seam := 0
	for i in range(seam_from, seam_to):
		if lines[i].contains("\"Found "):
			in_seam += 1
	assert_gt(in_seam, 1, "claim_for must hold the claim spellings — found %d" % in_seam)


func test_the_contents_type_match_has_a_default_arm() -> void:
	## `contents_type` is DATA-DRIVEN at `WhisperingCave:749` (`chest.contents_type = data["type"]`),
	## so an unrecognised value is reachable from a data edit with no code change. Without a default
	## the match fell through leaving `contents_text` empty — and a blank panel under an opened chest
	## is the one outcome a player cannot distinguish from a working one.
	var lines := _source().split("\n")
	var at := -1
	for i in lines.size():
		if lines[i].strip_edges() == "match contents_type:":
			at = i
			break
	assert_gt(at, -1, "the grant must still be a match on contents_type")
	var indent := lines[at].length() - lines[at].lstrip("\t").length()
	var has_default := false
	for i in range(at + 1, lines.size()):
		var raw: String = lines[i]
		if raw.strip_edges() == "":
			continue
		var ind := raw.length() - raw.lstrip("\t").length()
		if ind <= indent and not raw.strip_edges().begins_with("#"):
			break
		if raw.strip_edges() == "_:":
			has_default = true
			break
	assert_true(has_default,
		"match contents_type must carry a `_:` arm — contents_type comes from data at WhisperingCave:749")


## ⛔ THE SECOND HALF, LANDED AFTER ALL: the grant now runs BEFORE the chest commits to being open.
## `_is_opened = true` and the save-persisted `set_story_flag` used to be the FIRST two statements
## of `_open_chest`, above the grant — so a nothing-happened path left a permanently-opened chest
## and the reward gone. The stake was never the caption.
##
## 🔑 WHY THESE ARMS READ SOURCE, WHICH IS NORMALLY THE WEAK INSTRUMENT: this project's own rule is
## that a source guard certifies SPELLING, not that anything RUNS. That objection does not apply to
## a STATEMENT-ORDER invariant, because the order IS the defect — "the commit happens after the
## grant" is a fact about the text and nothing else can see it. Driving it instead would need a
## built TreasureChest with its sprite, label and dialogue children plus a live GameState, and would
## still only observe the order indirectly.
func test_the_chest_commits_only_after_and_only_if_the_grant_landed() -> void:
	var src := _source()
	var at := src.find("func _open_chest(")
	assert_gt(at, -1, "_open_chest must still exist")
	var fn := src.substr(at)
	var nxt := fn.find("\nfunc ", 1)
	if nxt > -1:
		fn = fn.substr(0, nxt)

	var i_grant := fn.find("_grant_contents()")
	var i_flag := fn.find("set_story_flag")
	var i_open := fn.find("_is_opened = true")
	assert_gt(i_grant, -1, "_open_chest must call _grant_contents")
	assert_gt(i_flag, -1, "_open_chest must still write the chest's story flag")
	assert_gt(i_open, -1, "_open_chest must still mark the chest opened")

	## THE ORDERING INVARIANT — this is the defect, stated.
	assert_lt(i_grant, i_flag, "the grant must run BEFORE the save-persisted flag is written")
	assert_lt(i_grant, i_open, "the grant must run BEFORE the chest is marked opened")

	## AND THE GATE — ordering alone is not enough; an unconditional commit after the grant still
	## consumes the chest. Both commits must sit under `if granted`.
	assert_string_contains(fn, "if granted:", "the commit must be gated on the grant")
	var gate := fn.find("if granted:")
	assert_lt(gate, i_flag, "the flag write must sit under the gate, not above it")
	assert_lt(gate, i_open, "the opened mark must sit under the gate, not above it")

	## The signal is what listeners credit from (WhisperingCave:764 connects it), so a phantom
	## credit on top of the panel's is the one thing worse than a wrong panel.
	var i_emit := fn.find("chest_opened.emit")
	assert_gt(i_emit, -1, "chest_opened must still be emitted")
	assert_lt(gate, i_emit, "chest_opened must not fire for a grant that did nothing")


func test_the_grant_defaults_to_a_refusal_not_an_empty_string() -> void:
	## FAIL-CLOSED, and the direction matters: `"" != NOTHING_ADDED`, so a `contents_text` seeded
	## empty would read as GRANTED and consume the chest. That is the fail-OPEN direction on the one
	## predicate the whole commit hangs from. All four arms assign today, so this default is
	## unreachable — its job is that a FIFTH arm which forgets to assign refuses rather than
	## silently eating a reward.
	var src := _source()
	var at := src.find("func _grant_contents(")
	assert_gt(at, -1, "_grant_contents must exist")
	var fn := src.substr(at)
	var nxt := fn.find("\nfunc ", 1)
	if nxt > -1:
		fn = fn.substr(0, nxt)
	assert_string_contains(fn, "var contents_text := NOTHING_ADDED",
		"the grant's default must be a refusal, not \"\" — \"\" reads as granted")

	## CONTROL: the predicate the default feeds must actually be the inequality, or seeding it
	## correctly defends nothing.
	var open_at := src.find("func _open_chest(")
	var open_fn := src.substr(open_at)
	assert_string_contains(open_fn, "contents_text != NOTHING_ADDED",
		"`granted` must be derived from the text, so there is one source of truth and not two")


## ⛔ THE SECOND SITE OF THE SAME SHAPE, AND THE SWEEP THAT BOUNDS IT. The gold arm's bug was a
## variable SEEDED WITH THE NOMINAL AMOUNT and then conditionally overwritten by the real credit —
## so when the conditional did not fire, the nominal amount was announced as if it had been granted.
## A derived sweep for that shape across `src/` returns exactly two sites: `TreasureChest`'s gold arm
## and `FireplaceSecret._examine`. Both are fixed here; `ConversationRewards:181` was already correct
## because it appends `add_gold`'s return directly, with nothing to seed.
##
## 🔑 THIS ARM IS THE MECHANISM RATHER THAN THE TWO CALL SITES. A per-site assertion would be green
## on the third one somebody writes; this reds on it. The population is derived from the source, so
## it cannot go stale against a file I did not know about when writing it.

const _SRC_ROOT := "res://src"


func _gd_files_under(root: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [root]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			stack.append(dir + "/" + sub)
		for f in d.get_files():
			if f.ends_with(".gd"):
				out.append(dir + "/" + f)
	return out


func test_no_credit_variable_is_seeded_with_the_amount_it_has_not_granted() -> void:
	var files := _gd_files_under(_SRC_ROOT)
	assert_gt(files.size(), 50, "the src sweep must actually find files — a tiny corpus cannot ratchet")

	var offenders: Array[String] = []
	var population := 0
	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		if not text.contains("add_gold("):
			continue
		var lines := text.split("\n")
		for i in lines.size():
			var line: String = lines[i]
			var body: String = line.strip_edges()
			if body.begins_with("#") or not body.begins_with("var "):
				continue
			if not body.contains("="):
				continue
			var name: String = body.substr(4).split(":")[0].split("=")[0].strip_edges()
			if name == "":
				continue
			## Is this variable later assigned from add_gold? That is what makes it a CREDIT
			## variable rather than any local int, and it is derived rather than name-matched.
			var assigned_from_credit := false
			for j in range(i + 1, mini(i + 8, lines.size())):
				if lines[j].contains(name + " = ") and lines[j].contains("add_gold("):
					assigned_from_credit = true
					break
			if not assigned_from_credit:
				continue
			population += 1
			var seed_expr: String = body.split("=", true, 1)[1].strip_edges()
			if seed_expr != "0":
				offenders.append("%s:%d seeds %s with `%s`" % [path, i + 1, name, seed_expr])

	## PRECONDITION, so a clean sweep cannot mean "the pattern matched nothing anywhere".
	## ⛔ `>= 1`, NOT `> 1`. The population is exactly 2 today, and pinning that would red on a
	## correct change — consolidating both sites behind one helper is a legitimate refactor and
	## would leave 1. The property worth defending is that the PATTERN STILL MATCHES SOMETHING (a
	## rename of `add_gold` would take it to 0 and make every later assertion vacuous), not that
	## there are two of them. Asserting the count instead of the relationship is the coincidental-
	## value ratchet: red on a correct change, green on a wrong one.
	assert_gt(population, 0, "the sweep must find at least one credit variable — found %d" % population)
	assert_eq(offenders.size(), 0,
		"a credit variable must be seeded at 0, never with the amount it has not granted yet: %s" % str(offenders))
