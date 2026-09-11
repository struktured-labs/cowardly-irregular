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

	var result := {
		"name": v["name"],
		"description": v["description"],
		"rules": v["rules"],
		"errors": [] as Array[String],
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
	if domain == DOMAIN_AUTOBATTLE and bool(kit_context.get("resolved", false)):
		_supply_missing_mp_guards(v["rules"], kit_context)

	var domain_system = get_node_or_null("/root/AutobattleSystem" if domain == DOMAIN_AUTOBATTLE else "/root/AutogrindSystem")
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
func _supply_missing_mp_guards(rules: Array, kit_context: Dictionary) -> void:
	var costs: Dictionary = kit_context.get("costs", {})
	var kit: Array = kit_context.get("kit", [])
	var max_mp: int = int(kit_context.get("max_mp", 0))
	if max_mp <= 0:
		return
	for rule in rules:
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
		for c in conditions:
			if typeof(c) != TYPE_DICTIONARY:
				continue
			if str(c.get("type", "")) == "mp_percent" and str(c.get("op", "")) == ">=":
				if int(c.get("value", 0)) < need:
					c["value"] = need
				raised = true
		if not raised:
			conditions.append({"type": "mp_percent", "op": ">=", "value": need})
			rule["conditions"] = conditions
