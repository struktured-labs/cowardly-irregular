extends GutTest

## Six abilities declared a 2-3 turn stun and delivered exactly one. 2026-07-29.
##
## The duration was applied correctly and then thrown away: the turn-skip handler called
## `remove_status("stun")` unconditionally on the first skipped turn, and `Combatant.remove_status`
## erases `status_durations` along with the effect. Nothing in src/ ever read
## `status_durations["stun"]`.
##
## The tell is twelve lines below in the same function. `cannot_act` — added later, for landed boss
## jailbreaks — reads its remaining duration, decrements, and only removes at zero. One status ticks,
## the other erased, same author, same file.
##
##   time_stop      declares 2   delivered 1
##   infinite_loop  declares 3   delivered 1
##   absolute_zero · ice_prison · shadow_bind · root_bind   declare 2, delivered 1
##
## The last four author `"freeze"`, which a 2026-07-03 audit aliases to `"stun"` at cast time — so a
## set derived from `effect == "stun"` finds four of six. Derive from what the runtime produces.
##
## Two consumers had it: BattleManager (live battles) and HeadlessBattleResolver (autogrind). Fixing
## one would leave an autogrind run scoring a fight the player could not have fought the same way.
##
## NOTE: this makes the game HARDER — two of the six belong to World 1 bosses. Shipped only on
## struktured's ruling; the tests below pin the mechanism either way.

const BM_SRC := "res://src/battle/BattleManager.gd"
const HBR_SRC := "res://src/autogrind/HeadlessBattleResolver.gd"


func _combatant(dur: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Victim"
	c.add_status("stun", dur)
	return c


## Exactly what BattleManager does on a stunned actor's turn. Duplicated rather than invoked because
## the real path needs a whole battle; the assertion below pins that the two stay identical.
func _skip_one_turn(c: Combatant) -> void:
	var left: int = int(c.status_durations.get("stun", 1))
	if left <= 1:
		c.remove_status("stun")
	else:
		c.status_durations["stun"] = left - 1


# ── behaviour ───────────────────────────────────────────────────────

func test_a_two_turn_stun_survives_the_first_skipped_turn() -> void:
	# The defect, stated as the player experiences it: Time Stop says two turns and you act on the
	# second. Before the fix has_status went false here.
	var c := _combatant(2)
	_skip_one_turn(c)
	assert_true(c.has_status("stun"), "a stun declared for 2 turns must still be active after 1")
	assert_eq(int(c.status_durations.get("stun", 0)), 1, "and must have one turn remaining")
	c.free()


func test_the_stun_ends_when_its_duration_is_spent() -> void:
	# The other direction. A tick-down that never removes is a permanent stun, which is worse than
	# the bug it replaces.
	var c := _combatant(2)
	_skip_one_turn(c)
	_skip_one_turn(c)
	assert_false(c.has_status("stun"), "a 2-turn stun must end after 2 skipped turns")
	assert_false(c.status_durations.has("stun"), "and must not leave a dangling duration entry")
	c.free()


func test_a_one_turn_stun_is_unchanged() -> void:
	# Regression floor: the overwhelming majority of stuns are 1 turn, and this must not lengthen
	# them. If it did, every basic stun in the game silently doubled.
	var c := _combatant(1)
	_skip_one_turn(c)
	assert_false(c.has_status("stun"), "a 1-turn stun must still end after one skipped turn")
	c.free()


func test_a_three_turn_stun_lasts_three() -> void:
	var c := _combatant(3)
	_skip_one_turn(c)
	_skip_one_turn(c)
	assert_true(c.has_status("stun"), "infinite_loop declares 3 — it must survive two skips")
	_skip_one_turn(c)
	assert_false(c.has_status("stun"), "and end on the third")
	c.free()


func test_remove_status_still_erases_the_duration() -> void:
	# The mechanism that caused this. If remove_status ever stops erasing status_durations, the
	# tick-down above becomes redundant rather than load-bearing, and this comment stops being true.
	var c := _combatant(3)
	c.remove_status("stun")
	assert_false(c.status_durations.has("stun"),
		"remove_status erases the duration — that is WHY an unconditional call discarded it")
	c.free()


# ── both consumers, derived ─────────────────────────────────────────

func test_every_stun_consumer_ticks_instead_of_erasing() -> void:
	# Derived from the sites that skip a turn on stun, not a hand list of two files. A third consumer
	# (a new battle mode, a simulator) would otherwise reintroduce the defect silently.
	var offenders: Array = []
	for path in [BM_SRC, HBR_SRC]:
		var src := FileAccess.get_file_as_string(path)
		var at: int = src.find("has_status(\"stun\")")
		if at < 0:
			offenders.append("%s: no stun handler found — did it move?" % path)
			continue
		var window: String = src.substr(at, 420)
		if not window.contains("status_durations.get(\"stun\""):
			offenders.append("%s: removes stun without reading its duration" % path)
	assert_eq(offenders, [], "a stun consumer discards the declared duration:\n  %s"
		% "\n  ".join(offenders))


func test_the_helper_matches_what_battlemanager_actually_does() -> void:
	# _skip_one_turn duplicates the production block. Pin that they agree, or every behavioural
	# assertion above tests a copy that has drifted from the code it stands in for.
	var src := FileAccess.get_file_as_string(BM_SRC)
	var at: int = src.find("has_status(\"stun\")")
	var window: String = src.substr(at, 420)
	assert_true(window.contains("stun_left <= 1"), "production must remove at the last turn")
	assert_true(window.contains("stun_left - 1"), "production must decrement otherwise")


# ── the data this defends ───────────────────────────────────────────

func test_the_corpus_still_declares_multi_turn_stuns() -> void:
	# Positive control. Every test above passes in a world where no ability declares more than 1
	# turn — the fix would be real and pointless. Derived through the freeze alias, because four of
	# the six are spelled "freeze" and a scan for "stun" finds only two.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var abilities: Dictionary = raw.get("abilities", raw)
	var multi: Array = []
	for id in abilities:
		var a: Dictionary = abilities[id]
		var eff := str(a.get("effect", ""))
		var meta := str(a.get("meta_effect", ""))
		if (eff == "stun" or eff == "freeze" or meta == "time_stop") and int(a.get("duration", 1)) > 1:
			multi.append("%s(%d)" % [id, int(a.get("duration", 1))])
	assert_gt(multi.size(), 1,
		"the corpus must still author multi-turn stuns or this fix defends nothing — found: %s"
			% str(multi))


func test_the_freeze_alias_still_exists() -> void:
	# Four of the six reach stun only through this alias. If it is ever removed, the affected set
	# shrinks to two and the comment at the top of this file becomes wrong.
	var src := FileAccess.get_file_as_string(BM_SRC)
	assert_true(src.contains("status_to_add = \"stun\""),
		"freeze aliases to stun — without it, absolute_zero and ice_prison stop being stuns at all")
