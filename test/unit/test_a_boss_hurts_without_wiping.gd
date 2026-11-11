extends GutTest

## cowir-autogrind's geared sweep (23847): from Glacius up, every W1 boss beat a best-shop-kit party at its own level
## 0 of 10, dealing half the party's HP or more each round. The cause was one number per boss (battle 23851): its
## strongest ALL-PARTY hit as a share of an average member's HP. Pyrroth's was the one that made a fight (10/10 in 8
## rounds); Glacius 1.4x that, Umbraxis 1.4x, Mordaine 2.5x. Tuned as data (multipliers, Mordaine's MAG; HP untouched).
## The reference is DERIVED: the real starting party (GameLoop._create_party) at the boss's level, its mean max HP.

const BOSSES := ["fire_dragon", "ice_dragon", "lightning_dragon", "shadow_dragon", "chancellor_mordaine"]
## A boss's strongest all-party hit (raw: stat x multiplier, before defence) over the starting party's mean max HP.
const MAX_SHARE := 0.80
## And not so soft that W1's climax fights stop hurting.
const MIN_SHARE := 0.50

var _gl: Node = null


func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	return (parsed as Dictionary).get("monsters", parsed) if parsed is Dictionary else {}


func _party_mean_hp(level: int) -> float:
	if _gl == null:
		_gl = load("res://src/GameLoop.gd").new()
		add_child_autofree(_gl)
		_gl._create_party()
	var total := 0.0
	for m in _gl.party:
		m.job_level = level
		m.recalculate_stats()
		total += float(m.max_hp)
	return total / float(maxi(1, _gl.party.size()))


## [ability id, raw hit] of the boss's strongest all-enemies damage ability.
func _strongest_all_party_hit(row: Dictionary) -> Array:
	var best := ["", 0.0]
	var stats: Dictionary = row.get("stats", {})
	for id in row.get("abilities", []):
		var a: Dictionary = JobSystem.get_ability(str(id))
		if str(a.get("target_type", "")) != "all_enemies" or float(a.get("damage_multiplier", 0.0)) <= 0.0:
			continue
		var stat: float = float(stats.get("magic" if str(a.get("type", "")) == "magic" else "attack", 0))
		var raw: float = stat * float(a["damage_multiplier"])
		if raw > float(best[1]):
			best = [str(id), raw]
	return best


func test_no_w1_boss_takes_most_of_a_member_in_one_all_party_hit() -> void:
	var mons := _monsters()
	var over: Array = []
	var soft: Array = []
	for id in BOSSES:
		var row: Dictionary = mons.get(id, {})
		assert_false(row.is_empty(), "CONTROL: %s is in monsters.json" % id)
		var hit := _strongest_all_party_hit(row)
		assert_gt(float(hit[1]), 0.0, "CONTROL: %s has an all-party damage ability" % id)
		var mean := _party_mean_hp(int(row.get("level", 1)))
		var share: float = float(hit[1]) / maxf(1.0, mean)
		gut.p("[BOSS] %s L%d: %s raw %d vs mean member HP %d = %.2f" % [id, int(row.get("level", 1)), hit[0], int(hit[1]), int(mean), share])
		if share > MAX_SHARE:
			over.append("%s: %s is %.2f of a member's HP" % [id, hit[0], share])
		if share < MIN_SHARE:
			soft.append("%s: %s is only %.2f of a member's HP" % [id, hit[0], share])
	assert_eq(over, [], "a boss's strongest all-party hit must leave the party standing for a fight, not a wipe in two rounds")
	assert_eq(soft, [], "CONTROL against tuning a boss to nothing: its biggest hit still takes half a member")


func test_each_boss_signature_is_still_its_hardest_all_party_hit() -> void:
	var mons := _monsters()
	for id in ["ice_dragon", "shadow_dragon"]:
		var row: Dictionary = mons.get(id, {})
		var sig := str(row.get("fx_signature", ""))
		assert_ne(sig, "", "CONTROL: %s has a signature" % id)
		assert_eq(str(_strongest_all_party_hit(row)[0]), sig, "%s's signature (%s) is the scariest thing it does to the whole party" % [id, sig])
