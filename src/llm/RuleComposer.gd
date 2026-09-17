extends Node

## RuleComposer — LLM-driven rule authoring assistant.
##
## Domain-parameterized: autobattle rules are per-character (character_id required),
## autogrind rules are party-level (character_id MUST be ""). See design spec
## docs/superpowers/specs/2026-07-01-llm-rule-composer-and-monster-adaptation-design.md
##
## Signal contract:
##   composition_ready(result: Dictionary) — emitted on success OR curated fallback
##   composition_failed(reason: String, details: Dictionary) — LLM path failure

signal composition_ready(result: Dictionary)
signal composition_failed(reason: String, details: Dictionary)

const DOMAIN_AUTOBATTLE := "autobattle"
const DOMAIN_AUTOGRIND  := "autogrind"

const _VALID_DOMAINS := [DOMAIN_AUTOBATTLE, DOMAIN_AUTOGRIND]

## ItemSystem.ItemCategory.META — key items and equipment, not usable in a battle.
const ITEM_CATEGORY_META := 4

const DialoguePromptsScript := preload("res://src/llm/DialoguePrompts.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func has_llm() -> bool:
	if OS.has_feature("web"):
		return false
	var svc = get_node_or_null("/root/LLMService")
	if svc == null:
		return false
	if not svc.has_method("is_available"):
		return false
	return bool(svc.is_available())

## Full LLM refine path: domain validation, per-domain scope guards, prompt
## build + LLMService.complete_json call, second-pass parse, and every
## fallback branch. Every branch emits composition_ready; failure branches
## additionally emit composition_failed(reason, details) first.
func compose_async(domain: String, prompt_text: String, character_id: String = "", current_rules: Array = []) -> Dictionary:
	if not domain in _VALID_DOMAINS:
		var err = _empty_result(domain, character_id, "fallback")
		err["errors"] = ["invalid domain: '%s'" % domain]
		composition_failed.emit("invalid_domain", {"errors": err["errors"]})
		return err

	if domain == DOMAIN_AUTOBATTLE and character_id.strip_edges() == "":
		var e = _empty_result(domain, character_id, "fallback")
		e["errors"] = ["autobattle domain requires a character_id"]
		composition_failed.emit("scope_error", {"errors": e["errors"]})
		return e

	if domain == DOMAIN_AUTOGRIND and character_id.strip_edges() != "":
		var e = _empty_result(domain, character_id, "fallback")
		e["errors"] = ["autogrind domain must not receive a character_id (got '%s')" % character_id]
		composition_failed.emit("scope_error", {"errors": e["errors"]})
		return e

	if not has_llm():
		var res = _fallback_result(domain, character_id)
		composition_failed.emit("no_llm", {})
		composition_ready.emit(res)
		return res

	# The prompt is built from the validator's own kit view, so it cannot teach a
	# kit the deep check then rejects.
	var kit_context: Dictionary = {}
	if domain == DOMAIN_AUTOBATTLE and character_id != "":
		var abs_sys = get_node_or_null("/root/AutobattleSystem")
		if abs_sys != null and abs_sys.has_method("get_deep_check_kit"):
			kit_context = abs_sys.get_deep_check_kit(character_id)
			kit_context = _widen_kit_to_what_this_character_knows(kit_context, character_id)
			kit_context["items"] = _battle_item_ids()
	elif domain == DOMAIN_AUTOGRIND:
		kit_context = _party_kit_context()
	var prompt: String = DialoguePromptsScript.build_rule_composition(
		domain, prompt_text, current_rules, kit_context)
	var svc = get_node_or_null("/root/LLMService")
	var raw: Variant = await svc.complete_json(prompt, DialoguePromptsScript.SCHEMA_RULE_COMPOSITION, DialoguePromptsScript.FALLBACK_RULE_COMPOSITION)

	var reply: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else DialoguePromptsScript.FALLBACK_RULE_COMPOSITION.duplicate(true)

	var v: Dictionary = DialoguePromptsScript.validate_rule_composition(reply, domain)
	var is_fallback: bool = (
		not v["parse_ok"]
		or reply.get("name", "") == DialoguePromptsScript.FALLBACK_RULE_COMPOSITION["name"]
	)

	if is_fallback:
		var res_fb: Dictionary = _fallback_result(domain, character_id)
		composition_failed.emit("invalid_json", {})
		composition_ready.emit(res_fb)
		return res_fb

	# What the composer CHANGED, for the player to read. Separate from errors:
	# errors mean the ruleset was refused, notes mean it was silently edited.
	# Filled after the repair below, which mutates v["rules"] in place.
	var repair_notes: Array[String] = []

	var result := {
		"name": v["name"],
		"description": v["description"],
		"rules": v["rules"],
		"errors": [] as Array[String],
		"notes": repair_notes,
		"source": "llm",
		"domain": domain,
		"character_id": character_id,
	}

	# The mp_percent guard is DERIVABLE, not a judgement: a rule casting cure (6 MP
	# of a 70 pool) requires exactly mp_percent >= 9. The model was told the numbers
	# and still omitted the guard in 20 of 29 rejected rules, and one missing guard
	# discarded the player's WHOLE ruleset. Supplying it is arithmetic from the same
	# kit the validator uses; it can only turn a rejection into a valid rule, and it
	# never loosens a guard the model did emit.
	# A model writing "target": null means "no target", which this grammar expresses
	# by OMITTING the key — and the validator rejects the null form, discarding the
	# whole ruleset. Measured across 33 parseable local-llama3 compositions: 2 died
	# this way. Dropping the key is a normalisation, NOT a loosening of the
	# validator, which is right to refuse it: action.get("target", "lowest_hp_enemy")
	# returns null rather than the default when the key is present, and assigning
	# Nil to a typed String aborts the enclosing function in the grid editor.
	if domain == DOMAIN_AUTOBATTLE:
		_drop_null_targets(v["rules"])
		for note in _normalise_autobattle_statuses(v["rules"]):
			repair_notes.append(note)
		for note in _normalise_item_ids(v["rules"], kit_context.get("items", [])):
			repair_notes.append(note)
		## BEFORE the MP-guard pass below: an action only recognised as an ability AFTER it
		## never gets the guard the deep check then demands, and the rule is dropped.
		for note in _normalise_autobattle_shapes(v["rules"], kit_context):
			repair_notes.append(note)

	if domain == DOMAIN_AUTOBATTLE and bool(kit_context.get("resolved", false)):
		for note in _supply_missing_mp_guards(v["rules"], kit_context):
			repair_notes.append(note)

	if domain == DOMAIN_AUTOBATTLE:
		for note in _repair_weakness_elements(v["rules"]):
			repair_notes.append(note)

	var domain_system = get_node_or_null("/root/AutobattleSystem" if domain == DOMAIN_AUTOBATTLE else "/root/AutogrindSystem")

	# Autogrind refuses the whole ruleset for one bad rule, so a near-miss name is a
	# total loss. Both of these are normalisations against the system's own vocabulary.
	if domain == DOMAIN_AUTOGRIND:
		for note in _normalise_autogrind_conditions(v["rules"], domain_system):
			repair_notes.append(note)
		for note in _normalise_member_status(v["rules"]):
			repair_notes.append(note)
		for note in _normalise_switch_profile(v["rules"], kit_context):
			repair_notes.append(note)

	# A heal with no target is sent at the enemy by the evaluator's default.
	if domain == DOMAIN_AUTOBATTLE:
		for note in _aim_untargeted_abilities(v["rules"]):
			repair_notes.append(note)

	# Before the rule-level drop: a rule whose only fault is a restated target is
	# repairable, and dropping it loses the behaviour the player asked for.
	if domain == DOMAIN_AUTOBATTLE:
		for note in _drop_target_shaped_conditions(v["rules"], domain_system):
			repair_notes.append(note)

	# ONE bad rule discarded the player's WHOLE ruleset. Measured on live llama3 after
	# the prompt fix: 4 of 10 fighter compositions still fell back, 3 of them for a
	# single rule naming an ability the character does not have (esuna, raise) while
	# the other three rules in the set were valid. The player asked for a strategy and
	# got a canned fallback because one line of four was wrong.
	# Same shape as _drop_null_targets above: drop the offending rule, keep the rest,
	# and TELL the player. Never empties the set — a zero-rule composition is not a
	# valid one, it is the save-wiping one, so the caller's refusal path still runs.
	## The grind domain was left out of this when it shipped, and the asymmetry cost the
	## same thing it was written to prevent. Measured on 50 captured live replies across
	## five deliberately messy intents: 4 died on ONE rule each — a null numeric value, a
	## null operator, an invented `rest` action, and one malformed rule — while the rest of
	## each set was valid. None of those four is repairable by lookup; dropping the rule is
	## the only honest move, and it is the move this project already chose for autobattle.
	if domain == DOMAIN_AUTOBATTLE and character_id != "":
		for note in _drop_unusable_rules(v["rules"], character_id, domain_system):
			repair_notes.append(note)
	elif domain == DOMAIN_AUTOGRIND:
		for note in _drop_unusable_rules(v["rules"], "", domain_system):
			repair_notes.append(note)

	# Last, so it orders whatever the other repairs left behind.
	if v.has("rules") and (v["rules"] as Array).size() > 1:
		for note in _sink_unconditional_rules(v["rules"]):
			repair_notes.append(note)
	var grammar_errors: Array[String] = []
	if domain_system != null and domain_system.has_method("validate_rule"):
		# autobattle passes character_id → deep-check (unknown ability, out-of-kit,
		# mp-starve, unknown item); autogrind stays shallow (party-level, no PC).
		for r in v["rules"]:
			var rule_errs: Array = domain_system.validate_rule(r, character_id) if domain == DOMAIN_AUTOBATTLE else domain_system.validate_rule(r)
			for err in rule_errs:
				grammar_errors.append(err)
	if grammar_errors.size() > 0:
		var res_bad: Dictionary = _fallback_result(domain, character_id)
		res_bad["errors"] = grammar_errors
		composition_failed.emit("grammar_errors", {"errors": grammar_errors})
		composition_ready.emit(res_bad)
		return res_bad

	composition_ready.emit(result)
	return result

func _empty_result(domain: String, character_id: String, source: String) -> Dictionary:
	return {
		"name": "",
		"description": "",
		"rules": [],
		"errors": [] as Array[String],
		"notes": [] as Array[String],
		"source": source,
		"domain": domain,
		"character_id": character_id,
	}

func _fallback_result(domain: String, character_id: String) -> Dictionary:
	return {
		"name": DialoguePromptsScript.FALLBACK_RULE_COMPOSITION["name"],
		"description": DialoguePromptsScript.FALLBACK_RULE_COMPOSITION["description"],
		"rules": [],
		"errors": [] as Array[String],
		"notes": [] as Array[String],
		"source": "fallback",
		"domain": domain,
		"character_id": character_id,
	}


## Add or raise the mp_percent guard each rule needs, in place.
##
## Mirrors _deep_check_rule's arithmetic exactly — summed MP cost of the rule's
## ability actions against the character's pool — so a repaired rule is one the
## validator accepts by construction rather than by coincidence. Rules whose
## abilities are unknown or out-of-kit are left alone: those are the model's
## errors to fail on, not arithmetic this can fix.
func _supply_missing_mp_guards(rules: Array, kit_context: Dictionary) -> Array[String]:
	var costs: Dictionary = kit_context.get("costs", {})
	var kit: Array = kit_context.get("kit", [])
	var max_mp: int = int(kit_context.get("max_mp", 0))
	var notes: Array[String] = []
	if max_mp <= 0:
		return notes
	for idx in range(rules.size()):
		var rule = rules[idx]
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		var total: int = 0
		var repairable: bool = true
		for a in rule.get("actions", []):
			if typeof(a) != TYPE_DICTIONARY or str(a.get("type", "")) != "ability":
				continue
			var aid: String = str(a.get("id", ""))
			if not (aid in kit) or a.has("upgrades"):
				repairable = false
				break
			total += int(costs.get(aid, 0))
		if not repairable or total <= 0:
			continue
		var need: int = ceili(float(total) / float(max_mp) * 100.0)
		var conditions: Array = rule.get("conditions", [])
		var raised: bool = false
		var changed: bool = false
		for c in conditions:
			if typeof(c) != TYPE_DICTIONARY:
				continue
			if str(c.get("type", "")) == "mp_percent" and str(c.get("op", "")) == ">=":
				if int(c.get("value", 0)) < need:
					c["value"] = need
					changed = true
				raised = true
		if not raised:
			conditions.append({"type": "mp_percent", "op": ">=", "value": need})
			rule["conditions"] = conditions
			notes.append("Rule %d (%s): added an MP check of at least %d%% so it cannot fizzle."
				% [idx + 1, _rule_ability_label(rule), need])
		elif changed:
			notes.append("Rule %d (%s): raised the MP check to %d%%, the minimum it needs."
				% [idx + 1, _rule_ability_label(rule), need])
	return notes


## Name a rule by the ability it casts, for a player-facing note. The note also
## carries the rule's 1-based position, because two rules casting the SAME ability
## produced identical notes and the player could not tell which one was edited —
## measured on real llama3 output, where duplicate 'cure' rules are common.
func _rule_ability_label(rule: Dictionary) -> String:
	for a in rule.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "ability":
			var aid: String = str(a.get("id", ""))
			if aid != "":
				return "'%s'" % aid
	return "costed"


## Remove `"target": null` from actions, in place. Returns how many were dropped.
##
## ONLY target, deliberately. Absent is a documented, defined state for it — the
## action falls back to its own default — so dropping the key changes nothing
## about what the rule DOES, which is why this emits no player-facing note.
##
## Every OTHER null is left for the validator to reject. A condition carrying
## "value": null is genuinely broken: the model failed to state a threshold, and
## stripping that key would manufacture a rule that validates and then compares
## against a default nobody chose. Refusing it is the honest outcome; recovering
## it would be exactly the plausible-looking artifact that is worse than a refusal.
## Drop rules the deep check refuses, keeping the ones that pass. Returns notes.
##
## Refusing a whole ruleset for one bad rule is the difference between the player
## getting their strategy minus a line, and getting a canned fallback that ignores
## what they asked for. Returns [] and leaves `rules` UNTOUCHED when nothing would
## survive, so the caller refuses normally rather than handing back an empty set.
func _drop_unusable_rules(rules: Array, character_id: String, domain_system) -> Array[String]:
	var notes: Array[String] = []
	if domain_system == null or not domain_system.has_method("validate_rule"):
		return notes
	var kept: Array = []
	var dropped: Array[String] = []
	for r in rules:
		## autobattle's validate_rule takes the character for its deep check; autogrind's is
		## party-level and takes the rule alone. Same refusal, different arity.
		var errs: Array = domain_system.validate_rule(r, character_id) if character_id != "" \
			else domain_system.validate_rule(r)
		if errs.is_empty():
			kept.append(r)
		else:
			dropped.append(str(errs[0]))
	if dropped.is_empty():
		return notes
	# SUBSTANTIVE FLOOR — and it subsumes the empty case: an empty `kept` has no
	# substantive rule by definition, so a separate kept.is_empty() check was dead
	# logic. Measured by mutation: removing it changed nothing, because this floor
	# was already catching it. Two guards on one property defeat a single mutation.
	# SUBSTANTIVE FLOOR. Measured: without it, 3 of 10 compositions were "rescued"
	# down to nothing but the trailing {always} -> attack line. That scores as a
	# success and hands the player plain attack labelled as the strategy they asked
	# for — worse than the canned fallback, which is at least honest about being one.
	# A rescue is only worth making if a rule the player would recognise survives.
	var substantive: bool = false
	for k in kept:
		for c in (k as Dictionary).get("conditions", []):
			if str((c as Dictionary).get("type", "")) != "always":
				substantive = true
				break
		if substantive:
			break
	if not substantive:
		return notes
	rules.clear()
	rules.append_array(kept)
	for d in dropped:
		notes.append("Dropped a rule this character cannot run — %s" % d)
	return notes


## Offer the abilities this character has actually unlocked, not the level-1 kit.
##
## `get_deep_check_kit` returns two sets and the prompt rendered the narrower one:
##
##     kit       job.abilities + free_move          NO level-gated entries
##     full_kit  kit + every abilities_at_level     ALL levels, unfiltered
##
## The prompt says "Ability ids you may use, and NOTHING else" over `kit`, while
## `_deep_check_rule` validates against `full_kit`. So the validator would have
## accepted fira/firaga/thundaga all along and the model was told they do not
## exist — a level-20 Mage asking for its strongest fire spell got `fire`.
##
## The intersection is the correct set, and both halves are load-bearing:
##   knows_ability   struktured's provenance-blind predicate, the only thing that
##                   gates on job_level (and the reason this is not a re-derivation)
##   full_kit        the deep check's own vocabulary — offering anything outside it
##                   would make _drop_unusable_rules discard the rule as unrunnable
##
## Learned and secondary-job abilities are deliberately NOT added: they sit outside
## full_kit, so the validator would reject them and the player would be told a rule
## they can run cannot run. Purchased spells need no special case — the shop sells
## from abilities_at_level, so they are already inside full_kit.
##
## No live party (headless, tests, the editor opened outside a run) falls back to
## the level-1 kit unchanged — narrower than the validator, which is the safe
## direction and exactly today's behaviour.
func _widen_kit_to_what_this_character_knows(ctx: Dictionary, character_id: String) -> Dictionary:
	if ctx.is_empty() or not bool(ctx.get("resolved", false)):
		return ctx
	var who = _live_combatant_for(character_id)
	if who == null or not who.has_method("knows_ability"):
		return ctx
	var kit: Array = (ctx.get("kit", []) as Array).duplicate()
	var costs: Dictionary = (ctx.get("costs", {}) as Dictionary).duplicate()
	var job_sys = get_node_or_null("/root/JobSystem")
	for aid in (ctx.get("full_kit", []) as Array):
		var id: String = str(aid)
		if kit.has(id) or not who.knows_ability(id):
			continue
		kit.append(id)
		# A missing cost renders as "0 MP" and the model omits the guard, so the
		# rule fizzles for want of MP. Every added id carries its real cost.
		costs[id] = int((job_sys.get_ability(id) as Dictionary).get("mp_cost", 0)) if job_sys != null else 0
	ctx["kit"] = kit
	ctx["costs"] = costs
	return ctx


## The live Combatant for a character_id, matched the way the rest of the codebase
## derives one from a name. GameLoop.party holds instances; GameState.player_party
## holds to_dict() snapshots, and from_dict does NOT restore `job` — a rehydrated
## snapshot answers "no" to its own job kit, measured.

## The grind grammar asks member_ability for "an ability id that member knows" and the
## prompt named no abilities at all. Measured on live llama3 2026-09-17, an intent that
## asks for one: 24 of 24 emitted ids were absent from abilities.json — 'revive' and
## 'heal' for the real 'raise' and 'cure'. The engine skips an unknown id with a stdout
## print, so the rule silently never fires.
## The item ids an `item` action may name. The deep check accepts ANY id in items.json, but
## only the four battle categories are usable in a fight — META is 146 of the 172 and is key
## items and equipment. Derived from ItemSystem rather than listed here.
##
## Measured on live llama3 2026-09-17, an intent needing ids the grammar does not exemplify
## ("cure blindness with eye drops, use echo herbs the moment someone is silenced"): 19 of 20
## `item` action ids were unknown — `echo_herb` 14, `echo` 5, against the real `echo_herbs`.
## The deep check turns each into a grammar error, and one grammar error discards the WHOLE
## composition. An earlier run with an intent asking for `potion` scored 0 of 19 wrong, which
## measured the grammar's own example rather than the prompt.
func _battle_item_ids() -> Array:
	var sys = get_node_or_null("/root/ItemSystem")
	if sys == null or not ("items" in sys):
		return []
	var out: Array = []
	for iid in (sys.items as Dictionary):
		var item: Dictionary = sys.items[iid]
		if int(item.get("category", -1)) == ITEM_CATEGORY_META:
			continue
		out.append(str(iid))
	out.sort()
	return out


func _party_kit_context() -> Dictionary:
	var gl = get_node_or_null("/root/GameLoop")
	var abs_sys = get_node_or_null("/root/AutobattleSystem")
	if gl == null or not ("party" in gl):
		return {}
	if abs_sys == null or not abs_sys.has_method("get_deep_check_kit"):
		return {}
	var members: Array = []
	for member in gl.party:
		if member == null or not is_instance_valid(member):
			continue
		var cid: String = str(member.combatant_name).to_lower().replace(" ", "_")
		var kit: Dictionary = abs_sys.get_deep_check_kit(cid)
		if not bool(kit.get("resolved", false)):
			continue
		kit = _widen_kit_to_what_this_character_knows(kit, cid)
		var profile_names: Array = []
		if abs_sys.has_method("get_character_profiles"):
			for prof in (abs_sys.get_character_profiles(cid) as Array):
				profile_names.append(str((prof as Dictionary).get("name", "Profile")))
		members.append({
			"member": cid,
			"job_id": str(kit.get("job_id", "")),
			"kit": kit.get("kit", []),
			"costs": kit.get("costs", {}),
			"profiles": profile_names,
		})
	if members.is_empty():
		return {}
	return {"resolved": true, "party": members}

func _live_combatant_for(character_id: String):
	var gl = get_node_or_null("/root/GameLoop")
	if gl == null or not ("party" in gl):
		return null
	for member in gl.party:
		if member == null or not is_instance_valid(member):
			continue
		if str(member.combatant_name).to_lower().replace(" ", "_") == character_id:
			return member
	return null


## Read an enemy_weak_to element the model named after the ABILITY, not the element.
##
## The condition matches `element in enemy.elemental_weaknesses` — a case-sensitive
## compare against the bestiary's own words. validate_rule checks that the field is
## PRESENT and never what it says: `weather` is the one payload with a vocabulary
## check, and its comment gives the reason — a bad value must fail at decode rather
## than silently-never-fire in battle. An element does neither today.
##
## Measured against live llama3 on the real composer prompt, four weakness intents,
## 48 compositions: 36 enemy_weak_to conditions, 35 valid and ONE naming the ability
## — {"element":"thunder"} beside the 'thunder' action, whose element is `lightning`.
## The kit itself invites it: two of the mage's three spells are named for something
## other than the element they deal (blizzard/ice, thunder/lightning).
##
## This MAPS rather than drops. The model named a real ability and the ability knows
## its element, so the rule the player asked for is recoverable. It acts ONLY when the
## string is an ability id whose element is a different word, so it can never touch a
## real element — `fire` is the one word that is both, and it maps to itself. An
## element nothing is weak to is left alone; the grammar promises that on purpose.
func _repair_weakness_elements(rules: Array) -> Array[String]:
	var notes: Array[String] = []
	var job_sys = get_node_or_null("/root/JobSystem")
	for r in rules:
		if not (r is Dictionary):
			continue
		for c in (r as Dictionary).get("conditions", []):
			if not (c is Dictionary):
				continue
			var cond: Dictionary = c as Dictionary
			if str(cond.get("type", "")) != "enemy_weak_to":
				continue
			var raw: String = str(cond.get("element", "")).strip_edges()
			if raw == "":
				continue
			var low: String = raw.to_lower()
			# Case alone is not measured, only free: every weakness in monsters.json
			# is lowercase, and the compare that reads it is case-sensitive.
			if low != raw:
				cond["element"] = low
			if job_sys == null or not job_sys.has_method("get_ability"):
				continue
			var elem: String = str((job_sys.get_ability(low) as Dictionary).get("element", "")).strip_edges().to_lower()
			if elem == "" or elem == low:
				continue
			cond["element"] = elem
			notes.append("Read '%s' as its element, %s — '%s' is an ability, not an element." % [raw, elem, raw])
	return notes


## Move catch-all rules to the bottom so they stop shadowing the player's intent.
##
## Rules are evaluated top-to-bottom, first match wins (AutobattleSystem: "Evaluate
## rules in order"). A rule whose conditions are all `always` matches every turn, so
## anything below it is unreachable. The prompt already asks for the fallback last;
## measured against live llama3, 2 of 13 multi-rule compositions ignored that and
## buried the rules the player actually asked for.
##
## Sinking is safe by construction: an always-rule matches regardless of position, so
## moving it last preserves it as the fallback it is and un-shadows the rest. Order
## among the sunk rules is preserved, so a model that emitted two keeps its own.
func _sink_unconditional_rules(rules: Array) -> Array[String]:
	var notes: Array[String] = []
	var first: int = -1
	for i in rules.size():
		if rules[i] is Dictionary and _is_catch_all(rules[i] as Dictionary):
			first = i
			break
	# No catch-all, or it is already last: nothing below it, nothing shadowed.
	var shadowed: int = (rules.size() - first - 1) if first != -1 else 0
	if shadowed <= 0:
		return notes
	var specific: Array = []
	var catch_all: Array = []
	for r in rules:
		if r is Dictionary and _is_catch_all(r as Dictionary):
			catch_all.append(r)
		else:
			specific.append(r)
	rules.clear()
	rules.append_array(specific)
	rules.append_array(catch_all)
	notes.append("Moved the catch-all rule last — %d rule%s below it could never run." % [
		shadowed, "" if shadowed == 1 else "s"])
	return notes


## True when the rule fires on any turn — because every condition is `always`, OR
## because it has none. Both engines treat an absent/empty condition list as a
## match: AutobattleSystem._evaluate_grid_rule ("No conditions = always match")
## and AutogrindSystem's party-rule evaluator both return true for size() == 0.
## llama3 emits that shape, so reading it as "not a catch-all" left it in place
## shadowing every rule below it.
func _is_catch_all(rule: Dictionary) -> bool:
	var conds: Array = rule.get("conditions", []) as Array
	if conds.is_empty():
		return true
	for c in conds:
		if not (c is Dictionary) or str((c as Dictionary).get("type", "")) != "always":
			return false
	return true


## Two autogrind shapes that cost the player the WHOLE ruleset, both normalisations.
##
## Autogrind has no per-rule rescue — one bad rule and the composition falls back — so a
## near-miss name is a total loss. Measured on 24 live llama3 autogrind compositions:
##
##   party_corruption                       2 of 24, each the composition's ONLY rule
##   {"type":"always","op":"","value":""}   1 of 24, beside two valid rules
##
## 1. `party_corruption` is the model generalising from its own siblings — the grammar
##    lists party_hp_min / party_hp_avg / party_mp_avg beside a bare `corruption`. The
##    prefix is stripped ONLY when the remainder is itself a live condition type, so this
##    is a lookup in the system's own vocabulary, not a table of guesses kept here.
## 2. `always` takes no payload, and validate_rule rejects a PRESENT `op` that is empty
##    rather than ignoring it. Erasing an empty payload key from a nullary condition
##    changes nothing the rule asks — the same shape as _drop_null_targets.
## member_status carries ONE status id, and validate_rule refuses anything else — which
## discards the WHOLE composition, not the rule. Measured on live llama3 2026-09-17, after the
## prompt was given the vocabulary: 3 of 20 compositions put an ARRAY in `value` ("or" spelled
## the way the player said it), and a residual English participle survived the instruction.
##
## Both are lookups in DialoguePrompts.STATUS_VOCABULARY, the same table the prompt
## renders — not a table of guesses kept here. An array becomes one rule per id because OR is
## what this grammar's rule list already means; the conditions are AND-chained, so cloning the
## rule preserves every other condition it carried.
## switch_profile names ONE member, and validate_rule checks only that the KEY is present —
## so any string passes. Measured on live llama3 2026-09-17, an intent asking to switch the
## whole party, 20 samples: 20 of 20 character_ids named nobody.
##
##     ""          7    passes validation, then apply_autogrind_actions skips on the != "" test
##     everyone    4    the model reaching for something the grammar cannot say
##     *           4
##     all         3
##     defensive   1    the profile NAME in the id field
##     None        1
##
## The middle eleven are the damaging ones, and not because they no-op: set_active_profile
## calls _ensure_character_profiles FIRST, so an invented id CREATES a profile block and
## _save_character_profiles persists it. Probed: character_profiles["everyone"] created with
## 3 profiles and active=1, written to user://autobattle/profiles.json in real play.
##
## A party word becomes one action per member — the grammar's own way to say it, and exactly
## what the intent asked for. An id naming nobody is DROPPED, because the alternative is
## letting it reach the save. Both need the live party, so with no kit context this does
## nothing: unable to verify is not the same as verified absent.
func _normalise_switch_profile(rules: Array, kit_context: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	if not bool(kit_context.get("resolved", false)):
		return notes
	var members: Array = []
	for raw in (kit_context.get("party", []) as Array):
		members.append(str((raw as Dictionary).get("member", "")))
	if members.is_empty():
		return notes
	const PARTY_WORDS := ["everyone", "everybody", "all", "*", "party", "the party", "all members"]
	for rule in rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		var actions: Array = rule.get("actions", [])
		var i: int = 0
		while i < actions.size():
			var a = actions[i]
			i += 1
			if typeof(a) != TYPE_DICTIONARY or str(a.get("type", "")) != "switch_profile":
				continue
			## A scalar slot given an array is the same shape member_status showed: the model
			## spelling "each of them" as a list. Measured here 3 of 36 for the id and 1 for
			## the index. An absent key is refused by validate_rule, which discards the WHOLE
			## composition — dropping the one action is the cheaper loss.
			if typeof(a.get("profile_index")) == TYPE_ARRAY:
				var idxs: Array = a["profile_index"]
				if idxs.size() == 1 and typeof(idxs[0]) == TYPE_INT:
					a["profile_index"] = idxs[0]
					notes.append("Read a one-item profile_index list as the slot it holds.")
			if not a.has("character_id") or not a.has("profile_index"):
				actions.remove_at(i - 1)
				i -= 1
				notes.append("Dropped an incomplete switch_profile — it needs both a member and a slot.")
				continue
			if typeof(a.get("character_id")) == TYPE_ARRAY:
				var named: Array = []
				for entry in (a["character_id"] as Array):
					var one: String = str(entry).strip_edges().to_lower()
					if members.has(one) and not named.has(one):
						named.append(one)
				if named.is_empty():
					actions.remove_at(i - 1)
					i -= 1
					notes.append("Dropped a switch_profile — none of the names it listed are in the party.")
					continue
				a["character_id"] = named[0]
				notes.append("Split a list of members into one switch_profile each.")
				for extra in named.slice(1):
					var clone_of_list: Dictionary = a.duplicate(true)
					clone_of_list["character_id"] = extra
					actions.insert(i, clone_of_list)
					i += 1
				continue
			var cid: String = str(a.get("character_id", "")).strip_edges().to_lower()
			if members.has(cid):
				continue
			if PARTY_WORDS.has(cid):
				a["character_id"] = members[0]
				notes.append("Read '%s' as every member — switch_profile names one at a time." % cid)
				for extra in members.slice(1):
					var clone: Dictionary = a.duplicate(true)
					clone["character_id"] = extra
					actions.insert(i, clone)
					i += 1
				continue
			actions.remove_at(i - 1)
			i -= 1
			notes.append("Dropped a switch_profile for '%s' — nobody in the party has that name." % cid)
	return notes


## An autobattle condition's `status` field, matched literally by Combatant.has_status.
## Measured 7 of 19 unmatchable on an intent about being silenced — the model wrote
## "silenced". Same lookup as the grind's, same table, because it is the same engine call.
## Three shapes measured across 48 captured live replies, 4 jobs x 12, replayed through the
## real compose_async. One grammar error discards the whole composition, so each cost a
## player their entire ruleset:
##
##     {"type":"ally_dead","op":"","value":null}      an empty payload on a NULLARY condition
##     {"type":"ally_hp_percent","op":">=0"}          the operator and value fused
##     {"type":"lullaby","target":"self"}             an ability id used as the action TYPE
##
## Every repair is a lookup in AutobattleSystem's own vocabulary or a parse of the string's
## own content. The ability rewrite is scoped to THIS character's kit, so it can only
## produce an action the deep check would already have accepted.
func _normalise_autobattle_shapes(rules: Array, kit_context: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var domain_system = get_node_or_null("/root/AutobattleSystem")
	if domain_system == null:
		return notes
	var nullary: Array = domain_system.NULLARY_CONDITIONS if "NULLARY_CONDITIONS" in domain_system else []
	var operators: Dictionary = domain_system.OPERATORS if "OPERATORS" in domain_system else {}
	var actions_ok: Dictionary = domain_system.ACTION_TYPES if "ACTION_TYPES" in domain_system else {}
	var kit: Array = kit_context.get("kit", [])
	for rule in rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		for c in rule.get("conditions", []):
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var ctype: String = str(c.get("type", ""))
			## A nullary condition carrying an empty payload — the same repair the autogrind
			## side has had all along, absent here only because nothing named the set.
			if nullary.has(ctype):
				for key in ["op", "value"]:
					if c.has(key) and (c[key] == null or str(c[key]) == ""):
						c.erase(key)
						notes.append("Dropped an empty '%s' from '%s' — it takes no payload." % [key, ctype])
				continue
			## The operator and its value fused into one string. Splitting it is a PARSE of
			## what the model wrote, not a guess — and it is refused when a separate value
			## is already present and disagrees, because then it IS a guess.
			var raw_op: String = str(c.get("op", ""))
			if raw_op == "" or operators.has(raw_op):
				continue
			for op in operators.keys():
				var op_s: String = str(op)
				if not raw_op.begins_with(op_s):
					continue
				var tail: String = raw_op.substr(op_s.length()).strip_edges()
				if not tail.is_valid_float():
					continue
				if c.has("value") and str(c["value"]) != tail:
					break
				c["op"] = op_s
				c["value"] = float(tail) if tail.contains(".") else int(tail)
				notes.append("Read '%s' as op '%s' with value %s." % [raw_op, op_s, tail])
				break
		var acts: Array = rule.get("actions", [])
		for a in acts:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var atype: String = str(a.get("type", ""))
			if actions_ok.has(atype) or not kit.has(atype):
				continue
			a["type"] = "ability"
			a["id"] = atype
			notes.append("Read '%s' as the ability it names — an ability is an action's id." % atype)
	return notes


func _normalise_autobattle_statuses(rules: Array) -> Array[String]:
	const STATUS_CONDITIONS := ["has_status", "not_has_status", "ally_has_status",
		"enemy_has_status", "not_enemy_has_status"]
	var notes: Array[String] = []
	var spellings: Dictionary = {}
	for id in DialoguePromptsScript.STATUS_VOCABULARY:
		spellings[str(id)] = str(id)
		for word in (DialoguePromptsScript.STATUS_VOCABULARY[id] as Array):
			spellings[str(word).to_lower()] = str(id)
	for rule in rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		for c in rule.get("conditions", []):
			if typeof(c) != TYPE_DICTIONARY or not STATUS_CONDITIONS.has(str(c.get("type", ""))):
				continue
			var raw: String = str(c.get("status", ""))
			var key: String = raw.strip_edges().to_lower()
			if raw == "" or spellings.get(key, "") == raw:
				continue
			if not spellings.has(key):
				continue
			c["status"] = spellings[key]
			notes.append("Read '%s' as '%s', the id the engine matches." % [raw, spellings[key]])
	return notes


## An `item` action's id is deep-checked, so a near miss discards the WHOLE composition —
## `echo_herb` for `echo_herbs` was 14 of 20 on one intent. The match normalises separators
## and an optional trailing 's', which is a defined rewrite rather than a guess: if two real
## ids collapse to the same key the id is left alone, because then it IS a guess.
func _normalise_item_ids(rules: Array, item_ids: Array) -> Array[String]:
	var notes: Array[String] = []
	if item_ids.is_empty():
		return notes
	var folded: Dictionary = {}
	for iid in item_ids:
		var key: String = _fold_item_id(str(iid))
		folded[key] = "" if folded.has(key) else str(iid)
	for rule in rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		for a in rule.get("actions", []):
			if typeof(a) != TYPE_DICTIONARY or str(a.get("type", "")) != "item":
				continue
			var raw: String = str(a.get("id", ""))
			if raw == "" or item_ids.has(raw):
				continue
			var real: String = str(folded.get(_fold_item_id(raw), ""))
			if real == "":
				continue
			a["id"] = real
			notes.append("Read item '%s' as '%s'." % [raw, real])
		for c in rule.get("conditions", []):
			if typeof(c) != TYPE_DICTIONARY or str(c.get("type", "")) != "item_count":
				continue
			var raw_c: String = str(c.get("item_id", ""))
			if raw_c == "" or item_ids.has(raw_c):
				continue
			var real_c: String = str(folded.get(_fold_item_id(raw_c), ""))
			if real_c == "":
				continue
			c["item_id"] = real_c
			notes.append("Read item '%s' as '%s'." % [raw_c, real_c])
	return notes


func _fold_item_id(raw: String) -> String:
	var flat: String = raw.to_lower().replace("_", "").replace("-", "").replace(" ", "")
	return flat.trim_suffix("s")


func _normalise_member_status(rules: Array) -> Array[String]:
	var notes: Array[String] = []
	var spellings: Dictionary = {}
	for id in DialoguePromptsScript.STATUS_VOCABULARY:
		spellings[str(id)] = str(id)
		for word in (DialoguePromptsScript.STATUS_VOCABULARY[id] as Array):
			spellings[str(word).to_lower()] = str(id)
	var i: int = 0
	while i < rules.size():
		var rule = rules[i]
		i += 1
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		for c in rule.get("conditions", []):
			if typeof(c) != TYPE_DICTIONARY or str(c.get("type", "")) != "member_status":
				continue
			var raw: Variant = c.get("value", "")
			var wanted: Array = raw if typeof(raw) == TYPE_ARRAY else [raw]
			var ids: Array = []
			for entry in wanted:
				var key: String = str(entry).strip_edges().to_lower()
				if spellings.has(key) and not ids.has(spellings[key]):
					ids.append(spellings[key])
			if ids.is_empty():
				continue
			if typeof(raw) != TYPE_ARRAY and ids[0] == str(raw):
				continue
			c["value"] = ids[0]
			if typeof(raw) == TYPE_ARRAY:
				notes.append("Split '%s' into one rule per status — a rule asks for one." % str(raw))
			else:
				notes.append("Read '%s' as '%s', the id the engine matches." % [str(raw), ids[0]])
			for extra in ids.slice(1):
				var clone: Dictionary = rule.duplicate(true)
				for cc in clone.get("conditions", []):
					if typeof(cc) == TYPE_DICTIONARY and str(cc.get("type", "")) == "member_status":
						cc["value"] = extra
				rules.insert(i, clone)
				i += 1
	return notes


func _normalise_autogrind_conditions(rules: Array, domain_system) -> Array[String]:
	var notes: Array[String] = []
	if domain_system == null or not ("PARTY_CONDITION_TYPES" in domain_system):
		return notes
	var types: Dictionary = domain_system.PARTY_CONDITION_TYPES
	var nullary: Array = domain_system.NULLARY_CONDITIONS if "NULLARY_CONDITIONS" in domain_system else []
	var named: Array = domain_system.NAMED_VALUE_CONDITIONS if "NAMED_VALUE_CONDITIONS" in domain_system else []
	var operators: Dictionary = domain_system.OPERATORS if "OPERATORS" in domain_system else {}
	for note in _expand_or_conditions(rules, types):
		notes.append(note)
	for rule in rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		for c in rule.get("conditions", []):
			if typeof(c) != TYPE_DICTIONARY:
				continue
			## The model writes the TYPE as the KEY: {"always": ""} for {"type":"always"}.
			## Only when exactly one key is itself a live condition type — anything looser
			## would rewrite a rule on the strength of a coincidence.
			if not c.has("type") and c.size() == 1:
				var only_key: String = str(c.keys()[0])
				if types.has(only_key):
					var carried: Variant = c[only_key]
					c.erase(only_key)
					c["type"] = only_key
					if str(carried) != "" and not nullary.has(only_key):
						c["value"] = carried
					notes.append("Read {\"%s\": …} as a '%s' condition." % [only_key, only_key])
			var ctype: String = str(c.get("type", ""))
			## The mirror of the party_ strip below: the model writes `member_hp_min` for an
			## aggregate that is spelled party_hp_min. Swapped ONLY when the swapped name is
			## itself a live type, so this is a lookup in the system's vocabulary.
			if not types.has(ctype) and ctype.begins_with("member_"):
				var swapped: String = "party_" + ctype.substr("member_".length())
				if types.has(swapped):
					c["type"] = swapped
					notes.append("Read '%s' as '%s' — that aggregate is party-level." % [ctype, swapped])
					ctype = swapped
			## An aggregate suffix on a live type: `corruption_avg` for `corruption`, measured
			## 1 of 20 on a second grind intent. Stripped ONLY when the remainder is itself a
			## live type — and the ORDER matters: member_hp_min strips to the live member_hp,
			## which is the wrong answer, so the party_ swap above runs first and claims it.
			if not types.has(ctype) and ctype.contains("_"):
				var head: String = ctype.substr(0, ctype.rfind("_"))
				if types.has(head):
					c["type"] = head
					notes.append("Read '%s' as '%s' — the comparison already carries the aggregate." % [ctype, head])
					ctype = head
			if not types.has(ctype) and ctype.begins_with("party_"):
				var stripped: String = ctype.substr("party_".length())
				if types.has(stripped):
					c["type"] = stripped
					notes.append("Read '%s' as '%s' — the condition this grind rule meant." % [ctype, stripped])
					ctype = stripped
			if ctype in nullary:
				for key in ["op", "value"]:
					if c.has(key) and str(c[key]) == "":
						c.erase(key)
						notes.append("Dropped an empty '%s' from '%s' — it takes no payload." % [key, ctype])
			## A named-value condition asks "does this member HAVE it" — the evaluator never
			## reads op. validate_rule refuses an unknown one and that discards the whole
			## composition, so an op it cannot use is dropped rather than paid for.
			if named.has(ctype) and c.has("op") and not operators.has(str(c["op"])):
				var bad_op: String = str(c["op"])
				c.erase("op")
				notes.append("Dropped op '%s' from '%s' — it asks whether the status is present." % [bad_op, ctype])
	return notes


## The model reaches for boolean composition this grammar does not have — `or` with a
## nested `options` list, `any_of` with `conditions`. Measured 2 of 20 live compositions,
## each a total loss. Conditions are AND-chained and first match wins, so OR is spelled as
## SEPARATE RULES: one rule per branch, carrying every sibling condition and the actions.
func _expand_or_conditions(rules: Array, types: Dictionary) -> Array[String]:
	const OR_TYPES := ["or", "any_of", "either", "any"]
	const BRANCH_KEYS := ["conditions", "options", "any", "branches"]
	var notes: Array[String] = []
	var i: int = 0
	while i < rules.size():
		var rule = rules[i]
		i += 1
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		var conds: Array = rule.get("conditions", [])
		var at: int = -1
		var branches: Array = []
		for j in conds.size():
			var c = conds[j]
			if typeof(c) != TYPE_DICTIONARY or not OR_TYPES.has(str(c.get("type", ""))):
				continue
			for key in BRANCH_KEYS:
				if typeof(c.get(key)) == TYPE_ARRAY and (c[key] as Array).size() > 0:
					branches = c[key]
					at = j
					break
			if at != -1:
				break
		if at == -1:
			continue
		conds.remove_at(at)
		conds.insert(at, branches[0])
		notes.append("Split an OR into one rule per branch — in this grammar, rules ARE the or.")
		for extra in branches.slice(1):
			var clone: Dictionary = rule.duplicate(true)
			(clone["conditions"] as Array)[at] = extra
			rules.insert(i, clone)
			i += 1
	return notes


## An ability action with NO target key, aimed by the ability's own declaration.
##
## The evaluator defaults a missing target to `lowest_hp_enemy`
## (AutobattleSystem._action_def_to_action), and `_resolve_ability_targets` only
## overrides that for all_allies / all_enemies / dead_ally — `single_ally` falls
## through. So a composed `{"type":"ability","id":"cure"}` with no target HEALS THE
## ENEMY. Measured: 1 of 12 live llama3 cleric compositions emitted exactly that.
##
## The fix is arithmetic from the ability's own data, like the MP guards: cure
## declares target_type single_ally, so the rule is aimed at an ally. Offensive
## abilities are left alone — the existing default is already correct for them, and
## writing it out would be a second copy of the engine's default.
func _aim_untargeted_abilities(rules: Array) -> Array[String]:
	var notes: Array[String] = []
	var js = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return notes
	for rule in rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		for a in rule.get("actions", []):
			if typeof(a) != TYPE_DICTIONARY or str(a.get("type", "")) != "ability":
				continue
			if a.has("target"):
				continue
			var aid: String = str(a.get("id", a.get("ability_id", "")))
			var ability: Variant = js.get_ability(aid)
			if not (ability is Dictionary) or (ability as Dictionary).is_empty():
				continue
			var declared: String = str((ability as Dictionary).get("target_type", ""))
			var aim: String = ""
			match declared:
				"single_ally", "all_allies":
					aim = "lowest_hp_ally"
				"self":
					aim = "self"
			if aim == "":
				continue
			a["target"] = aim
			notes.append("Aimed '%s' at %s — it had no target, and an untargeted ability is sent at the enemy." % [aid, aim])
	return notes


## A TARGET name used as a CONDITION type, when the rule's own action already aims
## there — {"type":"lowest_hp_enemy"} beside {"target":"lowest_hp_enemy"}.
##
## The condition carries no intent the action does not already carry, but it is not a
## condition type, so `_drop_unusable_rules` discarded the WHOLE rule — and in the
## measured case that rule was the player's actual request. Live llama3, 12 real
## fighter compositions through the shipped chain: 2 lost the attack rule this way and
## reached the player as a one-rule script.
##
## Deliberately narrow, because a condition is a gate and dropping one makes a rule
## fire MORE often:
##   • the type must be a live TARGET_TYPES key, read from the system, never a copy;
##   • an action in that same rule must already name that exact target, which is the
##     evidence the condition is a restatement rather than a lost intent;
##   • a non-`always` condition must survive, so a gated rule can never become a
##     catch-all. If nothing would survive, the rule is left alone to be dropped.
func _drop_target_shaped_conditions(rules: Array, domain_system) -> Array[String]:
	var notes: Array[String] = []
	if domain_system == null or not ("TARGET_TYPES" in domain_system):
		return notes
	var targets: Dictionary = domain_system.TARGET_TYPES
	for rule in rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		var conditions: Array = rule.get("conditions", [])
		var aimed: Dictionary = {}
		for a in rule.get("actions", []):
			if typeof(a) == TYPE_DICTIONARY and a.has("target"):
				aimed[str(a["target"])] = true
		var keep: Array = []
		var removed: Array[String] = []
		for c in conditions:
			if typeof(c) != TYPE_DICTIONARY:
				keep.append(c)
				continue
			var ctype: String = str(c.get("type", ""))
			if targets.has(ctype) and aimed.has(ctype):
				removed.append(ctype)
			else:
				keep.append(c)
		if removed.is_empty():
			continue
		var substantive: bool = false
		for c in keep:
			if typeof(c) == TYPE_DICTIONARY and str((c as Dictionary).get("type", "")) != "always":
				substantive = true
				break
		if not substantive:
			continue
		rule["conditions"] = keep
		for t in removed:
			notes.append("Dropped '%s' from a rule's conditions — it is a target, and the rule already aims there." % t)
	return notes


func _drop_null_targets(rules: Array) -> int:
	var dropped: int = 0
	for rule in rules:
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		for a in rule.get("actions", []):
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if a.has("target") and a["target"] == null:
				a.erase("target")
				dropped += 1
	return dropped
