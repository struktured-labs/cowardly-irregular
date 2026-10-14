extends GutTest

## ⛔ `Combatant.revive()` REFUSES a permakilled ally — and five consumers called it blind and then
## announced success anyway. The worst was the manual Raise: the executor emitted `healing_done`
## (a green popup) and logged "Marta is revived with 0 HP!" over a corpse that never stood up, after
## the player had spent the MP, the AP and the turn. That is not a silent failure, it is a FALSE
## CONFIRMATION, which is strictly worse: the player has no reason to look again.
##
## 🔑 WHY IT SURVIVED, and it is the `test_<your_defect>` tell in its purest form. The ITEM path is
## fully, carefully owned: `ItemSystem.ineffective_use_reason` composes `_someone_can_be_revived` and
## `_permakill_block_reason`, and ItemsMenu, MenuScene and the battle item row ALL consult it. Two
## test files are named for this exact area and both are green through this bug:
##
##   test_a_revive_row_quotes_its_hp                        3 arms — the ITEM ROW's HP quote
##   test_autobattle_revive_picks_a_revivable_ally_regr.   7 arms — AUTOBATTLE's TARGET SELECTION
##
## Seven permakill arms, and not one drives an executor. Their corpus is SELECTION; the defect is in
## EXECUTION. So the number of pre-existing files that could have failed on this is ZERO — which is
## the normal case for a real bug, and what makes the mutations below load-bearing.
##
## ✅ THE PREDICATE ALREADY EXISTED AND NOBODY CALLED IT: `revive_preview()` returns 0 exactly when
## `revive()` will refuse, and its own docstring says "The menu quotes this." `Combatant.can_be_revived`
## now names it, derived from that same function so the bool and the HP it quotes cannot drift.
##
## 📌 THE ROW STAYS SELECTABLE BY RULING. struktured 2026-10-03 on dead_ally targeting: "shows EVERY
## ally, living or KO'd, tagged by state ... the guess is theirs to make." So this does NOT add a
## reject_reason; it fixes the TAG (a permakilled ally read " [KO]", identical to a revivable one) and
## makes the executor tell the truth. Informed choice, not a removed choice.
##
## ⚠️ THE TWO INNS ARE PINNED BY THE RATCHET ONLY, and deliberately so: both need a live GameLoop and
## a scene tree. InnInterior is the one that RUNS (`:1455` — "interior_target routes every inn here
## instead, so the legacy charge never ran"), and it charged gold and said "Your party is fully
## rested!" with a permakilled member still face-down. VillageInn._rest_party had the same shape but
## is UNREACHABLE today — its `:327` branch routes to the interior whenever `interior_target` is set,
## and 0 villages override the "inn_interior" default (verified from source, not from the comment
## that says so). Fixed for symmetry; only InnInterior's lie reached a player.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

const RAISE := {"id": "raise", "name": "Raise", "type": "revival", "revive_percentage": 50}

var _bm = null
var _log: Array = []
var _heals: Array = []


## A FRESH BattleManager, not the autoload. The autoload is shared state and leaking one field of it
## is what got a whole stack dropped from .691; an instance has its own parties and its own signals.
func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_log = []
	_heals = []
	_bm.battle_log_message.connect(func(msg): _log.append(str(msg)))
	_bm.healing_done.connect(func(who, amount): _heals.append("%s:%d" % [who.combatant_name, amount]))


func _lines() -> String:
	return "\n".join(_log)


func _pc(who: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = who
	c.max_hp = 500
	c.current_hp = 500
	c.max_mp = 100
	c.current_mp = 100
	c.is_alive = true
	return c


func _ko(who: String) -> Combatant:
	var c := _pc(who)
	c.current_hp = 0
	c.is_alive = false
	return c


func _permakilled(who: String) -> Combatant:
	var c := _ko(who)
	c.add_status("permakilled", -1)
	return c


## FLOOR, one assert per RECEIVER this file drives. A rename reds here naming the symbol, instead of
## an arm aborting mid-frame and scoring Passing on whichever assert ran before it.
func test_the_symbols_this_file_drives_exist() -> void:
	var c := _pc("Floor")
	assert_true(c.has_method("can_be_revived"), "FLOOR: Combatant.can_be_revived is the one predicate")
	assert_true(c.has_method("revive_preview"), "FLOOR: can_be_revived derives from revive_preview")
	assert_true(c.has_method("revive"), "FLOOR: revive() is what actually refuses")
	assert_true(_bm.has_method("_execute_revival_ability"), "FLOOR: the manual Raise executor")
	assert_true(_bm.has_method("_smart_retarget_revive"), "FLOOR: the execution-time retarget")
	assert_true(MenuScript.new(null).has_method("_ally_state_tag"), "FLOOR: the dead_ally submenu's state tag")
	assert_true(ResolverScript.new().has_method("_resolve_ability"), "FLOOR: the headless twin")


## The predicate is not a second opinion — it must agree with what revive() does.
func test_the_predicate_agrees_with_what_revive_actually_does() -> void:
	var ko := _ko("Bram")
	assert_true(ko.can_be_revived(), "an ordinary KO can come back")
	ko.revive(100)
	assert_true(ko.is_alive, "CONTROL: and does, so the predicate is not trivially true")

	var gone := _permakilled("Marta")
	assert_false(gone.can_be_revived(), "a permakilled ally cannot")
	gone.revive(100)
	assert_false(gone.is_alive, "revive() refuses — the predicate reports the same verdict")
	assert_eq(gone.current_hp, 0, "and no HP landed either")


## ⛔ THE DEFECT. The player casts Raise on a permakilled ally and the game told them it worked.
func test_a_refused_revive_announces_no_revive() -> void:
	var gone := _permakilled("Marta")
	_bm._execute_revival_ability(_pc("Cleric"), RAISE, [gone])

	assert_false(gone.is_alive, "CONTROL: revive() still refuses — the fix must not resurrect her")
	assert_false(_lines().contains("is revived"),
		("the log claimed a revive that never happened. Pre-fix: \"Marta is revived with 0 HP!\" "
		+ "Got: %s") % _lines())
	assert_eq(_heals, [] as Array,
		("and NO healing_done, or the player gets a green popup over a corpse. Got %s") % str(_heals))
	assert_string_contains(_lines(), "beyond reviving",
		"it must say what happened instead of going quiet — a silent turn is the other half of the bug")
	assert_string_contains(_lines(), "Marta",
		"and name who, because a mixed target set needs the player to know which one failed")


## CONTROL for the arm above: the ordinary KO path must be UNCHANGED and still announced. Without
## this, muting every revive line would satisfy the defect arm.
func test_an_ordinary_ko_is_still_revived_and_still_announced() -> void:
	var ko := _ko("Bram")
	_bm._execute_revival_ability(_pc("Cleric"), RAISE, [ko])

	assert_true(ko.is_alive, "CONTROL: an ordinary KO must still stand up")
	assert_eq(ko.current_hp, 250, "CONTROL: at the authored 50% of 500 max HP")
	assert_string_contains(_lines(), "is revived", "CONTROL: and the success line must still fire")
	assert_eq(_heals, ["Bram:250"] as Array, "CONTROL: with the green popup intact")
	assert_false(_lines().contains("beyond reviving"), "and no refusal line for a target that worked")


## A group Raise over a mixed set must report BOTH halves — one refusal must not swallow the success,
## and one success must not hide the refusal.
func test_a_mixed_target_set_reports_both_halves() -> void:
	var ko := _ko("Bram")
	var gone := _permakilled("Marta")
	_bm._execute_revival_ability(_pc("Cleric"), RAISE, [gone, ko])

	assert_true(ko.is_alive, "the revivable ally still comes back")
	assert_false(gone.is_alive, "the permakilled one does not")
	assert_string_contains(_lines(), "Bram", "the success is reported")
	assert_string_contains(_lines(), "Marta", "and so is the refusal")
	assert_eq(_heals, ["Bram:250"] as Array,
		"exactly one popup, for the ally who actually stood up: got %s" % str(_heals))


## A revive with nobody raisable at all must still say something rather than consuming a turn mutely.
func test_a_revival_aimed_at_nobody_raisable_still_speaks() -> void:
	_bm._execute_revival_ability(_pc("Cleric"), RAISE, [_pc("Standing")])
	assert_false(_log.is_empty(), "a turn that did nothing must still report why")


## ⛔ Execution-time retarget. A queued Phoenix Down's target can be permakilled between SELECTION and
## EXECUTION, which is the window the menu's own gate cannot see.
func test_the_retarget_falls_through_a_permanent_corpse_to_a_revivable_one() -> void:
	var caster := _pc("Rogue")
	var gone := _permakilled("Marta")
	var ko := _ko("Bram")
	_bm.player_party.assign([caster, gone, ko])

	assert_eq(_bm._smart_retarget_revive(caster, gone), ko,
		"aimed at a permanent corpse, it must fall through to the ally it CAN raise")
	assert_eq(_bm._smart_retarget_revive(caster, ko), ko,
		"CONTROL: a revivable original target is still honoured unchanged")


func test_the_retarget_returns_null_when_every_corpse_is_permanent() -> void:
	var caster := _pc("Rogue")
	var gone := _permakilled("Marta")
	_bm.player_party.assign([caster, gone])

	assert_null(_bm._smart_retarget_revive(caster, gone),
		("null is what routes _execute_item into its keep-the-item branch. Pre-fix it returned the "
		+ "permakilled ally, so a finite Phoenix Down was CONSUMED and did nothing."))

	## CONTROL: the null is about raisability, not about an empty party — add a revivable ally and the
	## same call must find them.
	var ko := _ko("Bram")
	_bm.player_party.assign([caster, gone, ko])
	assert_eq(_bm._smart_retarget_revive(caster, gone), ko, "CONTROL: it still finds a real corpse")


## The player's half: a permanent death must not be labelled like a revivable KO in the target list.
func test_the_submenu_tags_a_permanent_death_differently_from_a_ko() -> void:
	var menu = MenuScript.new(null)
	var ko_tag: String = str(menu._ally_state_tag(_ko("Bram")))
	var gone_tag: String = str(menu._ally_state_tag(_permakilled("Marta")))

	assert_ne(gone_tag, ko_tag,
		("both read \" [KO]\" before this, so the player chose blind between a corpse Raise works on "
		+ "and one it never will. Got %s for both.") % ko_tag)
	assert_string_contains(gone_tag, "DEAD", "and the permanent one says DEAD, matching BattleScene's badge")
	assert_string_contains(ko_tag, "KO", "CONTROL: an ordinary KO still reads KO")

	var full := _pc("Theron")
	assert_string_contains(str(menu._ally_state_tag(full)), "Full", "CONTROL: living tags are untouched")
	var hurt := _pc("Milo")
	hurt.current_hp = 10
	assert_eq(str(menu._ally_state_tag(hurt)), "", "CONTROL: and a hurt living ally still gets no tag")


## Live/headless parity is a project invariant, and the headless twin carried the identical lie.
func test_the_headless_twin_does_not_log_a_revive_it_refused() -> void:
	var r = ResolverScript.new()
	var gone := _permakilled("Marta")
	r._resolve_ability(_pc("Cleric"), "raise", [gone])
	var text: String = "\n".join(r._battle_log)

	assert_false(gone.is_alive, "CONTROL: the grind refuses her too")
	assert_false(text.contains("revives Marta with"),
		"pre-fix the grind log read \"Cleric revives Marta with 0 HP\". Got: %s" % text)
	assert_string_contains(text, "permanent", "it must name the refusal, same as the live executor")

	var r2 = ResolverScript.new()
	var ko := _ko("Bram")
	r2._resolve_ability(_pc("Cleric"), "raise", [ko])
	assert_true(ko.is_alive, "CONTROL: an ordinary KO still revives in the grind")
	assert_string_contains("\n".join(r2._battle_log), "revives Bram",
		"CONTROL: and is still logged, so the arm above is not passing by muting the log")


## RATCHET, derived from source: every consumer of revive() must consult the predicate, strip the
## marker first, or re-check is_alive afterwards. Those are the three real repairs; there is no flag
## to silence this green, only one of the three to actually do. Covers the two inns, which need a
## live GameLoop to drive, and any consumer added after today.
func test_every_revive_caller_accounts_for_the_refusal() -> void:
	var offenders: Array[String] = []
	var checked: int = 0
	var dirs: Array[String] = ["res://src"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			dirs.append("%s/%s" % [d, sub])
		for f in da.get_files():
			if not f.ends_with(".gd"):
				continue
			var path: String = "%s/%s" % [d, f]
			## ⛔ THE CODE HALF, NOT THE RAW FILE. Measured on this very ratchet: pre-fix,
			## _execute_revival_ability's own header says "Pre-fix revive only called target.revive()",
			## so a raw text search for ".revive(" anchored on that COMMENT, swept in the loop guard's
			## is_alive below it, and the WORST defect in this change read as accounted for. The
			## ratchet would not have caught the bug it exists to catch. strip_comments keeps the
			## pre-comment part of every line, so indices still align.
			var lines: PackedStringArray = GdSource.code_of(path).split("\n")
			for i in lines.size():
				var line: String = lines[i].strip_edges()
				if line.begins_with("#") or line.begins_with("##"):
					continue
				if not (".revive(" in line) or ("revive_preview" in line):
					continue
				## Combatant.gd defines revive(); it is the refuser, not a consumer.
				if path.ends_with("/Combatant.gd"):
					continue
				checked += 1
				var body: String = _enclosing_function(lines, i)
				## AFTER means after THIS call, by line index. body.find(".revive(") finds the FIRST
				## occurrence in the function, which a header comment can own.
				## ⛔ THE CALL FORM, AND is_alive CONSULTED RATHER THAN MENTIONED. Token presence
				## accepted three shapes that gate nothing: `has_method("can_be_revived")`, a string
				## literal naming the predicate, and `is_alive` ASSIGNED after the call. cowir-story
				## measured this family in three guards here — a mention certified as a use, 121 of
				## 124 with no write shape anywhere. Verdicts on both real trees are unchanged
				## (pre-fix 3 offenders, fixed 0), so the tightening costs nothing.
				## Residual, named rather than papered over: a string literal containing the CALL
				## text would still pass. code_of strips comments, not strings.
				var accounted: bool = ("can_be_revived()" in body) \
					or ('remove_status("permakilled")' in body) \
					or _checks_is_alive_after(lines, i)
				if not accounted:
					offenders.append("%s:%d — %s" % [path, i + 1, line])
	assert_gt(checked, 4,
		"FLOOR: the sweep must actually find revive() call sites, or this ratchet certifies nothing (found %d)" % checked)
	assert_eq(offenders, [] as Array[String],
		("revive() refuses a permakilled ally. A caller that ignores that announces a revive which "
		+ "never happened — consult can_be_revived(), strip the marker first, or re-check is_alive "
		+ "after. Found: %s") % str(offenders))


## `is_alive` read in a CONDITIONAL after the call — the post-revive idiom GameLoop and InnInterior
## use. An assignment to it gates nothing and must not count.
func _checks_is_alive_after(lines: PackedStringArray, at: int) -> bool:
	for raw in _after_the_call(lines, at).split("\n"):
		var l: String = raw.strip_edges()
		if "is_alive" in l and (l.begins_with("if ") or l.begins_with("elif ") or " if " in l):
			return true
	return false

## The function's text from line `at` onward — the region in which a post-revive is_alive check
## must appear. Keyed to the caller's own line, so no earlier mention can move the anchor.
func _after_the_call(lines: PackedStringArray, at: int) -> String:
	var stop: int = lines.size()
	for i in range(at + 1, lines.size()):
		if lines[i].begins_with("func ") or lines[i].begins_with("static func "):
			stop = i
			break
	var out: PackedStringArray = []
	for i in range(at, stop):
		out.append(lines[i])
	return "\n".join(out)


## The text of the function containing line `at`, from its `func` header to the next one.
func _enclosing_function(lines: PackedStringArray, at: int) -> String:
	var start: int = 0
	for i in range(at, -1, -1):
		if lines[i].begins_with("func ") or lines[i].begins_with("static func "):
			start = i
			break
	var stop: int = lines.size()
	for i in range(at + 1, lines.size()):
		if lines[i].begins_with("func ") or lines[i].begins_with("static func "):
			stop = i
			break
	var out: PackedStringArray = []
	for i in range(start, stop):
		out.append(lines[i])
	return "\n".join(out)
