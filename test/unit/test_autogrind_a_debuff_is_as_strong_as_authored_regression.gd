extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"

## `_effect_to_stat` returned [stat, MODIFIER] with one hardcoded number per effect — every down
## 0.75, every up 1.5 — and the caller overwrote the authored value it had read one line earlier.
## abilities.json authors nine distinct magnitudes across these effects, so the grind converged all
## of them on two numbers: shell_guard's authored 2.5 ground at 1.5, web_shot's 0.5 at 0.75, and
## battle_hymn's 1.25 was buffed UP to 1.5. Found by @cowir-battle while closing the live half.
##
## 🔑 THE SHAPE IS A DATA COPY UNDER A WORKING READER — the file DID read `stat_modifier`, one line
## before throwing it away. An audit asking "does the grind read this key" scores it green, which is
## why this arm asserts the MAGNITUDE THAT LANDS rather than the presence of a lookup.
##
## ⚠️ THE TWO PINNED ABILITIES STRADDLE THE OLD CONSTANTS ON PURPOSE. shell_guard was 40% too weak
## and bark 7% too strong; a "fix" that swaps one constant for another moves one of them and cannot
## move both. The corpus arm below is the general case, these two are the ones a player feels.

const _SUPPORT_TYPES := ["support", "song", "status"]

var _res
var _abilities: Dictionary


func before_each() -> void:
	_res = ResolverScript.new()
	_abilities = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))


func _combatant(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 99999, "max_mp": 9999,
		"attack": 40, "defense": 40, "magic": 40, "speed": 40})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


## The modifier that actually landed on the target under this ability's own name, or NAN.
func _landed_modifier(ability_id: String) -> float:
	var caster := _combatant("Caster")
	var target := _combatant("Target")
	_res._player_party = [caster]
	_res._enemy_party = [target]
	_res._resolve_ability(caster, ability_id, [target])
	for pool in [target.active_buffs, target.active_debuffs]:
		for entry in pool:
			if str(entry["effect"]) == ability_id:
				return float(entry["modifier"])
	return NAN


## The effect names live's support executor has a real `match` ARM for.
##
## ⛔ ANCHORED ON ARM INDENTATION, and the first draft was not. Slicing live's function at the next
## `\nfunc ` swallows the two `_SECONDARY_STAT_*_MAP` consts that sit between it and the next
## function, and those dicts spell `"magic_up":` at ONE tab — so the scan reported live as having
## arms it does not have, and the declaration arm below went red against a corpus, not a fact. A
## match arm is two tabs in; a const entry is one. That single tab is the whole discriminator.
func _live_support_arms() -> Dictionary:
	var live: String = GdSource.code_of(LIVE)
	var start: int = live.find("func _execute_support_ability(")
	assert_gt(start, 0, "CONTROL: live's support executor must be locatable")
	var at: int = live.find("\n\tmatch effect", start)
	assert_gt(at, start, "CONTROL: live's `match effect` must be locatable inside it")
	var body: String = live.substr(at, live.find("\nconst ", at) - at)
	var out: Dictionary = {}
	for m in RegEx.create_from_string('\n\t\t"([a-z_]+)"').search_all(body):
		out[m.get_string(1)] = true
	assert_gt(out.size(), 30, "CONTROL: live's effect match must yield a real arm set, or every verdict below is vacuous")
	return out


## Match-arm labels inside one of live's appliers, same two-tab discriminator as _live_support_arms.
## Returns [] when the function is absent, and the caller's CONTROL catches that — a silently empty
## applier set would make every effect look grind-only and turn this declaration into noise.
func _live_applier_arms(fn_signature: String) -> Array:
	var live: String = GdSource.code_of(LIVE)
	var at: int = live.find(fn_signature)
	assert_gt(at, 0, "CONTROL: live must still contain %s — if it was renamed this union is silently short" % fn_signature)
	var body: String = live.substr(at, live.find("\nfunc ", at + 1) - at)
	var out: Array = []
	for m in RegEx.create_from_string('\n\t\t"([a-z_]+)"').search_all(body):
		out.append(m.get_string(1))
	assert_gt(out.size(), 2, "CONTROL: %s must yield real arms, or the union below is vacuous" % fn_signature)
	return out


## Support-family abilities that reach `_effect_to_stat` — no explicit `stat`, mapped `effect`.
func _reachable() -> Array:
	var mapped_effects := ["attack_up", "defense_up", "magic_up", "speed_up", "magic_defense_up",
		"attack_down", "defense_down", "magic_down", "speed_down", "magic_defense_down", "volatility_down"]
	var out: Array = []
	for aid in _abilities:
		var d: Dictionary = _abilities[aid]
		if not _SUPPORT_TYPES.has(str(d.get("type", ""))):
			continue
		if str(d.get("stat", "")) != "":
			continue
		if not mapped_effects.has(str(d.get("effect", ""))):
			continue
		out.append(str(aid))
	return out


func test_a_shell_and_a_web_land_at_the_strength_they_are_authored() -> void:
	## The two extremes, in opposite directions from the constants that used to replace them.
	var shell: float = _landed_modifier("shell_guard")
	var web: float = _landed_modifier("web_shot")
	gut.p("    shell_guard %.2f (authored 2.5 · old constant 1.5) · web_shot %.2f (authored 0.5 · old constant 0.75)" % [shell, web])
	assert_almost_eq(shell, 2.5, 0.001,
		"shell_guard 'massively boosting defense' at an authored 2.5 did not land at 2.5 — _effect_to_stat overwrote the authored magnitude with a hardcoded 1.5")
	assert_almost_eq(web, 0.5, 0.001,
		"web_shot's authored 0.5 did not land at 0.5 — the hardcoded 0.75 made the grind's webs weaker than the game's")


func test_the_grind_over_buffed_as_well_as_under_buffed() -> void:
	## ⛔ DIRECTION ARM. Every ability in the reachable corpus authoring ABOVE 0.75 / BELOW 1.5 was
	## made STRONGER by the old table, not weaker. A one-sided fix ("the grind was too weak") passes
	## the arm above and still gets these wrong, so the two cases are pinned apart.
	var bark: float = _landed_modifier("bark")
	var hymn: float = _landed_modifier("battle_hymn")
	gut.p("    bark %.2f (authored 0.8 · old 0.75, too harsh) · battle_hymn %.2f (authored 1.25 · old 1.5, too generous)" % [bark, hymn])
	assert_almost_eq(bark, 0.8, 0.001,
		"bark's authored 0.8 did not land — the old 0.75 debuffed HARDER than the game does")
	assert_almost_eq(hymn, 1.25, 0.001,
		"battle_hymn's authored 1.25 did not land — the old 1.5 handed the grinding party a buff the real Bard never gives")


func test_every_authored_support_magnitude_survives_the_cast() -> void:
	## THE CORPUS ARM. One cast per reachable ability; the landed modifier must equal what
	## abilities.json authors. This is the census the two arms above are instances of.
	var reachable: Array = _reachable()
	assert_gt(reachable.size(), 25, "CONTROL: the reachable support corpus must be real, or every comparison below is vacuous")
	var wrong: Array = []
	for aid in reachable:
		var d: Dictionary = _abilities[aid]
		var authored: float = float(d.get("stat_modifier", d.get("modifier", 1.0)))
		var landed: float = _landed_modifier(aid)
		if is_nan(landed) or absf(landed - authored) > 0.001:
			wrong.append("%s(%s authored %.2f landed %.2f)" % [aid, str(d.get("effect", "")), authored, landed])
	gut.p("    reachable support abilities: %d · wrong magnitude: %d" % [reachable.size(), wrong.size()])
	assert_eq(wrong, [],
		"a support ability ground at a magnitude abilities.json does not author: %s" % str(wrong))


func test_the_effect_table_no_longer_carries_a_magnitude() -> void:
	## ⛔ THE SHAPE ARM. The defect was not a wrong number, it was a SECOND HOME for a number the
	## ability already owns. Putting one back is how this regresses, so the table's return type is
	## pinned: a String cannot carry a magnitude at all.
	var code: String = GdSource.code_of(GRIND)
	var at: int = code.find("func _effect_to_stat(")
	assert_gt(at, 0, "CONTROL: _effect_to_stat must still be locatable")
	var body: String = code.substr(at, code.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("-> String"),
		"_effect_to_stat no longer returns a bare stat name — a return type that can hold a pair is a place for a hardcoded magnitude to come back")
	assert_false(RegEx.create_from_string("[0-9]+\\.[0-9]+").search(body.get_slice("func _effect_to_stat(", 1)) != null,
		"a float literal is back inside _effect_to_stat — the magnitude belongs to the ability, not to the effect name")


func test_the_grind_maps_every_stat_effect_live_has_an_arm_for() -> void:
	## ⛔ THE COVERAGE ARM, and the one that would have caught magic_defense_down: this table was the
	## only stat map missing one of live's arms, so soul_wail's effect fell through to add_status and
	## became a junk status named after the debuff it failed to apply.
	var arms: Dictionary = _live_support_arms()
	## ⛔ THE TABLE'S OWN BODY, not the file. Scanning the whole resolver passed this arm with
	## magic_defense_down deleted from the map, because the string also lives in
	## _SECONDARY_STAT_DEBUFF_MAP — a guard written FOR that omission, unable to see it. Caught by
	## mutation, not by reading. Same tab-width lesson as _live_support_arms one function up.
	var grind: String = GdSource.code_of(GRIND)
	var fn_at: int = grind.find("func _effect_to_stat(")
	assert_gt(fn_at, 0, "CONTROL: _effect_to_stat must still be locatable")
	grind = grind.substr(fn_at, grind.find("\nfunc ", fn_at + 1) - fn_at)
	assert_true(grind.contains("match effect"), "CONTROL: the sliced body must be the table itself")
	var missing: Array = []
	for eff in ["attack_up", "defense_up", "magic_defense_up", "attack_down", "defense_down",
			"magic_defense_down", "speed_down", "volatility_down"]:
		if not arms.has(eff):
			continue
		if not grind.contains('"%s"' % eff):
			missing.append(eff)
	gut.p("    live stat-effect arms unmapped by the grind: %s" % str(missing))
	assert_eq(missing, [],
		"live applies a stat change for an effect the grind does not map — it falls through to add_status and becomes a junk status: %s" % str(missing))


func test_an_effect_only_the_grind_maps_stays_unauthored() -> void:
	## ⚠️ THE DECLARATION, in the other direction. magic_up / speed_up / magic_down are in the
	## grind's table and live has NO arm for any of them — live push_warnings and fizzles. Nothing
	## authors them on a support-typed ability, so the divergence is unreachable rather than wrong.
	## The day someone authors one, the grind buffs where the real game does nothing, and this reds.
	##
	## ⛔ WIDENED 2026-09-17 FROM THE SUPPORT MATCH TO ALL OF LIVE, after the sibling declaration with
	## this exact shape failed for real. That one said "the divergence opens when live starts
	## applying it" and watched _execute_support_ability; live grew the arm in _apply_ability_status
	## and the guard never fired — fourteen monster abilities diverged behind a green test.
	## A trigger in CODE has no bounded place, so naming ONE function is naming a guess.
	## ⚠️ LIVE-SIDE relevance, not hypothetical: @cowir-battle holds an open call on wiring
	## `magic_down`, and _apply_stat_down is where it would go. Under the old scan that would have
	## opened a gap here silently.
	## ⚠️ AND THE WIDENING HAD TO KEEP THE DISCRIMINATOR. My first attempt scanned all of LIVE for
	## `"<eff>":` and reported live as handling all three — it was matching _SECONDARY_STAT_BUFF_MAP,
	## a const of a DIFFERENT mechanism, exactly the one-tab-vs-two-tab distinction _live_support_arms
	## exists to make. Widening a corpus without carrying its discriminator manufactures the finding
	## it was widened to catch. So: the union of live's APPLIER functions, each parsed as arms.
	var handled: Dictionary = _live_support_arms()
	for row in _live_applier_arms("func _apply_stat_down("):
		handled[row] = true
	var grind_only: Array = []
	for eff in ["magic_up", "speed_up", "magic_down"]:
		if not handled.has(eff):
			grind_only.append(eff)
	assert_eq(grind_only.size(), 3,
		"live has grown an arm for one of magic_up/speed_up/magic_down — the declaration below is stale and the effect is now a real parity target")
	var authored: Array = []
	for aid in _abilities:
		var d: Dictionary = _abilities[aid]
		if _SUPPORT_TYPES.has(str(d.get("type", ""))) and grind_only.has(str(d.get("effect", ""))):
			authored.append(str(aid))
	gut.p("    grind-only stat effects: %s · support abilities authoring one: %s" % [str(grind_only), str(authored)])
	assert_eq(authored, [],
		"a support ability now authors an effect only the GRIND applies — it buffs in the simulation and fizzles in the game: %s" % str(authored))
