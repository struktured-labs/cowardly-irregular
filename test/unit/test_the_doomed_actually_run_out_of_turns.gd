extends GutTest

## ⛔ THE DOOM COUNTER HAD SIX CONSUMERS AND NO REACHABLE PRODUCER. `Combatant.doom_counter` ticks
## down each turn and KOs at zero (Combatant:901), BattleScene paints a "☠ N" badge for it, `cleanse`
## clears it in BOTH engines, the save carries it and BattleManager resets it at battle start. Its
## ONLY setter sat in `_execute_support_ability` — and all three abilities that author
## `effect: "doom"` are magic or physical, so not one of them could ever reach it:
##
##   death_sentence    magic     no chance  countdown 3   (inert by its own description, deliberately)
##   final_death       magic     0.2        countdown 1   permadeath_reaper
##   permakill_strike  physical  0.2        countdown 1   permadeath_reaper
##
## The damage path instead added a STATUS called "doom" — no tick, no badge, no KO, and `cleanse`
## dutifully "cured" it. The grind was worse: it cured a counter nothing on Earth could set.
##
## ⚠️ THE NUMBERS ARE AUTHORED, NOT INVENTED. 0.2 and countdown 1 are in abilities.json; the only
## thing that changed is that they now arrive. The live consequence is confined to
## `permadeath_reaper` — an autogrind meta-boss that already carries `save_deletion` — and the
## player keeps the counterplay that was already wired: one turn of warning, a visible badge, and
## esuna. Flagged to struktured rather than silently re-balanced.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"

var _saved_persist: bool
var _saved_party: Array
var _saved_enemies: Array


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	AutobattleSystem._test_disable_persistence = true
	seed(20260916)


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _combatant(name: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name
	c.max_hp = 9999
	c.current_hp = 9999
	c.attack = 60
	c.magic = 60
	c.defense = 5
	c.is_alive = true
	return c


func _doom_ability(type: String, countdown: int = 2) -> Dictionary:
	return {"type": type, "effect": "doom", "effect_chance": 1.0, "countdown": countdown,
		"damage_multiplier": 0.1, "power": 0.1}


func _cast_live(type: String, ability: Dictionary, target: Combatant) -> void:
	var caster := _combatant("Reaper")
	BattleManager.player_party.assign([caster] as Array[Combatant])
	BattleManager.enemy_party.assign([target] as Array[Combatant])
	if type == "magic":
		BattleManager._execute_magic_ability(caster, ability, [target])
	else:
		BattleManager._execute_physical_ability(caster, ability, [target])


## ── the defect, in behaviour, on both damage paths ────────────────────

func test_a_damaging_doom_sets_the_counter_the_hud_reads() -> void:
	for type in ["magic", "physical"]:
		var victim := _combatant("Mira")
		assert_eq(victim.doom_counter, -1, "CONTROL: %s target starts undoomed" % type)
		_cast_live(type, _doom_ability(type), victim)
		assert_eq(victim.doom_counter, 2,
			"%s: the authored countdown must reach doom_counter — pre-fix only _execute_support_ability set it" % type)
		assert_false(victim.has_status("doom"),
			"%s: and it is NOT left as an inert status, which is what the damage path used to add" % type)


func test_the_counter_actually_runs_out_and_kills() -> void:
	## The whole point of the key. A counter that is set but never lethal is the same nothing.
	var victim := _combatant("Mira")
	_cast_live("magic", _doom_ability("magic", 2), victim)
	victim.update_buff_durations()
	assert_eq(victim.doom_counter, 1, "one turn spent")
	assert_true(victim.is_alive, "and not dead yet — the warning turn the player gets")
	victim.update_buff_durations()
	assert_false(victim.is_alive, "the doomed run out of turns")


func test_cleanse_still_takes_it_off() -> void:
	## Counterplay was wired before the producer was; this pins that the two now meet.
	var victim := _combatant("Mira")
	_cast_live("physical", _doom_ability("physical", 3), victim)
	assert_eq(victim.doom_counter, 3, "CONTROL: doomed first, or the cure proves nothing")
	var cleric := _combatant("Talia")
	BattleManager.player_party.assign([cleric, victim] as Array[Combatant])
	BattleManager._execute_support_ability(cleric, {"type": "support", "effect": "cleanse"}, [victim])
	assert_true(victim.doom_counter <= 0, "esuna clears the countdown")
	victim.update_buff_durations()
	assert_true(victim.is_alive, "and the cured target survives the turn that would have killed them")


func test_the_opt_in_default_still_decides_a_chanceless_doom() -> void:
	## death_sentence authors `effect: "doom"` and NO chance, and its own description says
	## "(Currently no effect)". The 0.0 default is what keeps that true — this fix must not
	## accidentally arm the Necromancer's joke.
	var sentence: Dictionary = JobSystem.get_ability("death_sentence")
	assert_eq(str(sentence.get("effect", "")), "doom", "CONTROL: it authors the effect")
	assert_false(sentence.has("effect_chance"), "CONTROL: and no chance")
	for i in 40:
		var victim := _combatant("Mira")
		_cast_live("magic", sentence, victim)
		assert_eq(victim.doom_counter, -1, "a chanceless doom still dooms nobody")
		victim.free()


## ── the grind mirrors it ──────────────────────────────────────────────

func test_the_grind_dooms_what_the_battle_dooms() -> void:
	## The resolver already CURED doom in its cleanse arm while nothing could set it. Parity here is
	## not decoration: CLAUDE.md puts hours of play through this engine.
	var resolver = ResolverScript.new()
	var caster := _combatant("Reaper")
	for type in ["magic", "physical"]:
		var victim := _combatant("Mira")
		resolver._maybe_inflict_status(caster, victim, _doom_ability(type, 2), "final_death")
		assert_eq(victim.doom_counter, 2, "%s: the grind sets the same counter live does" % type)
		assert_false(victim.has_status("doom"), "%s: and not an inert status either" % type)
		victim.free()


func test_the_grind_leaves_a_chanceless_doom_alone_too() -> void:
	var resolver = ResolverScript.new()
	var caster := _combatant("Reaper")
	var sentence: Dictionary = JobSystem.get_ability("death_sentence")
	for i in 40:
		var victim := _combatant("Mira")
		resolver._maybe_inflict_status(caster, victim, sentence, "death_sentence")
		assert_eq(victim.doom_counter, -1, "the grind honours the same opt-in default")
		victim.free()


## ── the shape that caused it ──────────────────────────────────────────

func test_every_ability_that_authors_doom_is_typed_away_from_the_old_setter() -> void:
	## This is WHY the producer was unreachable, pinned so the reason cannot quietly stop being true.
	## If someone re-types one of these to `support` the old path would serve it and this arm says so.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var abilities: Dictionary = data.get("abilities", data)
	var authors: Array = []
	for id in abilities:
		var a = abilities[id]
		if a is Dictionary and str(a.get("effect", "")) == "doom":
			authors.append("%s:%s" % [id, a.get("type", "")])
	authors.sort()
	assert_eq(authors, ["death_sentence:magic", "final_death:magic", "permakill_strike:physical"],
		"the doom roster and its types — a change here is a balance decision, not a refactor: %s" % str(authors))


func test_one_producer_and_every_path_reaches_it() -> void:
	## The support arm and the damage path must set the counter through the SAME function, or the
	## countdown, the log and the badge can disagree by path — which is the class that produced this
	## bug in the first place (two verbatim copies of the status block, doom in neither).
	var code: String = GdSourceHelper.code_of(BM_PATH)
	assert_eq(code.count("target.doom_counter = countdown"), 1,
		"exactly one assignment sets the counter")
	var at: int = code.find("func _inflict_doom(")
	assert_gt(at, -1, "CONTROL: the producer survives stripping")
	var nxt: int = code.find("\nfunc ", at + 1)
	var producer: String = code.substr(at, (nxt - at) if nxt > at else 1200)
	assert_true(producer.contains("target.doom_counter = countdown"),
		"and it is _inflict_doom that owns it")
	assert_eq(code.count("_inflict_doom("), 3,
		"one declaration plus two callers — the support arm and the shared status owner")
	var owner_at: int = code.find("func _apply_ability_status(")
	assert_gt(owner_at, -1, "CONTROL: the shared status owner survives stripping")
	var owner_end: int = code.find("\nfunc ", owner_at + 1)
	assert_true(code.substr(owner_at, owner_end - owner_at).contains("_inflict_doom("),
		"the damage path reaches the producer through the one status owner both executors call")


## ── the countdown narrates itself ─────────────────────────────────────

func test_the_doom_counter_says_something_every_turn_it_runs() -> void:
	## ⛔ A LETHAL TIMER THAT SAID NOTHING. Doom deals no damage, so it fires neither
	## status_tick_damage nor hp_changed — the ☠ badge was the only feedback, and the kill itself
	## reached the player as a bare print() on stdout. Every other way to die in this engine narrates
	## itself; this one killed you in silence.
	var victim := _combatant("Mira")
	var heard: Array[String] = []
	var tap := func(msg: String) -> void: heard.append(msg)
	BattleManager.battle_log_message.connect(tap)
	var cb := BattleManager._on_doom_ticked.bind(victim)
	victim.doom_ticked.connect(cb)
	_cast_live("magic", _doom_ability("magic", 3), victim)
	assert_eq(victim.doom_counter, 3, "CONTROL: doomed for three, or the countdown is about nothing")
	heard.clear()
	victim.update_buff_durations()
	victim.update_buff_durations()
	victim.update_buff_durations()
	victim.doom_ticked.disconnect(cb)
	BattleManager.battle_log_message.disconnect(tap)
	assert_eq(heard.size(), 3, "one line per tick, not one at the start: %s" % str(heard))
	assert_true(str(heard[0]).contains("2 turns left"), "it counts DOWN and says the number: %s" % heard[0])
	assert_true(str(heard[1]).contains("1 turn left"), "and says 'turn' singular at one: %s" % heard[1])
	assert_true(str(heard[2]).contains("time runs out"), "and names the kill rather than letting them just drop: %s" % heard[2])
	assert_false(victim.is_alive, "CONTROL: the third tick really did kill them")


func test_an_undoomed_combatant_stays_quiet() -> void:
	## Anti-vacuity for the arm above: the emit must be gated on the counter, not on the turn.
	var bystander := _combatant("Talia")
	var heard: int = 0
	var cb := func(_n: int) -> void: heard += 1
	bystander.doom_ticked.connect(cb)
	for i in 5:
		bystander.update_buff_durations()
	bystander.doom_ticked.disconnect(cb)
	assert_eq(heard, 0, "an undoomed combatant emits nothing, %d turns running" % 5)


func test_the_listener_is_cached_and_released_like_died_is() -> void:
	## ⛔ THE ARM ABOVE CONNECTS THE HANDLER BY HAND, so the PRODUCTION wiring could be absent and it
	## would still pass — it supplies the thing it is meant to be checking. That is the hole this arm
	## exists to close, and the missing line was the connect itself: the first version of this test
	## pinned the cache, the disconnect and the clears, and DELETING
	## `combatant.doom_ticked.connect(dcb)` would have left every arm in this file green.
	##
	## ⚠️ HONEST LIMIT: this is a SOURCE pin, not a driven battle. `start_battle()` is not callable
	## from an isolated GUT run — it dies on "data.tree is null", which
	## test_battle_start_cleanup_regression documents and works around the same way. A behavioural arm
	## through the real setup would be strictly better and is not available here.
	var code: String = GdSourceHelper.code_of(BM_PATH)
	assert_true(code.contains("var _doom_callbacks: Dictionary = {}"), "the cache exists")
	assert_true(code.contains("combatant.doom_ticked.connect(dcb)"),
		"THE LOAD-BEARING LINE: start_battle must actually connect the handler, or the countdown is emitted to nobody in a real fight")
	assert_true(code.contains("_doom_callbacks[combatant] = dcb"), "the bound Callable is cached at connect")
	assert_true(code.contains("combatant.doom_ticked.disconnect(dcb)"), "and disconnected from that cache at cleanup")
	assert_eq(code.count("_doom_callbacks.clear()"), 2, "cleared where _died_callbacks is — at setup and at cleanup")
	## The handler is reached from the SAME loop that wires `died`, not from some other pass that a
	## later refactor could drop independently.
	var at: int = code.find("_died_callbacks[combatant] = cb")
	assert_gt(at, -1, "CONTROL: the died wiring survives stripping")
	assert_true(code.substr(at, 400).contains("combatant.doom_ticked.connect(dcb)"),
		"and it is wired in the same loop as died, where the cleanup already knows to look")


## ── the grind's own loop, not its helper ──────────────────────────────

func test_the_grind_round_actually_runs_the_counter_down_and_kills() -> void:
	## ⛔ MY GRIND ARM ABOVE SETS THE COUNTER BY CALLING _maybe_inflict_status DIRECTLY, so it proves
	## the producer and NOTHING about whether the grind ever spends it. Setting a timer nothing ticks
	## is the same nothing as not setting it — and this is the shape that has cost three lanes a green
	## arm today, so it gets driven through the resolver's OWN round loop instead.
	var resolver = ResolverScript.new()
	var caster := _combatant("Reaper")
	var victim := _combatant("Mira")
	resolver._player_party = [victim]
	resolver._enemy_party = [caster]
	resolver._maybe_inflict_status(caster, victim, _doom_ability("magic", 2), "final_death")
	assert_eq(victim.doom_counter, 2, "CONTROL: doomed for two, or the loop has nothing to spend")
	resolver._tick_round_start()
	assert_eq(victim.doom_counter, 1, "the grind's round start spends a turn of it")
	assert_true(victim.is_alive, "and not before the count is done")
	resolver._tick_round_start()
	assert_false(victim.is_alive, "the grind kills with it, like live does")


func test_the_grind_round_leaves_the_undoomed_alone() -> void:
	## Anti-vacuity: _tick_round_start touches every living combatant, so the kill above must come
	## from the counter rather than from the loop being lethal to anyone it visits.
	var resolver = ResolverScript.new()
	var bystander := _combatant("Talia")
	resolver._player_party = [bystander]
	resolver._enemy_party = []
	for i in 6:
		resolver._tick_round_start()
	assert_true(bystander.is_alive, "six rounds and an undoomed combatant is untouched")
	assert_eq(bystander.doom_counter, -1, "with the sentinel intact")
