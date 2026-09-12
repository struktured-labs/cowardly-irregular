extends GutTest

## The party chatted at turn start and then said nothing when it mattered.
##
## Every PC party line — ambient and reactive alike — passed through ONE cooldown
## keyed by combatant name, `PARTY_LINE_COOLDOWN_ROUNDS` = 8:
##
##     turn_start              fires on EVERY PC turn          <- always first
##     low_hp                  crossing below 25% HP
##     big_hit_taken           a crit, or > 30% max HP in one blow
##     used_signature_ability  the job's iconic spell
##
## `turn_start` fires at a PC's first turn, so it claimed the slot in round 1 and
## the three reactive triggers were unreachable until round 9. The dramatic lines
## — the ones written for the moment a character drops into danger — lost every
## race to "another day, another dungeon", for most of a battle.
##
## ⛔ AND THE LOW-HP CROSSING IS ONE-SHOT, so losing it loses it for good.
## `_on_damage_dealt_for_party_dialogue` fires low_hp only on `pre >= 25 and
## post < 25`. Once a PC is below the band no later hit can produce that
## crossing, so a suppressed low_hp is not deferred — it never happens again in
## that battle.
##
## FIXED by letting a reaction take the slot back from ambient chatter, and only
## from ambient chatter: a reaction cannot preempt another reaction, so the
## anti-spam intent of the cooldown is intact. `victory` still bypasses, as before.
##
## Volume is bounded by EVENTS, not by turns — a reaction needs a real crossing,
## crit or signature cast — so this cannot become chatter.

const AMBIENT := "turn_start"
const REACTIVE := "low_hp"
const OTHER_REACTIVE := "big_hit_taken"

var _bm
var _pc: Combatant


func before_each() -> void:
	_bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(_bm)
	_pc = Combatant.new()
	_pc.initialize({"name": "Rilla", "max_hp": 180, "max_mp": 40,
		"attack": 20, "defense": 18, "magic": 20, "speed": 12})
	add_child_autofree(_pc)
	_bm.player_party.append(_pc)


## Drive the real gate at a given round; report whether the trigger got through.
func _fire(event_kind: String, at_round: int) -> bool:
	_bm.current_round = at_round
	var before: int = int(_bm._party_line_cooldowns.get("Rilla", -999))
	_bm._maybe_fire_party_line(_pc, event_kind, {})
	return int(_bm._party_line_cooldowns.get("Rilla", -999)) != before


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_reaction_is_heard_through_ambient_chatter() -> void:
	## THE ARM. Pre-fix this returned false: turn_start held the slot until round 9.
	assert_true(_fire(AMBIENT, 1), "CONTROL: the first trigger of a battle must fire")
	assert_true(_fire(REACTIVE, 3),
		("a PC dropping below 25% HP two rounds after chatting says nothing. The "
		+ "low_hp crossing is one-shot, so this line is not delayed — it is lost."))


func test_a_reaction_is_heard_even_on_the_very_next_round() -> void:
	## The worst case for the old gate and the commonest in a real fight.
	assert_true(_fire(AMBIENT, 4), "CONTROL: ambient claims the slot")
	assert_true(_fire(OTHER_REACTIVE, 5), "a crit one round later must still be voiced")


# ── the anti-spam intent must survive ─────────────────────────────────────────

func test_one_reaction_does_not_open_the_floodgates() -> void:
	## A reaction may take the slot from chatter, never from another reaction —
	## otherwise a multi-hit round would narrate every blow.
	assert_true(_fire(AMBIENT, 1), "CONTROL: ambient claims it")
	assert_true(_fire(REACTIVE, 2), "the reaction preempts")
	assert_false(_fire(OTHER_REACTIVE, 3),
		"a second reaction inside the cooldown must still be suppressed")
	assert_false(_fire(REACTIVE, 4), "and so must a repeat of the same one")


func test_ambient_chatter_cannot_preempt_anything() -> void:
	## The rule is one-directional. Chatter waits its turn.
	assert_true(_fire(REACTIVE, 1), "CONTROL: the reaction fires first here")
	assert_false(_fire(AMBIENT, 2), "chatter must not interrupt a reaction")
	assert_false(_fire(AMBIENT, 5), "nor later inside the same cooldown")


func test_the_cooldown_still_expires_normally() -> void:
	## CORRECT-WORK: preemption is an exception to the cooldown, not a removal.
	assert_true(_fire(AMBIENT, 1), "CONTROL")
	assert_false(_fire(AMBIENT, 8), "one round short must still be blocked")
	assert_true(_fire(AMBIENT, 9), "and the cooldown must expire on schedule")


func test_victory_still_bypasses_the_cooldown() -> void:
	## CONTROL: victory was already exempt and must stay so — the battle is over,
	## and _dispatch_victory_party_line has already chosen an alive speaker.
	assert_true(_fire(REACTIVE, 1), "CONTROL: something claims the slot")
	assert_true(_fire("victory", 2), "the victory line must never be swallowed")


# ── controls ──────────────────────────────────────────────────────────────────

func test_a_fresh_battle_starts_with_no_holder() -> void:
	## CONTROL on the new dict: it must be cleared with the cooldowns, or a
	## reaction could preempt a hold left over from the PREVIOUS battle.
	assert_true(_fire(AMBIENT, 1), "CONTROL")
	assert_eq(str(_bm._party_line_last_kind.get("Rilla", "")), AMBIENT,
		"the holder must be recorded, or preemption cannot tell ambient from reactive")
	## Clearing it BY HAND here proved nothing — measured: dropping the real clear
	## from start_battle left this arm green. So the arm reads start_battle itself.
	## Stripped and scoped to the function: a fixed window over raw source is
	## measured in prose as much as code.
	var src: String = _code_only(
		FileAccess.get_file_as_string("res://src/battle/BattleManager.gd"),
		"func start_battle(players: Array[Combatant], enemies: Array[Combatant]) -> void:")
	var at: int = src.find("func start_battle(")
	assert_true(at != -1, "CONTROL: start_battle must exist")
	var ends_at: int = src.find("\nfunc ", at + 1)
	if ends_at == -1:
		ends_at = src.length()
	var body: String = src.substr(at, ends_at - at)
	assert_true(body.find("_party_line_cooldowns.clear()") != -1,
		"CONTROL: start_battle must still clear the cooldowns")
	assert_true(body.find("_party_line_last_kind.clear()") != -1,
		("start_battle no longer clears the holder, so a hold left by the PREVIOUS "
		+ "battle decides whether the first reaction of THIS one may preempt."))


func test_the_event_vocabulary_matches_what_actually_fires() -> void:
	## THE PREMISE. The split is only meaningful if these are the real event ids.
	## If BattleManager stops firing one, or AMBIENT gains a member, the arms above
	## are classifying strings nothing produces.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_false(src.is_empty(), "CONTROL: source must load")
	for kind in [AMBIENT, REACTIVE, OTHER_REACTIVE, "used_signature_ability", "victory"]:
		assert_true(src.find("_maybe_fire_party_line(") != -1 and src.find("\"%s\"" % kind) != -1,
			"'%s' must still be an event this file fires" % kind)
	assert_eq(_bm.AMBIENT_PARTY_LINE_EVENTS, ([AMBIENT] as Array[String]),
		("the ambient set changed to %s. Everything here assumes exactly one ambient "
		+ "event; a second one needs its own arms.") % str(_bm.AMBIENT_PARTY_LINE_EVENTS))


func test_the_gate_is_reached_at_all() -> void:
	## CONTROL: every arm reads the cooldown dict as the signal that a trigger got
	## through. A gate that rejected on an earlier guard — not in player_party, not
	## alive — would make every arm read false for the wrong reason.
	assert_true(_pc in _bm.player_party, "the fixture must be in the party")
	assert_true(_pc.is_alive, "and alive")
	assert_true(_fire(AMBIENT, 1), "so a first trigger must pass the gate")


## Strip both comment forms before a presence assert; `must_survive` is a known
## code site, so an over-eager stripper cannot pass for a correct one.
func _code_only(src: String, must_survive: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	var in_doc: bool = false
	for line in src.split("\n"):
		var hash_at: int = line.find("#")
		var code: String = line if hash_at == -1 else line.substr(0, hash_at)
		var trimmed: String = code.strip_edges()
		if in_doc:
			if trimmed.ends_with("\"\"\""):
				in_doc = false
			continue
		if trimmed.begins_with("\"\"\""):
			if trimmed.count("\"\"\"") % 2 == 1:
				in_doc = true
			continue
		out.append(code)
	var stripped: String = "\n".join(out)
	assert_true(stripped.find(must_survive) != -1,
		("STRIPPER CONTROL: '%s' is a known code site and must survive stripping.")
		% must_survive)
	return stripped
