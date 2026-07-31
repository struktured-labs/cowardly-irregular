extends GutTest

## `power` is a legacy ability key NOTHING authors — 5 live read sites degraded (2026-07-30).
##
## `abilities.json` scales damage with `damage_multiplier` (160 of 288 abilities,
## median 1.5, max 5.0). It has never authored `power` — 0 of 288. Five sites read
## `power` anyway, each with a default, so each silently collapsed to a constant:
##
##   estimate_ability_damage   power(10) -> every "~N dmg" preview assumed 1.0x
##   _ai_caster spell score    power(10) -> every spell scored the same
##   _ai_tank sort             power(0)  -> "strongest physical" = whichever was first
##   _ai_assassin sort         power(0)  -> "strongest offensive" = whichever was first
##   generic_counter           power(0)  -> "strongest" counter = whichever was first
##
## The player-visible half is the preview: the command menu renders
## `~%d dmg` plus a `[KILL]` tag from that estimate, so a 3.5x ability advertised
## ~29% of its real damage and its [KILL] tag never appeared — the game told you an
## action would not finish a target when it would.
##
## `HeadlessBattleResolver:657` already carried the correct fallback AND a comment
## describing this exact fix; it was applied in one place and never propagated.
##
## Fixed by reading damage_multiplier with `power` kept as the legacy fallback, so
## any dict that genuinely authors power is unaffected.

const BM_SRC := "res://src/battle/BattleManager.gd"


func _bm() -> Node:
	var bm: Node = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	return bm


func _pc(atk: int, mag: int) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "PC"
	c.is_alive = true
	c.attack = atk
	c.magic = mag
	return c


func _target(hp: int, df: int) -> Combatant:
	var t: Combatant = autofree(Combatant.new())
	t.combatant_name = "Target"
	t.is_alive = true
	t.max_hp = hp
	t.current_hp = hp
	t.defense = df
	t.magic_defense = df
	return t


## ── the premise: the key really is unauthored ────────────────────────

func test_no_ability_authors_power() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var ab: Dictionary = raw.get("abilities", raw)
	var authors: Array[String] = []
	for id in ab:
		if (ab[id] as Dictionary).has("power"):
			authors.append(str(id))
	assert_eq(authors, [] as Array[String],
		"if abilities start authoring `power`, the fallback order below needs revisiting: %s" % str(authors))


func test_abilities_do_author_damage_multiplier() -> void:
	# POSITIVE CONTROL for the test above. A parse that silently returned {} would
	# make `no ability authors power` pass vacuously; this fails in that world.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var ab: Dictionary = raw.get("abilities", raw)
	var n: int = 0
	for id in ab:
		if (ab[id] as Dictionary).has("damage_multiplier"):
			n += 1
	assert_gt(n, 100,
		"the corpus must still scale damage with damage_multiplier — found %d of %d" % [n, ab.size()])


## ── the player-visible half ──────────────────────────────────────────

func test_preview_tracks_damage_multiplier() -> void:
	# The discriminating assertion. Pre-fix BOTH estimates were identical because
	# both read power's default; a stronger ability must now preview stronger.
	var bm: Node = _bm()
	var pc: Combatant = _pc(200, 200)
	var weak: int = bm.estimate_ability_damage(pc, _target(9999, 100),
		{"type": "magic", "damage_multiplier": 1.0})
	var strong: int = bm.estimate_ability_damage(pc, _target(9999, 100),
		{"type": "magic", "damage_multiplier": 5.0})
	assert_gt(strong, weak * 2,
		"a 5.0x ability must preview far above a 1.0x one — equal values mean the estimate is back on the constant `power` default (weak=%d strong=%d)" % [weak, strong])


func test_preview_matches_what_execution_actually_deals() -> void:
	# The point of a preview. Execution is `int(base * damage_multiplier)` then
	# take_damage's amount^2/(amount+def); the estimate must reproduce that, not a
	# different multiplier. Compared with a tolerance because the estimate
	# deliberately omits crit and variance.
	var bm: Node = _bm()
	var pc: Combatant = _pc(200, 200)
	var mult: float = 3.5
	var predicted: int = bm.estimate_ability_damage(pc, _target(99999, 100),
		{"type": "magic", "damage_multiplier": mult})
	var victim: Combatant = _target(99999, 100)
	var raw: int = int(pc.magic * mult)
	var actual: int = victim.take_damage(raw, true)
	assert_almost_eq(float(predicted), float(actual), float(actual) * 0.1,
		"the ~N dmg preview must land within 10%% of the damage execution deals (predicted %d, actual %d)" % [predicted, actual])


func test_a_lethal_ability_is_previewed_as_lethal() -> void:
	# The [KILL] tag is `est_dmg >= current_hp`. Pre-fix a high-multiplier ability
	# under-previewed, so the tag was withheld on an action that would in fact
	# kill — the failure a player actually acts on.
	var bm: Node = _bm()
	var pc: Combatant = _pc(200, 200)
	var ability: Dictionary = {"type": "magic", "damage_multiplier": 5.0}
	var victim: Combatant = _target(99999, 50)
	var real_kill: int = victim.take_damage(int(pc.magic * 5.0), true)
	var probe: Combatant = _target(real_kill, 50)
	var est: int = bm.estimate_ability_damage(pc, probe, ability)
	assert_gte(est, probe.current_hp,
		"an ability that deals %d to a %d HP target must preview as lethal, or [KILL] is withheld from a killing blow (est %d)" % [real_kill, probe.current_hp, est])


## ── the AI half ──────────────────────────────────────────────────────

func test_ability_power_helper_ranks_by_multiplier() -> void:
	var bm: Node = _bm()
	assert_gt(bm._ability_power({"damage_multiplier": 5.0}), bm._ability_power({"damage_multiplier": 1.0}),
		"the shared ranking helper must order by damage_multiplier")


func test_ability_power_still_honours_an_explicit_power() -> void:
	# The legacy key stays authoritative where something genuinely sets it, so the
	# fix cannot regress a caller that does.
	var bm: Node = _bm()
	assert_eq(bm._ability_power({"power": 42.0, "damage_multiplier": 1.0}), 42.0,
		"an explicitly authored `power` must still win over the fallback")


func test_strongest_sort_actually_reorders() -> void:
	# Pre-fix the comparator was constant, so sort_custom was a no-op and the
	# "strongest" ability was position 0. Weakest-first input makes that visible.
	var bm: Node = _bm()
	var abilities: Array = [
		{"id": "weak", "damage_multiplier": 0.5},
		{"id": "mid", "damage_multiplier": 2.0},
		{"id": "ultimate", "damage_multiplier": 5.0},
	]
	abilities.sort_custom(func(a, b): return bm._ability_power(a) > bm._ability_power(b))
	assert_eq(str(abilities[0]["id"]), "ultimate",
		"sorting by the real weight must put the ultimate first — a constant key leaves 'weak' in place")


## ── the sites, so a future edit cannot quietly revert one ────────────

func test_no_live_site_reads_bare_power_as_a_damage_weight() -> void:
	var src := FileAccess.get_file_as_string(BM_SRC)
	assert_ne(src, "", "the file must be readable or this assertion is vacuous")
	assert_eq(src.count("a.get(\"power\", 0)"), 0,
		"the constant-key comparator must not come back — use _ability_power()")
	assert_gte(src.count("_ability_power("), 5,
		"all four ranking sites plus the helper must go through _ability_power")
