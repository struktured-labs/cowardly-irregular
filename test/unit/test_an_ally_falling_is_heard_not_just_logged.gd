extends GutTest

## Tick 176 closed this moment's LOG parity — _on_party_hp_changed emits "X has fallen!" to match
## _on_enemy_died's "X has been defeated!". The AUDIO parity stayed open for six months: an enemy
## death plays enemy_death on the dedicated _death_player with DEATH_THUD under it, and a party
## member dropping played nothing at all. Same moment, same handler, half the feedback.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const CUE := "party_ko"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


## The lines INSIDE the block opened by `needle`, bounded by INDENTATION.
## substr(gate) takes the gate to end-of-function, which equals the branch only while nothing
## follows it — true here by layout, kept true by nothing. A sibling branch added after this one
## would silently join the window, and a cue moved into it would still satisfy the arm.
func _block_under(body: String, needle: String) -> String:
	var lines: PackedStringArray = body.split("\n")
	var gate_i: int = -1
	var gate_indent: int = 0
	for i in lines.size():
		if lines[i].contains(needle):
			gate_i = i
			gate_indent = lines[i].length() - lines[i].lstrip("\t").length()
			break
	if gate_i < 0:
		return ""
	var out: PackedStringArray = PackedStringArray()
	for i in range(gate_i + 1, lines.size()):
		var l: String = lines[i]
		if l.strip_edges() == "":
			continue
		if l.length() - l.lstrip("\t").length() <= gate_indent:
			break
		out.append(l)
	return "\n".join(out)


func before_each() -> void:
	var sm: Node = _sm()
	if sm:
		sm._sfx_cooldowns.clear()


func test_the_cue_is_authored_and_resolves() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(CUE), "%s is not in the manifest — the wire below is silent" % CUE)
	var f: String = str(sm._sfx_manifest.get(CUE, {}).get("file", ""))
	var path: String = f if f.begins_with("res://") else "res://" + f
	assert_true(ResourceLoader.exists(path), "%s names %s and it is not on disk" % [CUE, f])


func test_an_ally_falling_reaches_the_death_voice() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._death_player.stream = null
	sm.play_death(CUE)
	assert_not_null(sm._death_player.stream, "the ally-KO cue did not play at all")
	assert_true(str(sm._death_player.stream.resource_path).contains(CUE),
		"the death voice is holding %s, not the ally cue" % str(sm._death_player.stream.resource_path).get_file())


func test_it_does_not_evict_the_enemy_death_cry() -> void:
	# Both route through play_death, and a party member can fall in the same frame an enemy dies.
	# They SHARE _death_player by design — this pins that the sharing is the only collision, i.e.
	# the ally cue does not land on _battle_player and cut the hit that killed them.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_battle("attack_hit")
	var impact = sm._battle_player.stream
	assert_not_null(impact, "CONTROL: a battle cue must be sounding for this to mean anything")
	sm._sfx_cooldowns.clear()
	sm.play_death(CUE)
	assert_eq(sm._battle_player.stream, impact,
		"the ally-KO cue replaced the battle voice — it must ride its own death voice")


func test_the_moment_that_logs_the_fall_also_sounds_it() -> void:
	# Source-bound: the cue must sit in the SAME branch as the "has fallen" line, not merely
	# somewhere in the file. A cue in a neighbouring branch is a different moment.
	var code: String = GdSource.code_of(BATTLE_SCENE)
	assert_ne(code, "", "CONTROL: BattleScene code must survive the comment strip")
	var start: int = code.find("func _on_party_hp_changed(")
	assert_gt(start, -1, "CONTROL: _on_party_hp_changed is gone — this arm no longer describes the caller")
	var nxt: int = code.find("\nfunc ", start + 1)
	var body: String = code.substr(start, nxt - start) if nxt > start else code.substr(start)
	assert_gt(body.find("new_value <= 0 and old_value > 0"), -1,
		"CONTROL: the KO gate is gone — the cue may now fire on every HP tick")
	var branch: String = _block_under(body, "new_value <= 0 and old_value > 0")
	assert_ne(branch, "", "CONTROL: the KO branch extracted empty — the bound is broken, not the code")
	assert_true(branch.contains("play_death(\"%s\")" % CUE),
		"the ally-KO cue left the branch that announces the fall — the log and the sound are one moment")
	assert_true(branch.contains("has fallen"),
		"CONTROL: the 'has fallen' line must still be in this branch, or the pairing above is vacuous")
	## No line in BattleScene can distinguish "bounded to the branch" from "runs to end of
	## function" while nothing follows the KO branch — so the bound is proved on synthetic
	## input instead, in the arm below, rather than asserted against a layout coincidence here.


func test_the_branch_bound_excludes_a_sibling_branch() -> void:
	## The instrument, on input that HAS a sibling — which BattleScene does not, so the arm above
	## cannot tell a correct bound from a lucky one. Both repairs of that arm stay legal; what is
	## pinned is that the window stops at the branch.
	var synthetic := "\tif a:\n\t\tinside_the_branch()\n\tif b:\n\t\tin_a_sibling()\n\tafter_everything()"
	var block: String = _block_under(synthetic, "if a:")
	assert_true(block.contains("inside_the_branch()"),
		"the bound dropped the branch's own body — it is too tight to defend anything")
	assert_false(block.contains("in_a_sibling()"),
		"the bound swallowed a SIBLING branch — a cue moved out of the KO branch into a later one would still satisfy the arm above")
	assert_false(block.contains("after_everything()"),
		"the bound ran past the branch to function-body level")
	assert_eq(_block_under(synthetic, "not_present_anywhere"), "",
		"a missing needle must yield an EMPTY window, or the arm above would assert against the whole function")
	## The mechanism must be the one IN USE, not merely present: the arms above both pass if the
	## branch arm silently reverts to substr, because no line in BattleScene tells the bounds apart
	## (@cowir-battle). Bounded to that function, so this assert's own text is not the corpus.
	var own: String = GdSource.code_of("res://test/unit/test_an_ally_falling_is_heard_not_just_logged.gd")
	assert_ne(own, "", "CONTROL: this file's own source must survive the comment strip")
	var s: int = own.find("func test_the_moment_that_logs_the_fall_also_sounds_it(")
	assert_gt(s, -1, "CONTROL: the branch-bound arm was renamed — this pin no longer describes it")
	var n: int = own.find("\nfunc ", s + 1)
	var arm: String = own.substr(s, n - s) if n > s else own.substr(s)
	assert_true(arm.contains("_block_under(body,"),
		"the branch arm stopped using the indentation bound — whatever replaced it is unproved by the synthetic case above")
	## `code.substr(` is the LEGITIMATE one — it cuts the function out of the file. The defect is
	## substr on the function BODY, which cuts the gate to end-of-function and calls it a branch.
	## A bare `.substr(` here reds on correct code; measured, not reasoned — it did.
	assert_false(arm.contains("body.substr("),
		"the branch arm went back to a positional window: body.substr(gate) runs to END OF FUNCTION and is the exact defect this file was repaired for")


func test_the_cue_is_pinned_against_a_silent_re_roll() -> void:
	# It descends by construction, which is the shape the centroid test can mistake for a whoop.
	var f := FileAccess.open("res://test/fixtures/sfx_whoop_baseline.json", FileAccess.READ)
	assert_not_null(f, "CONTROL: the whoop baseline must be readable")
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var cues: Dictionary = parsed.get("cues", parsed) if parsed is Dictionary else {}
	assert_true(cues.has(CUE), "%s is not pinned in the whoop baseline — a re-roll could ship unmeasured" % CUE)


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## A direct `sm._x` on a RENAMED member raises at runtime and ABORTS the arm. An abort after
	## that arm's last assert scores PASSING — measured 2026-09-16: renaming the dedicated voice
	## this file exists to defend gave EXIT=0, Failing 0, NO Risky line, and moved only the assert
	## count. `get()` returns null for an absent name instead of raising, so the rename fails loudly
	## here and names itself before any other arm gets the chance to go quiet.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## Methods are NOT properties: get() returns null for a method name, so the loop below cannot
	## see a renamed METHOD. has_method ANSWERS instead of raising, same reason.
	## ⚠️ BOTH LISTS ARE A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT a
	## live derivation. Add a new sm. reach to this file and it is NOT covered until you add it here.
	## A runtime derivation would self-maintain but would read this arm's own body as corpus
	## (cowir-sprites' tautology class), needing cowir-ai's bare-Object exclusion to stay honest.
	## Convert it the next time this file gains a reach; until then the list is correct by being fresh.
	## ⚠️ IF YOU REGENERATE THIS LIST, STRIP COMMENTS FIRST (test/unit/helpers/gd_source.gd). The
	## generator that produced it read RAW source, so a trailing `# was sm.old_name()` — precisely
	## what a rename commit writes — becomes a listed member that never existed, and the floor then
	## REDS ON CORRECT CODE. cowir-music demonstrated that false red in their own floors 2026-09-16.
	## This list is ghost-free only because no such comment existed when it was generated.
	for method_name in ["play_battle", "play_death"]:
		assert_true(sm.has_method(method_name),
			"SoundManager has no method %s — this file CALLS it, and whether that shows as Risky or as a silent pass is decided by arm ORDER, not by care" % method_name)
	## ⚠️ get() CANNOT DISTINGUISH ABSENT FROM LEGITIMATELY NULL (@cowir-sprites): it returns null
	## for both. Every member below is a player, a Dictionary or a String — none is ever null once
	## _ready has run — so the check is sound HERE. If you add a nullable member to this list
	## (_crossfade_tween and the other _*_tween members are EXAMPLES, not an exhaustive list — check
	## the declaration), switch to get_property_list(), which answers about existence rather than value.
	for member_name in ["_battle_player", "_death_player", "_sfx_cooldowns", "_sfx_manifest"]:
		## assert_true on an explicit `!= null`: assert_ne deep-compares, and three of these members
		## are Dictionaries, which it refuses with "Only Arrays and Dictionaries are supported".
		assert_true(sm.get(member_name) != null,
			"SoundManager has no %s — this file reaches for it directly, and a rename would abort its arms SILENTLY" % member_name)
