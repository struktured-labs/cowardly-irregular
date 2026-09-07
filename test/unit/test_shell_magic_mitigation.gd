extends GutTest

## Shell — a real magic-mitigation buff. Nothing raised magic_defense (2026-07-30).
##
## `magic_defense` became a real stat (take_damage picks magic_defense for magical
## hits, defense for physical), but the buff family never followed:
##
##     magic_defense_down   soul_wail       -> "Soul Sap" debuff, wired
##     magic_defense_up     NOTHING         -> no ability, no handler
##
## So an enemy could sap your magic defense and no ability in the game restored
## it, and Protect — the obvious candidate — buffs `defense`, which magical hits
## never read. Magic damage had no mitigation ability at all.
##
## Added `shell` (Cleric, level 7, white magic, mirror of Protect) plus the
## `magic_defense_up` handler that makes it real. These tests assert the
## MITIGATION, not the buff's existence: a buff nothing reads is the defect.

const ABILITIES := "res://data/abilities.json"


func _bm() -> Node:
	var bm: Node = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	return bm


func _pc(mdef: int, df: int) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "Ally"
	c.is_alive = true
	c.max_hp = 100000
	c.current_hp = 100000
	c.defense = df
	c.magic_defense = mdef
	return c


func _shell() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	return (raw.get("abilities", raw) as Dictionary).get("shell", {})


## ── the ability exists and says what it does ─────────────────────────

func test_shell_is_authored() -> void:
	var s: Dictionary = _shell()
	assert_false(s.is_empty(), "shell must exist in abilities.json")
	assert_eq(str(s.get("effect", "")), "magic_defense_up",
		"shell must author the magic_defense_up effect, or the handler below is unreachable")
	assert_gt(float(s.get("stat_modifier", 0.0)), 1.0, "a defensive buff must raise the stat")


func test_shell_description_matches_its_numbers() -> void:
	# Authored prose that quotes a stat goes stale silently. Pin the two figures
	# the description states against the fields that drive them.
	var s: Dictionary = _shell()
	var desc: String = str(s.get("description", ""))
	var pct: int = int(round((float(s.get("stat_modifier", 1.0)) - 1.0) * 100.0))
	assert_true(desc.contains("%d%%" % pct),
		"description must quote the real modifier (%d%%): '%s'" % [pct, desc])
	assert_true(desc.contains(str(int(s.get("duration", 0)))),
		"description must quote the real duration (%d): '%s'" % [int(s.get("duration", 0)), desc])


## ── the handler is REACHED, not just present ─────────────────────────

func test_casting_shell_lands_a_magic_defense_buff() -> void:
	# Pre-fix magic_defense_up hit the `_:` push_warning default and fizzled: MP
	# and AP spent, animation played, nothing applied.
	var bm: Node = _bm()
	var ally: Combatant = _pc(100, 100)
	bm._execute_support_ability(_pc(100, 100), _shell(), [ally])
	var found: bool = false
	for b in ally.active_buffs:
		if str(b["stat"]) == "magic_defense":
			found = true
	assert_true(found,
		"casting shell must leave a buff on the magic_defense stat — an unhandled effect silently applies nothing")


## ── the point: it actually mitigates ─────────────────────────────────

func test_shell_reduces_magical_damage_taken() -> void:
	# The whole deliverable. A buff no damage path reads is the defect being fixed,
	# so this drives real take_damage rather than inspecting active_buffs.
	var bm: Node = _bm()
	var bare: Combatant = _pc(100, 100)
	var shelled: Combatant = _pc(100, 100)
	bm._execute_support_ability(_pc(100, 100), _shell(), [shelled])
	var without: int = bare.take_damage(500, true)
	var with_shell: int = shelled.take_damage(500, true)
	assert_lt(with_shell, without,
		"Shell must reduce magical damage (bare %d, shelled %d) — equal values mean the buff exists and nothing reads it" % [without, with_shell])


func test_shell_does_not_reduce_physical_damage() -> void:
	# Shell is the magic mirror of Protect, not a second Protect. If this passes
	# only because the buff leaks onto `defense`, the two abilities are redundant.
	var bm: Node = _bm()
	var bare: Combatant = _pc(100, 100)
	var shelled: Combatant = _pc(100, 100)
	bm._execute_support_ability(_pc(100, 100), _shell(), [shelled])
	assert_eq(shelled.take_damage(500, false), bare.take_damage(500, false),
		"Shell must not touch physical damage — that is Protect's job")


func test_protect_does_not_reduce_magical_damage() -> void:
	# The asymmetry that made Shell necessary. If Protect ever starts mitigating
	# magic, Shell is redundant and this whole addition should be revisited.
	var bm: Node = _bm()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	var protect: Dictionary = (raw.get("abilities", raw) as Dictionary).get("protect", {})
	assert_false(protect.is_empty(), "protect must exist or this control is vacuous")
	var bare: Combatant = _pc(100, 100)
	var guarded: Combatant = _pc(100, 100)
	bm._execute_support_ability(_pc(100, 100), protect, [guarded])
	assert_eq(guarded.take_damage(500, true), bare.take_damage(500, true),
		"Protect buffs `defense`, which magical hits never read — this gap is why Shell exists")


func test_shell_expires() -> void:
	# A permanent buff would be a different bug. Duration is authored; tick it out.
	var bm: Node = _bm()
	var ally: Combatant = _pc(100, 100)
	bm._execute_support_ability(_pc(100, 100), _shell(), [ally])
	var mitigated: int = ally.take_damage(500, true)
	for i in range(int(_shell().get("duration", 3)) + 1):
		ally.update_buff_durations()
	assert_gt(ally.take_damage(500, true), mitigated,
		"Shell must wear off after its authored duration")


## ── reachable by a player ────────────────────────────────────────────

func test_cleric_learns_shell() -> void:
	# A correct ability nobody can cast is still a no-op.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var jobs: Dictionary = raw.get("jobs", raw)
	var at_level: Dictionary = (jobs["cleric"] as Dictionary).get("abilities_at_level", {})
	var learns: bool = false
	for lv in at_level:
		if "shell" in (at_level[lv] as Array):
			learns = true
	assert_true(learns, "some Cleric level must grant shell, or no party member can ever cast it")


func test_shell_is_on_the_white_magic_shelf() -> void:
	var shop = load("res://src/exploration/VillageShop.gd")
	assert_true("shell" in shop.WHITE_MAGIC_INVENTORY,
		"shell should be buyable alongside protect, its physical sibling")


func test_shelf_ids_still_resolve() -> void:
	# Guards the edit above: a shelf id with no ability behind it is a dead entry.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	var ab: Dictionary = raw.get("abilities", raw)
	var shop = load("res://src/exploration/VillageShop.gd")
	var missing: Array[String] = []
	for id in shop.WHITE_MAGIC_INVENTORY:
		if not ab.has(str(id)):
			missing.append(str(id))
	assert_eq(missing, [] as Array[String], "every white-magic shelf id must resolve: %s" % str(missing))
