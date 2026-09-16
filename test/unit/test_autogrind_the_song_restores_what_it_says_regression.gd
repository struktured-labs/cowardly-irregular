extends GutTest

## `mp_restore_percent` and `ap_gain` are read by live in _execute_support_ability
## (BattleManager:6123-6124). The grind's arm for the same effect HARDCODED both:
##
##     target.restore_mp(int(target.max_mp * 0.25))
##     target.gain_ap(1)
##
## `inspiring_melody` — the only ability authoring either — authors **0.05**. So a grinding Bard's
## song restored FIVE TIMES the MP the game grants. The grind was SOFTER than the game it simulates,
## which is the same defect as being harsher: an MP-sustain party evaluates as viable in a grind and
## is not, and autogrind exists to evaluate exactly that.
##
## Reachable by form 2: the Bard learns it at LEVEL 8 and the Bard is a starter job. No monster casts
## it, so forms 1/3/4 do not apply — checked before building, not after.
##
## ⚠️ THE `ap_gain` HALF WAS CORRECT BY COINCIDENCE, which is why it gets its own arm. The literal 1
## happened to equal live's default, so every test of the AP path passed and would have kept passing
## if an ability ever authored 2. CLAUDE.md's ratchet rule, one layer in: a value that is right for a
## reason nobody chose is not defended by the test that passes on it.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res
## Injected into JobSystem's own table so the probe takes the SAME route a real cast does —
## _resolve_ability -> get_ability -> the support arm. A helper called directly would be a unit test
## of the helper wearing the feature's name, which cost two other lanes a green arm today.
const _PROBE_ID := "_autogrind_probe_song"
var _injected: bool = false


func before_each() -> void:
	_res = ResolverScript.new()


func after_each() -> void:
	## JobSystem is an AUTOLOAD — this table outlives the test. Leaving the key behind would hand every
	## later file a phantom ability.
	if _injected:
		var js: Node = get_node_or_null("/root/JobSystem")
		if js:
			js.abilities.erase(_PROBE_ID)
		_injected = false


func _inject(extra: Dictionary) -> bool:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not ("abilities" in js):
		return false
	var ab: Dictionary = {"name": "Probe Song", "type": "support", "effect": "mp_restore_and_ap",
		"mp_cost": 0, "target_type": "single_ally"}
	ab.merge(extra, true)
	js.abilities[_PROBE_ID] = ab
	_injected = true
	return true


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


func _combatant(name: String, mp: int = 1000) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 500, "max_mp": mp,
		"attack": 30, "defense": 10, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	c.current_hp = c.max_hp
	return c


func test_the_song_restores_the_authored_share_not_a_hardcoded_quarter() -> void:
	var ab: Dictionary = _authored("inspiring_melody")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var pct: float = float(ab.get("mp_restore_percent", -1.0))
	assert_gt(pct, 0.0, "CONTROL: inspiring_melody must still author mp_restore_percent")
	assert_ne(pct, 0.25, "CONTROL: and it must still DIFFER from the old hardcode, or this arm proves nothing")

	var bard := _combatant("Bard")
	_res._player_party = [bard]
	## Drained far enough that a 25% grant and a 5% grant cannot both fit — otherwise the cap hides it.
	var ally := _combatant("Ally", 1000)
	ally.current_mp = 0
	_res._resolve_ability(bard, "inspiring_melody", [ally])
	var expected: int = int(ally.max_mp * pct)
	gut.p("    authored %.2f -> expected %d MP, grind restored %d" % [pct, expected, ally.current_mp])
	assert_eq(ally.current_mp, expected,
		"the song restores %d%% of max MP (%d) — the grind gave %d" % [int(pct * 100), expected, ally.current_mp])


func test_the_ap_half_follows_the_authored_value_too() -> void:
	## The old literal 1 equalled live's default, so this could only be caught by an ability that
	## authors something else. There is none, so the arm SYNTHESISES one and drives the helper the
	## same way the real cast does — a coincidence is not defended by the data that produced it.
	var bard := _combatant("Bard")
	_res._player_party = [bard]
	var ally := _combatant("Ally", 1000)
	ally.current_mp = 0
	if not _inject({"ap_gain": 3, "mp_restore_percent": 0.10}):
		pass_test("JobSystem autoload unavailable")
		return
	var ap0: int = ally.current_ap
	_res._resolve_ability(bard, _PROBE_ID, [ally])
	gut.p("    ap before=%d after=%d" % [ap0, ally.current_ap])
	assert_eq(ally.current_ap - ap0, 3,
		"an ability authoring ap_gain 3 must grant 3 — the arm hardcoded 1 and agreed with live only by luck")


func test_a_zero_percent_song_restores_nothing() -> void:
	## ⚠️ THIS ARM DOES NOT DEFEND LIVE'S `mp_pct > 0.0` / `mp_restored > 0` GUARDS, and said it did
	## until the mutation was run. Deleting both guards leaves restore_mp(0), already a no-op, and
	## this arm stays GREEN — measured, not assumed. The guards are mirrored from live because live
	## has them, not because anything here would catch their loss.
	## What it DOES defend is the authored value reaching the arm at all: hardcoding the old 0.25
	## reds this arm too, because a 0% author would then restore a quarter of max MP.
	var bard := _combatant("Bard")
	_res._player_party = [bard]
	var ally := _combatant("Ally", 1000)
	ally.current_mp = 0
	if not _inject({"ap_gain": 1, "mp_restore_percent": 0.0}):
		pass_test("JobSystem autoload unavailable")
		return
	_res._resolve_ability(bard, _PROBE_ID, [ally])
	assert_eq(ally.current_mp, 0, "a 0% restore must restore nothing")
	assert_eq(ally.current_ap, 1, "and the AP half still pays, so the arm is not passing on a dead cast")
