extends GutTest

## Real gameplay regression: VillageInn._rest_party() must REVIVE dead
## party members, not just heal their HP to max while leaving is_alive
## stuck at false.
##
## Bug shape:
##   • _rest_party's restore loop did:
##       member.current_hp = member.max_hp
##       member.current_mp = member.max_mp
##       member.current_ap = 0
##   • Combatant.is_alive is a separate bool flag that gets flipped to
##     false on death in take_damage(). Direct current_hp assignment
##     bypasses revive() and leaves is_alive=false.
##   • Net: a dead party member walks into the inn, leaves with full HP
##     showing on their portrait, but battle code still treats them as
##     dead — they sit out of turn order and the battle's alive-check
##     misses them.
##   • Reported via playtest: "fully healed my party at the inn but the
##     bard still ded".
##
## Fix: when a member is_alive=false, call revive(max_hp). For alive
## members, keep the cheaper direct assignment. Either way, current_hp
## ends at max_hp and is_alive ends at true.
##
## Tests:
##   • Source pin: _rest_party calls member.revive(member.max_hp) on
##     the dead-member branch
##   • Source pin: the legacy unconditional `member.current_hp =
##     member.max_hp` is gone from non-comment code (the comment can
##     still cite the bug shape for teaching)
##   • Behavioural: a Combatant with is_alive=false going through the
##     same logic _rest_party uses ends up is_alive=true AND
##     current_hp=max_hp

const VILLAGE_INN_PATH := "res://src/exploration/VillageInn.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_rest_party_revives_dead_members() -> void:
	var text := _read(VILLAGE_INN_PATH)
	var idx := text.find("func _rest_party")
	assert_gt(idx, -1, "_rest_party must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("not member.is_alive"),
		"_rest_party must branch on is_alive — dead members need revive(), not just an HP assign")
	assert_true(body.contains("member.revive(member.max_hp)"),
		"_rest_party must call member.revive(member.max_hp) on the dead-member branch")


func test_legacy_unconditional_hp_assign_is_gone() -> void:
	# Walk non-comment code only. The teaching doc-comment cites the
	# legacy expression for context; the live code must not still use it.
	var text := _read(VILLAGE_INN_PATH)
	var idx := text.find("func _rest_party")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	var lines := body.split("\n")
	var code_only: PackedStringArray = PackedStringArray()
	var stripped_lines: PackedStringArray = PackedStringArray()
	for line in lines:
		var ln: String = str(line)
		var trimmed := ln.strip_edges()
		if trimmed.begins_with("#"):
			continue
		stripped_lines.append(trimmed)
		code_only.append(ln)
	# The fix guards the assignment with an else: branch. So a non-guarded
	# `member.current_hp = member.max_hp` line at the top level of the
	# loop body (no preceding `else:`) would be the bug shape.
	for i in range(stripped_lines.size()):
		var trimmed = stripped_lines[i]
		if trimmed == "member.current_hp = member.max_hp":
			var prior_non_blank := ""
			for j in range(i - 1, -1, -1):
				if stripped_lines[j] != "":
					prior_non_blank = stripped_lines[j]
					break
			assert_eq(prior_non_blank, "else:",
				"member.current_hp = member.max_hp must be guarded by an else: (the alive branch) — never unconditional, else dead members stay dead")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_revive_then_full_hp_for_dead_member() -> void:
	# Mirror what _rest_party does to a dead party member. The actual
	# _rest_party path needs a live GameLoop scene (main_scene root, not
	# an autoload) which GUT can't stand up — so drive the per-member
	# logic directly and assert the post-state.
	var c := Combatant.new()
	c.combatant_name = "DeadBard"
	c.base_max_hp = 100
	c.base_max_mp = 30
	add_child_autofree(c)
	# Kill it via the public path so is_alive=false is reached the same
	# way it would in battle.
	c.take_damage(99999)
	assert_false(c.is_alive, "precondition: combatant should be dead after lethal damage")
	# Apply the same rest-loop logic the fix uses.
	if not c.is_alive:
		c.revive(c.max_hp)
	else:
		c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	c.current_ap = 0
	assert_true(c.is_alive, "post-rest: combatant must be is_alive=true")
	assert_eq(c.current_hp, c.max_hp,
		"post-rest: current_hp must equal max_hp (full HP restore)")


func test_alive_member_path_still_works() -> void:
	# Inverse case: an alive but injured combatant goes through the rest
	# loop and ends up at full HP/MP, is_alive untouched (already true).
	var c := Combatant.new()
	c.combatant_name = "InjuredFighter"
	c.base_max_hp = 100
	c.base_max_mp = 30
	add_child_autofree(c)
	c.take_damage(40)
	assert_true(c.is_alive, "precondition: combatant should still be alive after sub-lethal damage")
	var hp_before_rest := c.current_hp
	assert_lt(hp_before_rest, c.max_hp, "precondition: HP should be below max")
	if not c.is_alive:
		c.revive(c.max_hp)
	else:
		c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	c.current_ap = 0
	assert_true(c.is_alive, "post-rest: combatant must remain is_alive=true")
	assert_eq(c.current_hp, c.max_hp, "post-rest: alive member's HP must restore to max")
