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

## Placeholder — implemented in Task 10.
func compose_async(domain: String, prompt_text: String, character_id: String = "", current_rules: Array = []) -> Dictionary:
	return _empty_result(domain, character_id, "not_implemented")

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
