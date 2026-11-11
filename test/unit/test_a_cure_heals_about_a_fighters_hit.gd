extends GutTest

## struktured (main 23434): "Nerf her healing by A LOT; it should be near the Fighter's attack damage or less." Measured
## on .789: Sanatio healed ~80-100x a Fighter's hit (325 HP at Lv 1, 2155 at Lv 10), so every cast was a full heal. The
## reference is DERIVED, never a number typed here: the REAL starting party (GameLoop._create_party: the Fighter's
## sword, ring and weapon_mastery; the Cleric's staff, magic_ring and magic_boost) at each level, and the Fighter's plain
## hit on every monster authored at that level (median), which is the number he watches.

const LEVELS := [1, 2, 3, 4, 6, 8, 10, 12, 15, 18, 20]

var _gl: Node = null


func _party() -> Dictionary:
	_gl = load("res://src/GameLoop.gd").new()
	add_child_autofree(_gl)
	_gl._create_party()
	var out := {}
	for m in _gl.party:
		out[str(m.job.get("id", "")) if m.job else ""] = m
	return out


func _monsters_at(level: int) -> Array:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var all: Dictionary = parsed.get("monsters", parsed)
	var out: Array = []
	for id in all:
		var row = all[id]
		if row is Dictionary and int(row.get("level", 0)) == level and row.has("stats"):
			var s: Dictionary = row["stats"]
			var c := Combatant.new()
			c.initialize({"name": str(id), "max_hp": int(s.get("max_hp", 10)), "max_mp": 0, "attack": int(s.get("attack", 1)),
				"defense": int(s.get("defense", 1)), "magic": 1, "speed": 1})
			c.set_meta("monster_type", str(id))
			add_child_autofree(c)
			out.append(c)
	return out


## [level, median Fighter hit, Cure heal] for every level that has authored monsters.
func _table() -> Array:
	var p := _party()
	var f: Combatant = p.get("fighter")
	var c: Combatant = p.get("cleric")
	assert_not_null(f, "CONTROL: the starting party has a Fighter")
	assert_not_null(c, "CONTROL: and a Cleric")
	var rows: Array = []
	if f == null or c == null:
		return rows
	for lv in LEVELS:
		for u in [f, c]:
			u.job_level = lv
			u.recalculate_stats()
		var hits: Array = []
		for m in _monsters_at(lv):
			hits.append(BattleManager.estimate_attack_damage(f, m))
		if hits.is_empty():
			continue
		hits.sort()
		rows.append([lv, int(hits[hits.size() / 2]), BattleManager.heal_cast_amount(c, JobSystem.get_ability("cure"))])
	return rows


func test_a_cure_heals_no_more_than_a_fighters_hit_and_not_much_less() -> void:
	var rows := _table()
	assert_gt(rows.size(), 4, "CONTROL: enough levels have authored monsters to judge (%d)" % rows.size())
	var over: Array = []
	var under: Array = []
	for r in rows:
		if int(r[2]) > int(r[1]):
			over.append("Lv %d heals %d > hit %d" % [r[0], r[2], r[1]])
		if int(r[2]) * 2 < int(r[1]):
			under.append("Lv %d heals %d < half of hit %d" % [r[0], r[2], r[1]])
	assert_eq(over, [], "a single-target Cure heals at most what a Fighter's plain attack deals at that level")
	assert_eq(under, [], "CONTROL against a nerf to nothing: it still heals at least half of that hit")


func test_the_heal_ladder_keeps_its_order() -> void:
	var p := _party()
	var c: Combatant = p.get("cleric")
	assert_not_null(c, "CONTROL: a Cleric")
	if c == null:
		return
	c.job_level = 10
	c.recalculate_stats()
	var cure: int = BattleManager.heal_cast_amount(c, JobSystem.get_ability("cure"))
	var cura: int = BattleManager.heal_cast_amount(c, JobSystem.get_ability("cura"))
	assert_gt(cure, 0, "CONTROL: Cure heals")
	assert_gt(cura, cure, "Cura still out-heals Cure after the nerf, so no tier lost its place")
	assert_lt(cura, cure * 4, "and no tier was left at the old power (Cura %d vs Cure %d)" % [cura, cure])
