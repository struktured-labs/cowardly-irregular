extends GutTest

## BURN dealt zero damage — five fire abilities applied a decorative status (2026-07-30).
##
## `Combatant.update_buff_durations` ticks the fire DoT on `"burning"`:
##
##     if "burning" in status_effects and is_alive:
##         var burn_damage = max(1, int(max_hp * 0.08))   # 8% max HP per turn
##
## Nothing authors `"burning"`. Five abilities author `"burn"` —
## boiler_burst, fire_breath, flame_wall, scalding_mist, steam_vent — and
## `_RANDOM_DEBUFF_POOL` can roll it too. The apply path accepts both spellings,
## so the status landed, showed its BURN badge, appeared in the log, and ticked
## for nothing.
##
## Measured before the fix, on real Combatants through the real tick:
##     burn     100 -> 100      (0 damage)
##     burning  100 ->  92      (8, the status nothing authors)
##     poison   100 ->  95      (control: a DoT that works)
##
## Fixed by aliasing at APPLY, next to the existing freeze->stun alias in the
## same function, rather than widening the tick. The cleanse list
## (_limit_break_cleanse) and the negative-status lists already say "burning";
## widening only the tick would have left burn uncleansable — trading a dead DoT
## for a status no dispel could remove.
##
## Found by joining statuses CHECKED in code against statuses ever APPLIED or
## authored. That join returned exactly one name.

const BM_SRC := "res://src/battle/BattleManager.gd"


func _victim() -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "Victim"
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	return c


## ── the mechanism ────────────────────────────────────────────────────

func test_the_dot_ticks_on_burning() -> void:
	# The premise. If this stops being true the alias below defends nothing.
	var c: Combatant = _victim()
	c.add_status("burning", 3)
	c.update_buff_durations()
	assert_eq(c.current_hp, 92,
		"the fire DoT is 8%% of max HP per turn on 'burning' — if this changed, the alias is pinned to the wrong name")


func test_poison_still_ticks() -> void:
	# Independent control: a DoT that was never broken. If BOTH this and the
	# burn case read 0, the harness is not ticking at all and every assertion
	# in this file is vacuous.
	var c: Combatant = _victim()
	c.add_status("poison", 3)
	c.update_buff_durations()
	assert_lt(c.current_hp, 100,
		"poison must still deal damage — if it does not, this test file is measuring nothing")


## ── the alias, at both sites ─────────────────────────────────────────

func test_apply_path_aliases_burn_to_burning() -> void:
	# Source-level: the alias lives inside the ability-resolution body, which
	# needs a full cast to drive. Both sites, because the effect application is
	# duplicated and fixing one would leave the other dead.
	var src := FileAccess.get_file_as_string(BM_SRC)
	assert_ne(src, "", "the file must be readable or this assertion is vacuous")
	var count: int = src.count("status_to_add = \"burning\"")
	assert_eq(count, 2,
		"both effect-application sites must alias burn->burning — there are two, and the freeze alias is duplicated across the same pair")


func test_freeze_alias_still_present() -> void:
	# The precedent this was modelled on. If freeze->stun is ever removed, the
	# burn alias sitting beside it should be re-examined at the same time.
	var src := FileAccess.get_file_as_string(BM_SRC)
	assert_eq(src.count("status_to_add = \"stun\""), 2,
		"freeze->stun aliases at both sites; burn->burning was added alongside it")


## ── the corpus this defends ──────────────────────────────────────────

func test_abilities_still_author_burn() -> void:
	# POSITIVE CONTROL. Every assertion above passes in a world where no ability
	# authors "burn" at all — the alias would be correct and pointless. Derived
	# from the shipped data so a rename shows up here rather than silently
	# retiring the fix.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var abilities: Dictionary = raw.get("abilities", raw)
	var authors: Array[String] = []
	for id in abilities:
		var a: Dictionary = abilities[id]
		if str(a.get("effect", "")) == "burn":
			authors.append(str(id))
	assert_gt(authors.size(), 0,
		"abilities must still author 'burn' or this alias defends nothing — found: %s" % str(authors))


func test_nothing_authors_burning_directly() -> void:
	# The other half of why the alias is needed rather than a data rename: the
	# DoT's own spelling appears nowhere in the ability data, so every burn in
	# the game arrives through the alias.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var abilities: Dictionary = raw.get("abilities", raw)
	var direct: Array[String] = []
	for id in abilities:
		if str((abilities[id] as Dictionary).get("effect", "")) == "burning":
			direct.append(str(id))
	assert_eq(direct, [] as Array[String],
		"nothing authors 'burning' directly; if that changes, both spellings are live and the alias needs revisiting")
