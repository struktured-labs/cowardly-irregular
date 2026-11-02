extends GutTest

## struktured 2026-11-01: the Ice Wolf crit-one-shot his back line (Cleric 140 vs 126, Rogue 181 vs 161, Mage 179 vs 148). Ruling:
## "tone it down but only VERY slightly — make it beatable if you're lucky and/or clever". A general crit cap was rejected, so only the
## wolf's own attack moved. This pins the INTENT both ways, derived from the data rather than a stat value:
##   clever — a full-HP back-liner who Defers outlives the wolf's biggest crit;
##   still dangerous — an undefended back-liner's average crit stays near the whole of their HP, so it is no stroll.
## Survivable if you Defer. Undefended odds vary by monster: the wolf is ~a coin flip, the bone_warden is lethal (cowir-main 21335).
## cowir-main 21325 widened arm 1 to every W1 trash monster: the bone_warden was the one other that failed (attack 162 → 143).

const WOLF := "ice_wolf"
const BACK_ROW := ["cleric", "mage", "bard", "rogue"]
## BattleManager's default variance ceiling (volatility's widest band is wider only under chaos).
const VARIANCE_MAX := 1.15


func _monsters() -> Dictionary:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	return d.get("monsters", d)


## Pool id lists, flattened from either pool shape.
func _pools() -> Dictionary:
	var pools: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_pools.json"))
	pools = pools.get("pools", pools)
	var out := {}
	for key in pools:
		var ids: Variant = pools[key]
		if ids is Dictionary:
			ids = (ids as Dictionary).get("enemies", (ids as Dictionary).get("monsters", []))
		if ids is Array:
			out[key] = ids
	return out


## Every non-boss monster sharing a field with the wolf (cowir-main 21320: the ruling covers its band, derived, not hand-listed).
func _wolf_band() -> Array:
	var mons := _monsters()
	var band: Array = []
	for ids in _pools().values():
		if not (WOLF in ids):
			continue
		for id in ids:
			if mons.has(str(id)) and not bool((mons[str(id)] as Dictionary).get("boss", false)) and not (str(id) in band):
				band.append(str(id))
	return band


## The level of a party that meets the wolf: its toughest companion in the gentlest field it roams.
func _meeting_level() -> int:
	return _meeting_level_of(WOLF)


func _meeting_level_of(who: String) -> int:
	var mons := _monsters()
	var best := 1 << 20
	for ids in _pools().values():
		if not (who in ids):
			continue
		var top := 0
		for id in ids:
			if str(id) != who and mons.has(str(id)):
				top = maxi(top, int((mons[str(id)] as Dictionary).get("level", 0)))
		if top > 0:
			best = mini(best, top)
	return best if best < (1 << 20) else 0


func _member(job_id: String, level: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = job_id.capitalize()
	add_child_autofree(c)
	c.job = JobSystem.get_job(job_id)
	c.job_level = level
	c.recalculate_stats()
	c.current_hp = c.max_hp
	c.is_alive = true
	return c


func _crit(variance: float, who: String = WOLF) -> int:
	var atk: int = int(((_monsters()[who] as Dictionary).get("stats", {}) as Dictionary).get("attack", 0))
	return int(int(atk * variance) * 1.5)


func test_a_back_liner_who_defers_outlives_the_wolfs_biggest_crit() -> void:
	var level := _meeting_level()
	assert_gt(level, 0, "CONTROL: the wolf roams at least one field with companions")
	for job_id in BACK_ROW:
		var c := _member(job_id, level)
		c.is_defending = true
		var taken: int = c.take_damage(_crit(VARIANCE_MAX))
		assert_gt(c.current_hp, 0, "a full-HP %s who Defers must outlive the wolf's biggest crit (took %d of %d at level %d)"
			% [job_id, taken, c.max_hp, level])


func test_an_undefended_back_liner_still_fears_the_crit() -> void:
	var level := _meeting_level()
	var frailest := 1.0
	for job_id in BACK_ROW:
		var c := _member(job_id, level)
		var taken: int = c.take_damage(_crit(1.0))
		frailest = minf(frailest, float(c.max_hp) / float(maxi(1, taken)))
	assert_lt(frailest, 1.1, "the wolf must stay dangerous: its average crit should take ~90%+ of the frailest back-liner's HP")


## Every non-boss monster in a World 1 pool: pools whose every member stands below the W1 final boss's level.
func _w1_trash() -> Array:
	var mons := _monsters()
	var cap: int = int((mons.get("chancellor_mordaine", {}) as Dictionary).get("level", 0))
	var out: Array = []
	for ids in _pools().values():
		var w1 := true
		for id in ids:
			if mons.has(str(id)) and int((mons[str(id)] as Dictionary).get("level", 0)) >= cap:
				w1 = false
		if not w1:
			continue
		for id in ids:
			if mons.has(str(id)) and not bool((mons[str(id)] as Dictionary).get("boss", false)) and not (str(id) in out):
				out.append(str(id))
	return out


func test_every_w1_trash_monster_can_be_outlasted_the_same_way() -> void:
	var band := _w1_trash()
	assert_true(WOLF in band and "bone_warden" in band and band.size() >= 20, "CONTROL: the W1 trash set is derived from the pools: %d" % band.size())
	for wolf_mate in _wolf_band():
		assert_true(wolf_mate in band, "CONTROL: the wolf's own band sits inside it (%s)" % wolf_mate)
	for who in band:
		var level := maxi(1, _meeting_level_of(str(who)))
		for job_id in BACK_ROW:
			var c := _member(job_id, level)
			c.is_defending = true
			c.take_damage(_crit(VARIANCE_MAX, str(who)))
			assert_gt(c.current_hp, 0, "a full-HP %s who Defers must outlive %s's biggest crit at level %d" % [job_id, who, level])
