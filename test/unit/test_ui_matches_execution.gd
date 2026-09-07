extends GutTest

## Does the interface tell the truth about the engine? (2026-08-06)
##
## Every player-visible defect found in combat this week was the UI stating something
## the engine did not do — not the simulation being wrong:
##
##   menu said "~133 dmg"        execution dealt 612      (`power`, unauthored, months old)
##   badge said "CAN"            status was cannot_act    (grey truncation fallback)
##   Shell promised mitigation   nothing raised magic_defense
##   "enemies cast abilities"    they only ever swung     (autogrind, two dead keys)
##
## Every guard we own asks whether a thing EXISTS or RESOLVES. None asks whether the
## number on screen is the number that lands. `estimate_ability_damage` and the real
## execution path have both existed for months and have never been compared to each
## other — that comparison is this file.
##
## This is the instrument for the "shipped, reachable, and wrong" category: defects that
## render every frame, pass every presence check, and are invisible to any orphan sweep.
##
## Test-only. No src/ change, no balance change. It measures what already ships.

const BM_SRC := "res://src/battle/BattleManager.gd"
const ABILITIES := "res://data/abilities.json"


func _bm() -> Node:
	var bm: Node = load(BM_SRC).new()
	add_child_autofree(bm)
	return bm


func _pc(atk: int, mag: int) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "PC"
	c.is_alive = true
	c.max_hp = 9999
	c.current_hp = 9999
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


func _abilities() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	return raw.get("abilities", raw)


## ── controls, so a zero below is a claim about the game and not this file ──

func test_the_corpus_and_the_estimator_both_work() -> void:
	var ab := _abilities()
	assert_gt(ab.size(), 200, "abilities.json must parse; got %d" % ab.size())
	var bm := _bm()
	var est: int = bm.estimate_ability_damage(_pc(200, 200), _target(9999, 100),
		{"type": "magic", "damage_multiplier": 1.0})
	assert_gt(est, 0,
		"NAMED-MEMBER control: a 1.0x magic ability must preview above zero, or every comparison below is vacuous")


## ── the core claim: the preview is the damage ──

func test_preview_matches_execution_across_the_shipped_multiplier_range() -> void:
	# The defect this exists for: for months the preview assumed 1.0x for EVERY ability,
	# so a 3.5x ability advertised 29% of its damage. Sweeping the real authored range
	# rather than one value — a single multiplier passes even when the preview ignores
	# the field entirely, since 1.0 is a fixed point.
	var bm := _bm()
	var offenders: Array[String] = []
	for mult in [0.5, 1.0, 1.5, 2.5, 3.5, 5.0]:
		var caster := _pc(200, 200)
		var ability := {"type": "magic", "damage_multiplier": mult}
		var previewed: int = bm.estimate_ability_damage(caster, _target(99999, 100), ability)
		# the real path: int(base * multiplier) then take_damage's amount^2/(amount+def)
		var actual: int = _target(99999, 100).take_damage(int(caster.magic * mult), true)
		if abs(previewed - actual) > maxi(1, int(actual * 0.1)):
			offenders.append("mult %.1f: previewed %d, executed %d" % [mult, previewed, actual])
	assert_eq(offenders, [] as Array[String],
		"the ~N dmg the menu shows must be within 10%% of what execution deals, at every authored multiplier: %s" % str(offenders))


func test_preview_tracks_the_physical_path_too() -> void:
	# Physical reads `attack` and mitigates on `defense`; magic reads `magic`/`magic_defense`.
	# A preview that used the wrong stat pair would agree on a symmetric dummy, so the
	# combatant here is deliberately LOPSIDED — atk 300 vs mag 50.
	var bm := _bm()
	var caster := _pc(300, 50)
	var ability := {"type": "physical", "damage_multiplier": 2.0}
	var previewed: int = bm.estimate_ability_damage(caster, _target(99999, 120), ability)
	var actual: int = _target(99999, 120).take_damage(int(caster.attack * 2.0), false)
	assert_almost_eq(float(previewed), float(actual), float(actual) * 0.1,
		"a physical ability must preview off attack/defense, not magic — a symmetric dummy would hide a swapped stat pair (previewed %d, executed %d)" % [previewed, actual])


## ── the [KILL] tag: advertised lethality must be real lethality ──

func test_a_killing_blow_is_advertised_as_lethal() -> void:
	# BattleCommandMenu renders "[KILL]" when est_dmg >= current_hp. Under-previewing
	# withheld it from blows that would in fact kill, and the player retargets on that.
	var bm := _bm()
	var caster := _pc(200, 200)
	var ability := {"type": "magic", "damage_multiplier": 5.0}
	var lethal_amount: int = _target(99999, 50).take_damage(int(caster.magic * 5.0), true)
	var victim := _target(lethal_amount, 50)
	assert_gte(bm.estimate_ability_damage(caster, victim, ability), victim.current_hp,
		"an ability that deals exactly lethal damage must preview as lethal, or [KILL] is withheld from a killing blow")


func test_a_nonlethal_blow_is_not_advertised_as_lethal() -> void:
	# The other direction, which matters more: a FALSE [KILL] makes the player commit a
	# turn to a finisher that doesn't finish. Over-previewing is the mirror defect and
	# nothing else in the suite would catch it.
	var bm := _bm()
	var caster := _pc(200, 200)
	var ability := {"type": "magic", "damage_multiplier": 1.0}
	var actual: int = _target(99999, 50).take_damage(int(caster.magic * 1.0), true)
	var tanky := _target(actual * 4, 50)
	assert_lt(bm.estimate_ability_damage(caster, tanky, ability), tanky.current_hp,
		"an ability dealing a quarter of a target's HP must NOT preview as lethal — a false [KILL] costs the player a turn")


## ── the whole shipped corpus, not a sample ──

func test_no_shipped_damaging_ability_previews_wildly_wrong() -> void:
	# The sweep the point-tests can't be: every authored damaging ability, through both
	# paths, against one dummy. Catches a field the estimator reads that execution does
	# not (or vice versa) for abilities nobody wrote a test for.
	var bm := _bm()
	var ab := _abilities()
	var offenders: Array[String] = []
	var checked: int = 0
	for id in ab:
		var a: Dictionary = ab[id]
		var t: String = str(a.get("type", ""))
		if not (t == "magic" or t == "physical"):
			continue
		if not a.has("damage_multiplier"):
			continue
		var mult := float(a["damage_multiplier"])
		if mult <= 0.0:
			continue
		checked += 1
		var caster := _pc(200, 200)
		var previewed: int = bm.estimate_ability_damage(caster, _target(99999, 100), a)
		var base: int = caster.magic if t == "magic" else caster.attack
		var actual: int = _target(99999, 100).take_damage(int(base * mult), t == "magic")
		if abs(previewed - actual) > maxi(2, int(actual * 0.15)):
			offenders.append("%s (%s %.1fx): previewed %d, executed %d" % [id, t, mult, previewed, actual])
	assert_gt(checked, 100,
		"CONTROL: the sweep must actually examine the corpus; only %d abilities qualified" % checked)
	assert_eq(offenders, [] as Array[String],
		"these shipped abilities advertise a number execution does not deliver: %s" % str(offenders))


## ── the other half of "what the UI says": statuses ──

func test_the_status_a_cast_lands_is_the_status_the_badge_names() -> void:
	# burn->burning was this defect: the ability authors "burn", the engine applies
	# "burning", and the icon table was keyed on the authored name — so the badge went
	# grey the day the DoT started working. Assert the APPLIED name is the one the
	# renderer can resolve, for every effect the config claims to cover.
	var scene_src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var start := scene_src.find("const STATUS_ICON_CONFIG")
	assert_gt(start, -1, "STATUS_ICON_CONFIG must exist or this assertion is vacuous")
	var cfg := scene_src.substr(start, scene_src.find("\n}", start) - start)
	var bm := _bm()
	var target := _target(500, 10)
	bm.player_party.append(_pc(50, 50))
	bm.enemy_party.append(target)
	bm._execute_magic_ability(_pc(50, 50), {
		"id": "flame_wall", "effect": "burn", "effect_chance": 1.0, "duration": 3,
		"damage_multiplier": 0.1, "type": "magic", "target_type": "single",
	}, [target])
	var landed: Array[String] = []
	for s in target.status_effects:
		landed.append(str(s))
	assert_gt(landed.size(), 0, "the cast must land a status or this assertion is vacuous")
	for s in landed:
		assert_true(cfg.contains('"%s"' % s),
			"the status a cast actually applies (%s) must have an icon entry, or it renders as a grey 3-letter truncation of its own name" % s)
