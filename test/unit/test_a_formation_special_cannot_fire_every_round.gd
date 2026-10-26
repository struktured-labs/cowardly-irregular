extends GutTest

## HeadlessBattleResolver has had GROUP_ATTACK_COOLDOWN = 3 since it shipped. BattleManager — the
## engine a PLAYER fights in — had no cooldown at all, so a formation special was gated by AP alone:
## 2 AP each against a natural +1 per round means Four Heroes on rounds 3, 4, 6, 8, 10. Carmelo
## approved exactly this one change on 2026-10-26 ("give Four Heroes a cooldown, match the
## resolver's 3 rounds") and declined every other balance item, so the SCOPE is pinned here too.
##
## Why it matters past the spam: measured on the shipped tree 63dac407b, one Four Heroes at L10 is
## 10,267 damage and one-shots 20 of 26 bosses. A cooldown cannot save those — one hit is all the
## move needs. It bites on the three that survive a hit (Mordaine, the W6 curator and warden), where
## it cuts the formation's cadence by about a third.
##
## The cooldown is DERIVED from current_round rather than ticked by its own counter: there is no
## increment to delete, and nothing to desync from the round the rest of the engine is on.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const RESOLVER_PATH := "res://src/autogrind/HeadlessBattleResolver.gd"
const MENU_PATH := "res://src/battle/BattleCommandMenu.gd"
const MANAGER_PATH := "res://src/battle/BattleManager.gd"
const THIS_FILE := "res://test/unit/test_a_formation_special_cannot_fire_every_round.gd"

var _bm = null
var _log_lines: Array[String] = []


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_log_lines.clear()
	_bm.battle_log_message.connect(func(s: String): _log_lines.append(s))


func _body(who: String, hp: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = who
	c.max_hp = hp
	c.current_hp = hp
	c.is_alive = true
	return c


## One PC mid-selection with `ap` to spend, one live enemy, and the cooldown armed as start_battle
## leaves it. Returns the PC. TYPED LOCALS, NOT LITERALS: player_party/selection_order are
## Array[Combatant], and an untyped `[pc]` through an untyped `_bm` is the roundtrip trap — it
## aborts this helper and hands back the default.
func _selecting_fight(ap: int = 4) -> Combatant:
	var pc := _body("Hero", 1000)
	pc.current_ap = ap
	var foe := _body("Foe", 1000)
	var players: Array[Combatant] = [pc]
	var enemies: Array[Combatant] = [foe]
	var everyone: Array[Combatant] = [pc, foe]
	var order: Array[Combatant] = [pc, foe]
	_bm.player_party = players
	_bm.enemy_party = enemies
	_bm.all_combatants = everyone
	_bm.selection_order = order
	_bm.selection_index = 0
	_bm.current_combatant = pc
	_bm.pending_actions = [] as Array[Dictionary]
	_bm.execution_order = [] as Array[Dictionary]
	_bm.current_round = 1
	_bm._formation_last_round = -int(_bm.GROUP_ATTACK_COOLDOWN)
	_bm.current_state = BattleManagerScript.BattleState.PLAYER_SELECTING
	return pc


func _said_cooldown() -> bool:
	for line in _log_lines:
		if line.to_lower().contains("re-form"):
			return true
	return false


## A function body, bounded at BOTH ends — from its own `func` line to the next one. An unbounded
## window reads the whole rest of the file and would find the call anywhere below it.
func _func_body(src: String, fname: String) -> String:
	var start: int = src.find("func %s(" % fname)
	if start < 0:
		return ""
	var end: int = src.find("\nfunc ", start + 1)
	return src.substr(start, (end - start) if end > start else -1)


func test_the_floor_names_every_symbol_this_file_reaches() -> void:
	## DERIVED, not hand-listed: every `_bm.<name>` this file touches must exist on the real script,
	## so a rename reds here BY NAME instead of leaving each arm to abort into a silent pass. These
	## are lane-local symbols with one consumer apiece — this file — so the floor IS the cover.
	var src: String = FileAccess.get_file_as_string(THIS_FILE)
	assert_gt(src.length(), 0, "the file must read its own source for the derivation to mean anything")
	var rx := RegEx.new()
	rx.compile("_bm\\.(\\w+)")
	var reached := {}
	for m in rx.search_all(src):
		reached[m.get_string(1)] = true
	assert_gt(reached.size(), 8, "the derivation must find the real reach set (found %s)" % str(reached.keys()))
	## Three call shapes reach three namespaces and `in` sees only the first.
	var missing: Array = []
	for name in reached:
		if not ((name in _bm) or _bm.has_method(name) or _bm.has_signal(name)):
			missing.append(name)
	assert_eq(missing.size(), 0, "BattleManager no longer carries: " + str(missing))


func test_the_live_cooldown_is_the_resolvers_twin() -> void:
	## The comment on BattleManager.GROUP_ATTACK_COOLDOWN claims it is the resolver's twin, and the
	## ruling was "match the resolver". Twins by construction must agree in VALUE; nothing else makes
	## them, and the whole reason the harness numbers transfer to live is that they do.
	var resolver_src: String = FileAccess.get_file_as_string(RESOLVER_PATH)
	var rx := RegEx.new()
	rx.compile("(?m)^const GROUP_ATTACK_COOLDOWN\\s*(?::\\s*int\\s*)?=\\s*(\\d+)")
	var m := rx.search(resolver_src)
	assert_not_null(m, "HeadlessBattleResolver must still declare GROUP_ATTACK_COOLDOWN for the twin to mean anything")
	if m == null:
		return
	assert_eq(int(_bm.GROUP_ATTACK_COOLDOWN), int(m.get_string(1)),
		"the live cooldown and the resolver's must stay equal — the harness measures one and the player feels the other")


func test_a_battle_opens_with_the_cooldown_already_expired() -> void:
	## ⛔ THE ONE PLACE LIVE DIVERGES FROM THE RESOLVER, DELIBERATELY. The resolver's counter starts
	## COLD — 0 at battle start — so its first formation cannot land before round 3, which is why
	## every balance cell reads 3.00 rounds. Live must NOT copy that: a cold gate makes the row dead
	## for the first three rounds of every fight, and trash encounters last 2.00 rounds, so the move
	## would not exist for most of the game. test_an_unpayable_group_row_says_why_regression's own
	## control arm says it in one line — "a reason that is always present is this same bug wearing
	## the other mask" — and it red on my first attempt, which is how this arm came to be inverted.
	##
	## It also buys nothing measurable: 2 AP against a natural +1 per round already delays the opener
	## to round 2-3, and a formation-only cooldown of 3 measured IDENTICAL to no cooldown on all six
	## anchors (20 trials, tree 63dac407b). A cooldown starts when you USE the move.
	## ⛔ NO FIXTURE CALL HERE, ON PURPOSE: _selecting_fight() hand-sets the stamp, so this arm would
	## read its own copy of the decision and stay green while production reverted to a cold gate —
	## measured, it did exactly that. A bare manager reads the DECLARED default, which is the subject.
	var seen: Array = []
	for r in range(1, 5):
		_bm.current_round = r
		seen.append(_bm.formation_cooldown_remaining())
	assert_eq(seen, [0, 0, 0, 0],
		"a battle must open with the formation available — AP is the only thing that gates the first one: %s" % str(seen))
	## And the divergence is this and ONLY this: once it has fired, both engines wait the same 3.
	_bm._formation_last_round = 2
	_bm.current_round = 3
	assert_eq(_bm.formation_cooldown_remaining(), int(_bm.GROUP_ATTACK_COOLDOWN) - 1,
		"after a use, live must wait exactly as long as the resolver does")


func test_the_boundary_is_the_round_the_cooldown_names() -> void:
	## BISECTED rather than sampled: one round short must still refuse and the named round must
	## allow, so an off-by-one in either direction reds. A guard that only checks "far enough later"
	## passes a cooldown that is secretly 2 or 4.
	_selecting_fight()
	var cd: int = int(_bm.GROUP_ATTACK_COOLDOWN)
	_bm._formation_last_round = 10
	_bm.current_round = 10 + cd - 1
	assert_eq(_bm.formation_cooldown_remaining(), 1,
		"one round short of the cooldown must still have 1 round left")
	_bm.current_round = 10 + cd
	assert_eq(_bm.formation_cooldown_remaining(), 0,
		"the cooldown must be spent exactly GROUP_ATTACK_COOLDOWN rounds after the formation fired")


func test_firing_a_formation_puts_it_back_on_cooldown() -> void:
	## THE MECHANISM, not the outcome: the accepted path stamps the round it fired on, which is the
	## only thing that makes the NEXT one wait. Asserted on the stamp and on what it derives.
	var pc := _selecting_fight()
	_bm.current_round = 7
	_bm._formation_last_round = 0
	assert_eq(_bm.formation_cooldown_remaining(), 0, "CONTROL: round 7 with nothing fired yet must be ready")
	_bm.player_group_attack("formation", "four_heroes")
	assert_eq(int(_bm._formation_last_round), 7,
		"an accepted formation must stamp the round it fired on")
	assert_eq(_bm.formation_cooldown_remaining(), int(_bm.GROUP_ATTACK_COOLDOWN),
		"straight after firing, the full cooldown must be outstanding")
	assert_false(_said_cooldown(), "the accepted path must NOT emit the refusal line")
	## Either side of the selection -> execution handoff: _queue_action appends to pending_actions,
	## and _end_selection_turn can move it into execution_order before this line runs.
	assert_gt(int(_bm.pending_actions.size()) + int(_bm.execution_order.size()), 0,
		"the accepted formation must actually reach the engine — if nothing queued, the refusal arm below proves nothing")
	assert_true(pc.current_ap <= 4, "sanity: the actor is a real combatant with an AP pool")


func test_a_formation_on_cooldown_is_refused_and_says_why() -> void:
	## THE DEFECT ARM. Before this change the engine had nothing to refuse with, so this call queued
	## a second 10,267-damage strike one round after the first.
	_selecting_fight()
	_bm.current_round = 8
	_bm._formation_last_round = 7
	assert_gt(_bm.formation_cooldown_remaining(), 0, "CONTROL: the fixture must actually be on cooldown")
	_bm.player_group_attack("formation", "four_heroes")
	assert_eq(int(_bm.pending_actions.size()), 0,
		"a formation on cooldown must not queue an action")
	assert_eq(int(_bm.execution_order.size()), 0,
		"and it must not reach the execution order either")
	assert_true(_said_cooldown(),
			"the refusal must tell the player WHY in the battle log — a row that silently does nothing reads as a broken button: %s" % str(_log_lines))
	assert_eq(_bm.current_state, BattleManagerScript.BattleState.PLAYER_SELECTING,
		"the refusal must hand the turn back, or the player is left with no input")


func test_the_cooldown_governs_formations_only() -> void:
	## SCOPE, pinned where it was granted. Carmelo approved a cooldown on Four Heroes and declined
	## every other balance change, so All-Out Attack and Limit Break must stay ungated — and that is
	## not only paperwork: GameLoop:1110's publish smoke drives player_group_attack("all_out_attack")
	## and would fail the deploy chain if this change had widened by one string.
	_selecting_fight()
	_bm.current_round = 8
	_bm._formation_last_round = 7
	assert_gt(_bm.formation_cooldown_remaining(), 0, "CONTROL: a formation would be refused right now")
	_bm.player_group_attack("all_out_attack")
	assert_gt(int(_bm.pending_actions.size()) + int(_bm.execution_order.size()), 0,
		"All-Out Attack must still launch while a formation is on cooldown")
	assert_false(_said_cooldown(), "and it must not be told it is re-forming: %s" % str(_log_lines))


func test_the_cooldown_does_not_leak_into_the_next_battle() -> void:
	## A carried-over stamp would read the LAST battle's formation as this one's, so the first fight
	## after a long one would open with a free formation or a stuck row depending on the sign. This
	## is a source pin because start_battle reaches GameState, SaveSystem and the scene script — the
	## arithmetic above is the behaviour, this is the reset that feeds it.
	var src: String = FileAccess.get_file_as_string(MANAGER_PATH)
	var body: String = _func_body(src, "start_battle")
	assert_gt(body.length(), 0, "BattleManager must still declare start_battle")
	assert_true(body.contains("_formation_last_round = -GROUP_ATTACK_COOLDOWN"),
		"start_battle must reset the formation stamp to the EXPIRED sentinel — a carried-over stamp crosses the battle boundary, and a reset to 0 would cold-gate the opener instead")


func test_the_menu_asks_the_engine_instead_of_keeping_its_own_copy() -> void:
	## ⛔ REACHABILITY. Every arm above drives BattleManager directly, so all of them stay green if
	## the menu never asks — the row would be offered, the player would pick it, and the engine would
	## refuse with a log line and no explanation on the row. The menu's own comment says every AP
	## question goes to BattleManager because a second copy drifted once already; the cooldown is the
	## same kind of question and gets the same answer.
	var menu_src: String = FileAccess.get_file_as_string(MENU_PATH)
	var body: String = _func_body(menu_src, "build_command_menu_items_with_targets")
	assert_gt(body.length(), 0, "BattleCommandMenu must still declare build_command_menu_items_with_targets")
	assert_true(body.contains("BattleManager.formation_cooldown_remaining()"),
		"the formation row must take its cooldown from BattleManager, not from a second copy of the rule")
	assert_true(_bm.has_method("formation_cooldown_remaining"),
		"and the engine the menu asks must still answer that question")
	## The menu must not re-derive the number: a local constant is how the two sources drift.
	assert_false(body.contains("GROUP_ATTACK_COOLDOWN -"),
		"the menu must not do the cooldown arithmetic itself")


func test_the_default_party_can_actually_select_four_heroes() -> void:
	## THE ROW A PLAYER SEES, which is the half every arm above is blind to: a cooldown on a move
	## nobody can select would be busywork, and I had measured the formation's damage without once
	## checking that the starting party qualifies for it. Derived from the real default party rather
	## than from the four job names, so changing who you start with reds here instead of going quiet.
	var menu := BattleCommandMenu.new(null)
	var party: Array[Combatant] = []
	for custom in CharacterCustomization.create_default_party_with_script(CharacterCustomization):
		var jobs: Array = custom.starting_jobs
		assert_gt(jobs.size(), 0, "every default party member must start with a job")
		var c := _body(str(custom.name), 500)
		c.job = {"id": str(jobs[0])}
		party.append(c)
	assert_gt(party.size(), 3, "the default party must field at least four members for any formation")
	var formation: Dictionary = menu._detect_formation(party)
	assert_eq(str(formation.get("id", "")), "four_heroes",
		"the DEFAULT starting party must still qualify for Four Heroes — it is the row they get for free, and the one the cooldown now governs")
	assert_eq(int(formation.get("ap_cost", -1)), 2,
		"and at the 2 AP each every number in the measurement assumed")
