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

	var prompt: String = DialoguePromptsScript.build_rule_composition(domain, prompt_text, current_rules)
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

	var domain_system = get_node_or_null("/root/AutobattleSystem" if domain == DOMAIN_AUTOBATTLE else "/root/AutogrindSystem")
	var grammar_errors: Array[String] = []
	if domain_system != null and domain_system.has_method("validate_rule"):
		for r in v["rules"]:
			for err in domain_system.validate_rule(r):
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
