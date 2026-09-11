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

	if domain == DOMAIN_AUTOBATTLE and bool(kit_context.get("resolved", false)):
		for note in _supply_missing_mp_guards(v["rules"], kit_context):
			repair_notes.append(note)

	var domain_system = get_node_or_null("/root/AutobattleSystem" if domain == DOMAIN_AUTOBATTLE else "/root/AutogrindSystem")

	# ONE bad rule discarded the player's WHOLE ruleset. Measured on live llama3 after
	# the prompt fix: 4 of 10 fighter compositions still fell back, 3 of them for a
	# single rule naming an ability the character does not have (esuna, raise) while
	# the other three rules in the set were valid. The player asked for a strategy and
	# got a canned fallback because one line of four was wrong.
	# Same shape as _drop_null_targets above: drop the offending rule, keep the rest,
	# and TELL the player. Never empties the set — a zero-rule composition is not a
	# valid one, it is the save-wiping one, so the caller's refusal path still runs.
	if domain == DOMAIN_AUTOBATTLE and character_id != "":
		for note in _drop_unusable_rules(v["rules"], character_id, domain_system):
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
		var errs: Array = domain_system.validate_rule(r, character_id)
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
