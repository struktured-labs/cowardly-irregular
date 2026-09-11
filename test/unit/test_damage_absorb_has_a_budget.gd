extends GutTest

## `fill_the_void` authors `absorb_amount: 1000`. Nothing read it — the comment on the handler said
## so out loud ("documented in the data but not enforced, duration is the limiter"), so this was a
## decision rather than an oversight. The decision is wrong for the one monster that owns it.
##
## `fill_the_void` belongs to `the_absence`, a COMMON W6 enemy (enemy_pools + AbstractOverworld's
## roaming set) which ALSO carries a passive 30% damage→heal conversion. With duration as the only
## limiter, one cast made it immune to a five-member party AND healed it by every point they dealt,
## for two full rounds. That does not make the fight harder, it makes it longer and unreadable —
## the player's hits produce green numbers on the enemy and no feedback about what would work.
##
## So absorb_amount is now a BUDGET: the ward eats damage until it is spent, the overflow lands in
## the SAME hit, and the status breaks. An OMITTED absorb_amount still means unlimited, because
## that is the rule every already-shipped caller was written against — checked below, not assumed.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"

func _make(display_name: String) -> Combatant:
	var c: Combatant = (load(COMBATANT_PATH) as GDScript).new()
	c.initialize({
		"name": display_name, "max_hp": 500, "max_mp": 50,
		"attack": 20, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c

## Measured on an UNWARDED combatant, so it cannot move with a mutation to the absorb block.
func _plain_hit(raw: int) -> int:
	var c := _make("Ruler")
	c.current_hp = c.max_hp
	var d: int = c.take_damage(raw, false)
	assert_gt(d, 0, "CONTROL: an unwarded hit deals damage (%d)" % d)
	return d

func test_the_budget_is_spent_down_and_the_ward_breaks() -> void:
	var d := _plain_hit(30)
	var c := _make("Warded")
	c.current_hp = 200
	c.add_status("damage_absorb", 5)
	c.set_meta("_damage_absorb_budget", d + 5)

	assert_eq(c.take_damage(30, false), 0, "the first hit is inside the budget — fully absorbed")
	assert_true(c.has_status("damage_absorb"), "5 points of ward remain, so it must still stand")

	var second: int = c.take_damage(30, false)
	assert_gt(second, 0, "the second hit exhausts the ward and the OVERFLOW must land, not vanish")
	assert_false(c.has_status("damage_absorb"), "a spent ward must break rather than absorb forever")

func test_the_overflow_is_the_part_the_budget_could_not_pay() -> void:
	## Exactness matters: rounding the overflow to "something" would let a 1-point ward erase a
	## 200-point hit and still read as a pass.
	var d := _plain_hit(30)
	var c := _make("Thin")
	c.current_hp = 200
	c.add_status("damage_absorb", 5)
	c.set_meta("_damage_absorb_budget", 4)
	assert_eq(c.take_damage(30, false), d - 4, "overflow = damage - remaining budget, exactly")

func test_the_remaining_budget_falls_by_what_it_paid() -> void:
	## The version of this I wrote first asserted that a SPENT ward stops absorbing, and it could
	## not go red under any of three mutations — a ward at 0 absorbs nothing whether or not the
	## status broke, so the assertion was seconded by arithmetic. This pins the decrement itself,
	## which is the property a "reset the budget each hit" bug would break while every downstream
	## symptom still looked correct.
	var d := _plain_hit(30)
	var c := _make("Ledger")
	c.current_hp = 200
	c.add_status("damage_absorb", 5)
	c.set_meta("_damage_absorb_budget", d * 3)
	c.take_damage(30, false)
	assert_eq(int(c.get_meta("_damage_absorb_budget", -1)), d * 2,
		"one absorbed hit must cost the ward exactly what it absorbed")
	c.take_damage(30, false)
	assert_eq(int(c.get_meta("_damage_absorb_budget", -1)), d,
		"and the second must too — a ward that refills is an unlimited ward wearing a number")

func test_an_absorbed_hit_still_heals() -> void:
	## The ability's actual identity. Budgeting it must not quietly turn it into a shield.
	var c := _make("Feeder")
	c.current_hp = 100
	c.add_status("damage_absorb", 5)
	c.set_meta("_damage_absorb_budget", 999)
	assert_eq(c.take_damage(30, false), 0, "inside budget")
	assert_gt(c.current_hp, 100, "absorbed damage must come back as HP")

func test_no_budget_meta_is_still_unlimited() -> void:
	## CONTROL for the compatibility promise. Every pre-existing caller applies the status with no
	## meta at all; if that silently became a zero-point ward, the ability would die the other way.
	var c := _make("Legacy")
	c.current_hp = 100
	c.add_status("damage_absorb", 5)
	for i in 6:
		assert_eq(c.take_damage(30, false), 0, "hit %d must still be fully absorbed" % i)
	assert_true(c.has_status("damage_absorb"), "an unbudgeted ward wears off on DURATION only")

func test_the_handler_parks_the_authored_amount() -> void:
	## The join. A budget the ability never installs is a mechanic with no data behind it.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if bm == null or js == null or not js.abilities.has("fill_the_void"):
		pending("BattleManager + JobSystem autoloads with fill_the_void required")
		return
	var c := _make("Target")
	var ability: Dictionary = js.abilities["fill_the_void"].duplicate(true)
	var targets: Array[Combatant] = [c]
	bm._execute_support_ability(null, ability, targets)
	assert_true(c.has_status("damage_absorb"), "CONTROL: the status is still applied")
	assert_eq(int(c.get_meta("_damage_absorb_budget", -1)), int(ability["absorb_amount"]),
		"the ward must be worth exactly what the ability authored")

func test_the_ability_still_authors_a_finite_budget() -> void:
	## The premise. If absorb_amount is ever deleted from fill_the_void the mechanic goes back to
	## unlimited SILENTLY, because that is the compatibility rule — so pin it where it is visible.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	var abilities: Dictionary = (parsed as Dictionary).get("abilities", parsed)
	var a: Dictionary = abilities.get("fill_the_void", {})
	assert_eq(str(a.get("effect", "")), "damage_absorb", "CONTROL: still the absorb ability")
	assert_gt(int(a.get("absorb_amount", 0)), 0,
		"fill_the_void must author a finite ward — without it the_absence is immune for two rounds")

## ── The ward must survive a snapshot with its bound intact ────────────────────────────────────
## Found by asking cowir-sfx's closing question of my own fix: what did fixing this file stop me
## looking at? `status_effects` round-trips through to_dict/from_dict and the Time Mage's
## `create_save` explicitly quicksaves DURING battle. The budget lived only in Object meta, so a
## snapshot restored the ward WITHOUT it — and "no budget" legitimately means unlimited, so the
## round trip silently restored the exact defect the budget exists to prevent.
##
## Not reachable today: `fill_the_void` is self-target and monster-only, and enemies are not
## persisted. It is pinned anyway because the consequence is the original bug and there is no
## natural discovery path — the same reasoning tick 151 used one family member earlier, when
## status_durations was lost on rewind and every active poison became permanent.

func test_the_budget_survives_a_round_trip() -> void:
	var c := _make("Snapshot")
	c.add_status("damage_absorb", 5)
	c.set_meta("_damage_absorb_budget", 137)
	var restored := _make("Restored")
	restored.from_dict(c.to_dict())
	assert_true(restored.has_status("damage_absorb"), "CONTROL: the status itself round-trips")
	assert_eq(int(restored.get_meta("_damage_absorb_budget", -1)), 137,
		"the ward must come back worth what was left of it, not unlimited")

func test_a_restored_ward_still_spends_and_breaks() -> void:
	## Behavioural, because carrying the number across is not the same as the restored combatant
	## USING it — a restored ward that absorbs without decrementing is the original bug again.
	var d := _plain_hit(30)
	var c := _make("Snapshot")
	c.current_hp = 200
	c.add_status("damage_absorb", 5)
	c.set_meta("_damage_absorb_budget", 4)
	var restored := _make("Restored")
	restored.from_dict(c.to_dict())
	restored.current_hp = 200
	assert_eq(restored.take_damage(30, false), d - 4, "the restored ward pays what it has, then the overflow lands")
	assert_false(restored.has_status("damage_absorb"), "and it breaks, exactly as it would have before the snapshot")

func test_a_save_written_before_this_shipped_keeps_the_unbudgeted_rule() -> void:
	## Old saves have no such key, and an unbudgeted ward is what they recorded. Reading absence as
	## a ZERO budget would retroactively delete a mechanic from every existing save.
	var c := _make("Legacy")
	var data: Dictionary = c.to_dict()
	data.erase("damage_absorb_budget")
	data["status_effects"] = ["damage_absorb"]
	var restored := _make("Restored")
	restored.from_dict(data)
	restored.current_hp = 100
	assert_eq(restored.take_damage(30, false), 0, "an absent key must still mean unlimited, not spent")
