extends GutTest

## Effect audit 2026-07-03: two authored effect strings ran through the
## dispatch and applied a status name no downstream code read — 4
## abilities lied about their mechanics. `freeze` (absolute_zero,
## blizzard_breath, ice_prison) applied "freeze" as a status label that
## nothing checked — the "frozen solid" description delivered pure
## damage. `summon_clone` (clone_self) hit the push_warning default
## and forked nothing. Freeze now aliases to `stun` at both offensive
## dispatch sites (the CC arm already implements skip-turn);
## summon_clone reuses the existing monster_summoned signal.


func test_freeze_alias_present_in_both_dispatch_sites() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# Both physical and magic dispatch went through replace_all: 2 sites.
	var count = src.count("if status_to_add == \"freeze\":")
	assert_eq(count, 2,
		"freeze alias must live at BOTH physical and magic dispatch sites (found %d)" % count)


func test_freeze_alias_maps_to_stun() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# The alias body is the only reason freeze becomes stun — no other engine
	# code reads has_status("freeze"), so this pin protects the whole loop.
	var idx: int = src.find("if status_to_add == \"freeze\":")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 80)
	assert_true(window.contains("status_to_add = \"stun\""),
		"the alias must map to stun (CC arm already skip-turns stunned combatants)")


func test_freeze_all_three_authored_abilities_are_magic_type() -> void:
	# Sanity: only magic-type freezers land in the magic dispatch site.
	# If a future author writes a physical freeze ability, this passes
	# too (physical site has the same alias), but the current roster is
	# all magic — pinning that so a future re-tag surfaces here.
	var a = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	for aid in ["absolute_zero", "blizzard_breath", "ice_prison"]:
		assert_true(a.has(aid), "authored ability %s missing" % aid)
		assert_eq(str(a[aid].get("effect", "")), "freeze")
		assert_eq(str(a[aid].get("type", "")), "magic")


func test_summon_clone_wired_in_dispatch() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(src.contains("\"summon_clone\":"),
		"summon_clone must be a real match branch")
	assert_true(src.contains("monster_summoned.emit(clone_type"),
		"summon_clone must reuse the existing summon signal for sprite/party plumbing")
	# Default-arm's unimplemented comment should no longer list summon_clone
	var default_idx: int = src.find("copy_last_ability, random_stat_change")
	if default_idx > -1:
		var window: String = src.substr(default_idx - 60, 200)
		assert_false(window.contains("summon_clone"),
			"summon_clone removed from the 'unimplemented' comment — it's implemented now")


func test_no_ability_effect_falls_to_default_silently() -> void:
	# Ratchet: only the acknowledged bespoke set is allowed to hit the
	# push_warning default. If a new effect appears in abilities.json
	# without a handler, this test surfaces it.
	var acknowledged := {
		"dispel": true,
		"copy_last_ability": true,
		"random_stat_change": true,
		"adapt_resistance": true,
	}
	# Effects that route directly to add_status and land as canonical
	# statuses BattleManager already reads (positive/negative status
	# lists at ~5255/5170 + the CC arm). If a name here goes silent,
	# it's a data drift the alias belt-and-suspenders should catch.
	var known_offensive_status := {
		"freeze": true, "poison": true, "burn": true, "burning": true,
		"blind": true, "confuse": true, "fear": true, "silence": true,
		"curse": true, "sleep": true, "stun": true, "charm": true,
		"barrier": true, "invisible": true, "magic_block": true,
		"evasion": true, "reflect": true, "erase": true, "pacify": true,
		"physical_reflect": true, "prismatic_reflect": true, "static": true,
		"doom": true,
	}
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var a = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var unhandled: Array = []
	for aid in a:
		var eff: String = str(a[aid].get("effect", ""))
		if eff == "" or eff == "none":
			continue
		if src.contains("\"%s\":" % eff):
			continue
		if known_offensive_status.has(eff):
			continue
		if not acknowledged.has(eff):
			unhandled.append("%s → %s" % [aid, eff])
	assert_eq(unhandled.size(), 0,
		"abilities author effects that hit no dispatch branch (silent fizzle class): %s" % str(unhandled))
