extends GutTest

## Lens combat consumers (msg 3177/3179) — cowir-battle's half of the Lens system.
##
## cowir-main owns the data model, persistence, craft/equip and the read
## surface (`LensSystem.get_lens_meta_effects`). This file pins the four
## BATTLE consumers plus the recipe-unlock hook.
##
## WHY THE META_EFFECTS LOOK THE WAY THEY DO — the axis fingerprint
## (msg 3178) measured what the 20 live masterites actually do, and it
## contradicted the design doc on three of four axes:
##
##   warden   support 10 · physical 11 · magic 4   "DEFENSIVE WALL"      doc +8% DEF  ✓
##   arbiter  support 10 · physical 15             "EXECUTIONER"          doc +8% ATK  ~
##   tempo    support 20 · physical  5             "SPEED MANIPULATOR"    doc +10% SPD ✗
##   curator  support 14 · magic    11             "RESOURCE DENIAL"      doc +10% MAG ✗
##
## Tempo has 20/25 support slots — it manipulates action economy and
## barely fights; SPD is the stat it SPENDS, not what it does. Curator's
## "magic" is mana_drain / audit / dispel / resource_cut — every one
## attacks MP or buffs, never HP. Both doc tilts read the ability TYPE
## and missed what the axis does to you. So tempo and curator ship with
## empty `stat_mods` and carry their identity entirely in meta_effects,
## which is what these consumers implement.

const BM_PATH: String = "res://src/battle/BattleManager.gd"
const COMBATANT_PATH: String = "res://src/battle/Combatant.gd"


## ── (1) Recipe unlock on masterite defeat ────────────────────────────

func test_defeat_hook_unlocks_recipe_on_victory_path() -> void:
	# struktured ruled Lenses POOLED, so this needs NO attacker — only
	# "a masterite of axis X died and the party won". That's why it sits
	# in end_battle's victory block beside the bestiary loop rather than
	# in any damage path.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func end_battle(victory: bool) -> void:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 6000)
	assert_string_contains(body, "LensSystem.unlock_recipe(axis)",
		"masterite defeat must unlock the axis recipe on the victory path")
	assert_string_contains(body, "has_meta(\"masterite_type\")",
		"axis comes from the masterite_type meta set at spawn (BattleEnemySpawner)")


func test_defeat_hook_requires_no_attacker() -> void:
	# The anti-regression that matters: an earlier plan routed this
	# through killing-blow attribution across 5 functions / 15 call
	# sites. struktured's pooled ruling removed the need entirely.
	# If someone reintroduces attribution here, the pooled design has
	# been misunderstood.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("LensSystem.unlock_recipe(axis)")
	assert_gt(idx, -1)
	var window: String = src.substr(maxi(0, idx - 600), 600)
	assert_false(window.find("attacker") > -1,
		"recipe unlock must not depend on an attacker — Lenses are pooled, any PC equips them")


## ── (2) Warden — lethal floor ────────────────────────────────────────

func test_warden_floor_exists_and_is_once_per_battle() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	assert_string_contains(src, "lens_lethal_floor",
		"Warden consumer must read the lens_lethal_floor meta effect")
	assert_string_contains(src, "var _lens_floor_used: bool = false",
		"the floor is once per battle and needs a flag to track it")
	assert_string_contains(src, "_lens_floor_used = true",
		"the flag must be set when the floor fires, or it repeats every lethal hit")


func test_warden_floor_resets_each_battle_not_persisted() -> void:
	# A floor that stayed spent across a reload would silently weaken
	# the Lens on every continue — the player would never know why.
	var bm: String = FileAccess.get_file_as_string(BM_PATH)
	assert_string_contains(bm, "_lens_floor_used = false",
		"BattleManager.start_battle must clear the floor for every combatant")
	var save_src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var to_dict_idx: int = save_src.find("func to_dict(")
	if to_dict_idx > -1:
		var next: int = save_src.find("\nfunc ", to_dict_idx + 1)
		var to_dict_body: String = save_src.substr(to_dict_idx, (next - to_dict_idx) if next > -1 else 3000)
		assert_false(to_dict_body.find("_lens_floor_used") > -1,
			"the floor must NOT be save-persisted — it is battle-scoped, not run-scoped")


func test_warden_floor_precedes_death_resistance() -> void:
	# The Lens floor is guaranteed; death_resistance is a chance roll.
	# Checking the guaranteed one first means a Warden holder never
	# burns their roll on a hit the Lens would have caught anyway.
	# Match the ACTUAL read, not the word: `find("death_resist")` hits
	# this consumer's own explanatory comment first and compares the
	# code against prose. Caught by this test failing while the code
	# was correct — the proxy was a string I wrote myself.
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var lens_idx: int = src.find("me.get(\"lens_lethal_floor\"")
	var resist_idx: int = src.find("_get_passive_meta_effect_sum(\"death_resist_chance\")")
	assert_gt(lens_idx, -1, "the Lens floor read must exist")
	assert_gt(resist_idx, -1, "the death_resistance roll must exist")
	assert_lt(lens_idx, resist_idx,
		"guaranteed Lens floor must be checked BEFORE the death_resistance chance roll")


## ── (3) Arbiter — execute bonus ──────────────────────────────────────

func test_arbiter_execute_helper_reads_both_meta_keys() -> void:
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func _apply_lens_execute_bonus(")
	assert_gt(idx, -1, "the Arbiter execute helper must exist")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1800)
	assert_string_contains(body, "lens_execute_threshold",
		"must read the threshold")
	assert_string_contains(body, "lens_execute_bonus",
		"must read the bonus")


func test_arbiter_threshold_reads_hp_before_the_hit() -> void:
	# "Finish the wounded", not "reward whatever this hit happened to
	# leave behind". Reading post-hit HP would make every killing blow
	# an execute, which is a different (and much stronger) mechanic.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func _apply_lens_execute_bonus(")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1800)
	assert_string_contains(body, "float(target.current_hp) / float(target.max_hp) > threshold",
		"threshold must test the target's CURRENT hp fraction, before this hit is applied")


func test_arbiter_bonus_applies_to_physical_and_magic() -> void:
	# The Lens describes the holder's approach, not their weapon — a
	# Mage holding Arbiter should finish the same way a Fighter does.
	# Three damage paths exist; all three must call it.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var call_count: int = src.count("_apply_lens_execute_bonus(")
	# 1 definition + 3 call sites
	assert_gte(call_count, 4,
		"execute bonus must be wired into all three damage paths (attack, physical ability, magic ability), got %d references" % call_count)


## ── (4) Tempo — AP echo ──────────────────────────────────────────────

func test_tempo_echo_rearms_each_round_and_does_not_bank() -> void:
	# Unspent charges must not accumulate: Tempo rewards acting, which
	# is the axis's own behaviour (20/25 support slots manipulating
	# action economy). Banking would make sitting still optimal.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	assert_string_contains(src, "func _rearm_lens_ap_echo() -> void:",
		"the re-arm helper must exist")
	var idx: int = src.find("func _rearm_lens_ap_echo() -> void:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1200)
	assert_string_contains(body, "_lens_ap_echo_charges = 0",
		"re-arm must RESET to zero first — accumulating across rounds would let a passive holder bank charges")


func test_tempo_echo_is_party_only() -> void:
	# Tempo must not fund the enemy side. Masterites carry the axis but
	# never a Lens; still, the consumer runs for whoever acts, so the
	# party gate is load-bearing.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("_lens_ap_echo_charges > 0")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 220)
	assert_string_contains(window, "combatant in player_party",
		"AP echo must only fire for party members")


func test_tempo_echo_is_a_refund_at_one_seam() -> void:
	# Deliberate design: every AP-spending path deducts independently
	# (basic attack, each Advance sub-action, three group-attack paths),
	# so intercepting "cost" means five sites and getting the group
	# arithmetic right. Granting 1 AP at the action boundary is
	# arithmetically identical with exactly one seam.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("_lens_ap_echo_charges -= 1")
	assert_gt(idx, -1, "the echo must be consumed somewhere")
	var window: String = src.substr(idx, 200)
	assert_string_contains(window, "gain_ap(1)",
		"the echo is implemented as a refund at the action boundary, not as a discount at each spend site")


## ── (5) Curator — MP tithe + debuff resist ───────────────────────────

func test_curator_tithe_fires_only_on_a_real_spend() -> void:
	# Free moves and 0-cost abilities must not farm the tithe.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("_apply_lens_mp_tithe(caster)")
	assert_gt(idx, -1, "the tithe must be called from the MP spend path")
	var window: String = src.substr(maxi(0, idx - 260), 260)
	assert_string_contains(window, "mp_cost > 0",
		"tithe must be gated on an actual MP cost")


func test_curator_tithe_is_party_level() -> void:
	# The holder need not be the spender — that's the point. It's a
	# party economy Lens, so it scans the party rather than crediting
	# the caster.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func _apply_lens_mp_tithe(")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1200)
	assert_string_contains(body, "for pc in player_party",
		"the tithe must scan the party for a holder, not assume the spender holds it")
	assert_string_contains(body, "restore_mp(tithe)",
		"must grant via restore_mp so the max_mp clamp applies")


func test_curator_debuff_resist_shortens_never_blocks() -> void:
	# Blocking outright would make a resisted debuff indistinguishable
	# from a bug — nothing in the log, nothing on screen. Shortening
	# keeps the debuff visible and still rewards the Lens.
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var idx: int = src.find("lens_debuff_resist")
	assert_gt(idx, -1, "add_debuff must consume the resist meta effect")
	var window: String = src.substr(maxi(0, idx - 700), 1100)
	assert_string_contains(window, "maxi(1,",
		"duration must floor at 1 — the debuff still lands and still reads, it just expires sooner")


## ── (6) The fingerprint pin: tempo/curator carry NO stat tilt ────────

func test_tempo_and_curator_have_empty_stat_mods() -> void:
	# The axis fingerprint's headline finding. If someone "tidies" a
	# tilt back in because the design doc says +10% SPD / +10% MAG,
	# this fails and points at the measurement instead.
	var f: FileAccess = FileAccess.open("res://data/lenses.json", FileAccess.READ)
	assert_not_null(f, "lenses.json must exist")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var lenses: Dictionary = parsed.get("lenses", parsed)
	for axis in ["tempo", "curator"]:
		assert_true(lenses.has(axis), "lenses.json must define '%s'" % axis)
		var sm: Variant = (lenses[axis] as Dictionary).get("stat_mods", {})
		assert_true(sm is Dictionary and (sm as Dictionary).is_empty(),
			"'%s' must ship with EMPTY stat_mods — its identity is meta_effects. The doc's tilt read the ability TYPE and missed what the axis does (msg 3178 fingerprint). Re-adding a tilt needs a new measurement, not a tidy-up." % axis)


## ── (7) Target-resolver parity (msg 3189, cowir-ai's find) ───────────

func test_resolve_target_delegates_rather_than_duplicating() -> void:
	# TARGET_TYPES advertises 10; this resolver implemented 5 and sent the
	# rest to lowest_hp_enemy with no signal. Latent (the grid path
	# pre-resolves to a Combatant), but the fix is delegation rather than
	# five more arms — two implementations of one contract is how they
	# drift apart.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var idx: int = src.find("func _resolve_target(")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
	assert_string_contains(body, "_get_target_by_type",
		"unhandled target types must delegate to the complete resolver, not silently become lowest_hp_enemy")
	assert_string_contains(body, "push_warning",
		"a genuinely unknown type must be loud — silent fallback is the defect being fixed")


func test_autobattle_resolver_still_covers_every_advertised_type() -> void:
	# The delegation is only correct while AutobattleSystem implements
	# everything TARGET_TYPES advertises. If the two drift, this fails
	# here rather than degrading a player's rule silently.
	var abs_src: String = FileAccess.get_file_as_string("res://src/autobattle/AutobattleSystem.gd")
	var t_start: int = abs_src.find("const TARGET_TYPES = {")
	assert_gt(t_start, -1)
	var t_end: int = abs_src.find("}", t_start)
	var advertised: Array = []
	for m in RegEx.create_from_string("\"([a-z_]+)\":").search_all(abs_src.substr(t_start, t_end - t_start)):
		advertised.append(m.get_string(1))
	assert_gt(advertised.size(), 0, "TARGET_TYPES must parse")
	var r_start: int = abs_src.find("func _get_target_by_type(")
	assert_gt(r_start, -1)
	var r_end: int = abs_src.find("\nfunc ", r_start + 1)
	var resolver: String = abs_src.substr(r_start, (r_end - r_start) if r_end > -1 else 3000)
	var missing: Array = []
	for t in advertised:
		if resolver.find("\"%s\":" % t) < 0:
			missing.append(t)
	assert_eq(missing.size(), 0,
		"AutobattleSystem._get_target_by_type must implement every advertised TARGET_TYPE — BattleManager._resolve_target delegates to it. Missing: %s" % str(missing))
