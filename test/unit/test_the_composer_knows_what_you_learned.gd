extends GutTest

## A level-20 Mage asked the Rule Composer for its strongest fire spell and got `fire`.
##
## `AutobattleSystem.get_deep_check_kit` returns TWO sets and the prompt rendered
## the narrower one:
##
##     kit       job.abilities + free_move       NO level-gated entries
##     full_kit  kit + every abilities_at_level  ALL levels, unfiltered
##
## `_format_rule_kit` renders `kit` under the line "Ability ids you may use, and
## NOTHING else", while `_deep_check_rule` validates against `full_kit`. So the
## validator would have accepted `fira`/`firaga`/`thundaga` all along and the
## model was told they do not exist. The composer was permanently stuck at the
## tutorial tier for every character in the game.
##
## ⚠️ THE ASYMMETRY WAS IN THE SAFE DIRECTION, which is why nothing ever redded:
## a prompt narrower than the validator produces no false drops. Verified before
## claiming otherwise — the shop sells tier-2 spells out of `abilities_at_level`,
## so a purchased spell is inside `full_kit` and `_drop_unusable_rules` never told
## a player their bought spell "cannot run".
##
## The offered set is now `full_kit ∩ knows_ability`, and both halves are
## load-bearing:
##
##     knows_ability   the only predicate that gates on job_level — and it is
##                     struktured's, so this is a borrowed resolution rather than
##                     a sixth re-derivation of "what can this character cast"
##     full_kit        the deep check's own vocabulary; offering anything outside
##                     it would make _drop_unusable_rules discard the rule
##
## MEASURED, live, on a mage at job_level 12:
##     knows fire ✅  fira ✅  firaga ✅ (unlocks at 11)  thundaga ❌ (unlocks at 13)

const RC := preload("res://src/llm/RuleComposer.gd")
const DP := preload("res://src/llm/DialoguePrompts.gd")

const STUB_GAMELOOP := """
extends Node
var party: Array = []
"""

var _stub: Node = null


func before_each() -> void:
	## Never shadow a real GameLoop: if one is in the tree these tests would be
	## measuring it instead, and the stub would be the two-writers class.
	assert_null(get_tree().root.get_node_or_null("GameLoop"),
		"CONTROL: no real GameLoop may be in the tree when this file runs")


func after_each() -> void:
	if _stub != null and is_instance_valid(_stub):
		get_tree().root.remove_child(_stub)
		_stub.free()
	_stub = null


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


## A mage partway up its unlock table. Named "Mage" so character_id resolves to
## the job id — _resolve_job_for_character falls through to the id itself, which
## is the same path get_deep_check_kit("mage") takes.
func _mage_at(level: int) -> Combatant:
	var c: Combatant = Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Mage"
	c.job = JobSystem.get_job("mage")
	c.job_level = level
	return c


func _party_of(member: Combatant) -> void:
	var script := GDScript.new()
	script.source_code = STUB_GAMELOOP
	script.reload()
	_stub = Node.new()
	_stub.set_script(script)
	_stub.name = "GameLoop"
	_stub.party = [member]
	get_tree().root.add_child(_stub)


func _kit_for(level: int) -> Dictionary:
	_party_of(_mage_at(level))
	var base: Dictionary = AutobattleSystem.get_deep_check_kit("mage")
	assert_true(bool(base.get("resolved", false)),
		"CONTROL: the kit must resolve, or this file measures nothing")
	return _rc()._widen_kit_to_what_this_character_knows(base, "mage")


func _ids(ctx: Dictionary) -> Array:
	return ctx.get("kit", []) as Array


# ── the defect ────────────────────────────────────────────────────────────────

func test_an_unlocked_spell_is_offered() -> void:
	## THE ARM. firaga unlocks at 11; a level-12 mage has had it for a level and
	## the composer had never heard of it.
	var ids: Array = _ids(_kit_for(12))
	assert_true(ids.has("firaga"), "a spell this character has unlocked must be offered: %s" % str(ids))
	assert_true(ids.has("fira"), "and so must the tier below it: %s" % str(ids))


func test_the_level_one_kit_is_still_there() -> void:
	## CORRECT-WORK: widening must add, never replace. `channel` is the free move
	## and is the member a kit walker loses first.
	var ids: Array = _ids(_kit_for(12))
	for base in ["fire", "blizzard", "thunder", "channel"]:
		assert_true(ids.has(base), "the level-1 kit must survive widening: %s missing from %s" % [base, str(ids)])


# ── it must not over-offer ────────────────────────────────────────────────────

func test_a_spell_not_yet_unlocked_is_withheld() -> void:
	## The failure mode of rendering full_kit instead: thundaga unlocks at 13, so
	## a level-12 mage would author a rule it cannot cast, and it fizzles in play.
	var ids: Array = _ids(_kit_for(12))
	assert_false(ids.has("thundaga"),
		"thundaga unlocks at 13 and this mage is 12 — offering it authors a rule that fizzles: %s" % str(ids))


func test_a_level_one_character_is_offered_exactly_its_kit() -> void:
	## The boundary at the bottom: at level 1 the widened set must equal the kit
	## that shipped, or this change moved the floor.
	var ctx: Dictionary = _kit_for(1)
	var ids: Array = _ids(ctx)
	for gated in ["fira", "firaga", "dark_bolt", "chain_lightning"]:
		assert_false(ids.has(gated), "a level-1 mage must not be offered %s: %s" % [gated, str(ids)])


func test_everything_offered_is_inside_the_validators_vocabulary() -> void:
	## THE INVARIANT that keeps this safe: the deep check validates ability ids
	## against full_kit, so anything offered outside it would be composed and then
	## dropped as unrunnable — telling the player a rule they can run cannot run.
	var ctx: Dictionary = _kit_for(12)
	var full: Array = ctx.get("full_kit", []) as Array
	var outside: Array[String] = []
	for aid in _ids(ctx):
		if not full.has(str(aid)):
			outside.append(str(aid))
	assert_eq(outside, ([] as Array[String]),
		("the prompt offers ids the deep check will reject: %s. Fix in RuleComposer."
		+ "_widen_kit_to_what_this_character_knows — only ids already in full_kit may be added, "
		+ "or _drop_unusable_rules discards the rule and tells the player it cannot run.")
			% ", ".join(outside))


# ── the cost must travel with the ability ─────────────────────────────────────

func test_every_added_spell_carries_its_real_mp_cost() -> void:
	## A missing cost renders as "0 MP", the model omits the guard, and the rule
	## fizzles for want of MP — the exact failure _supply_missing_mp_guards exists
	## to repair. The widening must not create work for that repair.
	var ctx: Dictionary = _kit_for(12)
	var costs: Dictionary = ctx.get("costs", {}) as Dictionary
	var zero_cost: Array[String] = []
	for aid in _ids(ctx):
		var real: int = int((JobSystem.get_ability(str(aid)) as Dictionary).get("mp_cost", 0))
		if real > 0 and int(costs.get(str(aid), 0)) != real:
			zero_cost.append("%s (real %d, offered %d)" % [str(aid), real, int(costs.get(str(aid), 0))])
	assert_eq(zero_cost, ([] as Array[String]),
		"these are offered at the wrong MP cost, so the model will not guard them: %s" % ", ".join(zero_cost))


# ── no live party: today's behaviour, unchanged ───────────────────────────────

func test_without_a_live_party_the_kit_is_untouched() -> void:
	## Headless, tests, and the editor opened outside a run. Falling back to the
	## level-1 kit is narrower than the validator — the safe direction, and what
	## shipped before this change.
	var base: Dictionary = AutobattleSystem.get_deep_check_kit("mage")
	var before: Array = (base.get("kit", []) as Array).duplicate()
	var after: Dictionary = _rc()._widen_kit_to_what_this_character_knows(base, "mage")
	assert_eq(after.get("kit", []), before,
		"with no GameLoop.party there is nothing to widen from, so the kit must be unchanged")


func test_a_name_that_matches_nobody_is_not_widened() -> void:
	## CONTROL on the matcher: the party is searched by name→id, and a miss must
	## fall back rather than widen from whoever happens to be first.
	_party_of(_mage_at(12))
	var base: Dictionary = AutobattleSystem.get_deep_check_kit("mage")
	var before: Array = (base.get("kit", []) as Array).duplicate()
	var after: Dictionary = _rc()._widen_kit_to_what_this_character_knows(base, "somebody_else")
	assert_eq(after.get("kit", []), before, "an unmatched character_id must not borrow another's kit")


# ── execution is not selection ────────────────────────────────────────────────

func test_compose_async_actually_widens_before_building_the_prompt() -> void:
	## Every arm above calls the helper directly. Deleting its call site would
	## leave them green while no composition was ever widened — and the widening
	## must happen BEFORE build_rule_composition, or the prompt renders the old kit.
	var src: String = _code_only(FileAccess.get_file_as_string("res://src/llm/RuleComposer.gd"))
	assert_false(src.is_empty(), "CONTROL: source must load")
	var widen_at: int = src.find("_widen_kit_to_what_this_character_knows(kit_context, character_id)")
	var build_at: int = src.find("build_rule_composition(")
	assert_true(widen_at != -1, "compose_async must widen the kit context it just fetched")
	assert_true(build_at != -1, "CONTROL: the prompt build call must still exist")
	assert_true(widen_at < build_at, "the widening must run before the prompt is built")


func test_the_prompt_renders_the_widened_kit() -> void:
	## The consequence a player meets: the ids reach the text the model reads.
	var ctx: Dictionary = _kit_for(12)
	var prompt: String = DP.build_rule_composition("autobattle", "hit them hard", [], ctx)
	assert_true(prompt.find("firaga") != -1, "the unlocked spell must appear in the prompt")
	assert_true(prompt.find("Ability ids you may use") != -1, "CONTROL: the kit block must render")
	assert_eq(prompt.find("thundaga"), -1, "and the not-yet-unlocked one must not")


func _code_only(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		if line.find("\"\"\"") != -1:
			continue
		var hash_at: int = line.find("#")
		out.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(out)
