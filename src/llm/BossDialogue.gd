extends Node

## BossDialogue — autoload singleton for boss dialogue, intent biasing, and
## jailbreak vulnerability detection. Loads data/boss_dialogue.json on _ready.
##
## Public API:
##   has_entry(boss_id) -> bool
##   get_verbs(boss_id) -> Array[Dictionary]
##   get_opening_lines(boss_id) -> Array[String]
##   get_phase_transition_line(boss_id, phase) -> String
##   get_victory_line(boss_id) -> String   (boss reaction when the PARTY wins)
##   get_defeat_line(boss_id) -> String    (boss gloat when it WIPES the party)
##   pick_intent(boss_id, phase, game_state, llm_available) -> Dictionary
##       returns { intent_id, taunt_line }
##   check_jailbreak(boss_id, directive_text) -> Variant
##       returns null OR { vulnerability_id, consequence }
##
## STORY-FLAG SAFETY: consequence.type must be in CONSEQUENCE_ALLOWLIST.
## Any value outside the allowlist returns null from check_jailbreak — the
## LLM is never the rules engine; only authored deterministic vulnerabilities
## can land. Stakes guardrail: no consequence sets canonical story flags.
##
## Scripted floor: ALL pick_intent / check_jailbreak paths work without
## LLMService present. Keyword matching is deterministic; intent selection
## falls back to weighted-random over scripted intents.

## Allowlist of consequence types — anything outside this set is rejected.
const CONSEQUENCE_ALLOWLIST: Array[String] = [
	"skip_turn",
	"lose_buff_or_stagger",
	"enrage_briefly",
	"taunt_softens",
	"none",
]

## Data path. Loaded once on _ready, cached for the lifetime of the process.
const DATA_PATH: String = "res://data/boss_dialogue.json"

## Signal emitted when a player directive trips a vulnerability. BattleManager
## listens for this and applies the consequence to the boss combatant.
signal jailbreak_succeeded(boss_id: String, vulnerability_id: String, consequence: Dictionary)

# ── Internal state ────────────────────────────────────────────────────────────

var _data: Dictionary = {}
var _loaded: bool = false


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_data()


func _load_data() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("[BossDialogue] data file missing: %s" % DATA_PATH)
		return
	var f = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("[BossDialogue] could not open data file")
		return
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[BossDialogue] data root is not a Dictionary")
		return
	_data = parsed


# ── Public API ────────────────────────────────────────────────────────────────

func has_entry(boss_id: String) -> bool:
	"""True iff data/boss_dialogue.json declares a section for this boss."""
	if not _loaded:
		_load_data()
	return _data.has(boss_id)


func get_verbs(boss_id: String) -> Array:
	"""Returns the verbs list for the boss menu, or empty array."""
	if not has_entry(boss_id):
		return []
	var entry: Dictionary = _data[boss_id]
	var v = entry.get("verbs", [])
	if v is Array:
		return v
	return []


func get_opening_lines(boss_id: String) -> Array:
	if not has_entry(boss_id):
		return []
	var entry: Dictionary = _data[boss_id]
	var lines = entry.get("opening_lines", [])
	if lines is Array:
		return lines
	return []


func get_display_name(boss_id: String) -> String:
	"""Returns the boss section's display_name, or "" if absent. Flavour only —
	used to humanise LLM prompts; never gates a deterministic fallback."""
	if not has_entry(boss_id):
		return ""
	var entry: Dictionary = _data[boss_id]
	return str(entry.get("display_name", ""))


func get_phase_transition_line(boss_id: String, phase: int) -> String:
	"""Returns a random transition line for the given phase, or empty string."""
	if not has_entry(boss_id):
		return ""
	var entry: Dictionary = _data[boss_id]
	var phase_map: Dictionary = entry.get("phase_transition_lines", {})
	var key = "phase_%d" % phase
	if not phase_map.has(key):
		return ""
	var lines = phase_map[key]
	if lines is Array and lines.size() > 0:
		return str(lines[randi() % lines.size()])
	return ""


## get_victory_line — scripted-pool fallback for the boss's reaction WHEN THE
## PARTY DEFEATS IT (the party wins; the boss gloats/concedes in defeat).
## Returns a random pick from the boss section's "victory_lines" pool, or empty
## string if the section/pool is absent. This is the deterministic floor the
## LLM-narrated gloat falls back to. Graceful: never crashes on missing data.
func get_victory_line(boss_id: String) -> String:
	return _random_pool_line(boss_id, "victory_lines")


## get_defeat_line — scripted-pool fallback for what the boss says WHEN IT WIPES
## THE PARTY (the boss wins). Returns a random pick from the boss section's
## "defeat_lines" pool, or empty string if the section/pool is absent.
func get_defeat_line(boss_id: String) -> String:
	return _random_pool_line(boss_id, "defeat_lines")


## Shared helper for the optional victory_lines / defeat_lines pools. Returns a
## random non-empty string from the named pool, or "" when the boss has no
## section, the pool key is absent, the value is not an Array, or the Array is
## empty. The graceful empty-string contract lets call sites treat "no scripted
## line authored yet" identically to "no LLM available" — both degrade silently.
func _random_pool_line(boss_id: String, pool_key: String) -> String:
	if not has_entry(boss_id):
		return ""
	var entry: Dictionary = _data[boss_id]
	var lines = entry.get(pool_key, [])
	if lines is Array and lines.size() > 0:
		return str(lines[randi() % lines.size()])
	return ""


## pick_intent — DETERMINISTIC SCRIPTED PATH always available.
##
## Returns { intent_id, taunt_line } where intent_id is one of the entry's
## scripted_intents IDs and taunt_line is a short line (LLM-narrated when
## available + valid, otherwise a randomly-chosen scripted taunt).
##
## Args:
##   boss_id        — string key into data/boss_dialogue.json
##   phase          — int 1..3 (battle phase from combatant.get_meta('masterite_battle_phase'))
##   _game_state    — optional snapshot; currently unused but reserved for
##                    future intent-conditioning on autobattle frequency etc.
##   _llm_available — bool; when true, an LLM call could re-narrate the taunt.
##                    The current synchronous implementation ALWAYS uses the
##                    scripted floor so this is a no-op flag for now; the
##                    hook is intentional so a later wave can swap in an
##                    awaitable taunt voicer without changing call sites.
##
## Fallback safety: if boss_id has no entry, returns {intent_id="", taunt_line=""}
func pick_intent(boss_id: String, phase: int, _game_state: Variant = null, _llm_available: bool = false) -> Dictionary:
	if not has_entry(boss_id):
		return {"intent_id": "", "taunt_line": ""}
	var entry: Dictionary = _data[boss_id]
	var intents = entry.get("scripted_intents", [])
	if not (intents is Array) or intents.size() == 0:
		return {"intent_id": "", "taunt_line": ""}

	# Filter by phase eligibility (min_phase condition)
	var eligible: Array = []
	for it in intents:
		if not (it is Dictionary):
			continue
		var cond: Dictionary = it.get("conditions", {})
		var min_phase: int = int(cond.get("min_phase", 1))
		if phase >= min_phase:
			eligible.append(it)
	if eligible.is_empty():
		eligible = [intents[0]]

	# Weighted-random selection over the eligible set.
	var total_weight: float = 0.0
	for it in eligible:
		total_weight += float(it.get("conditions", {}).get("weight", 1.0))
	var roll: float = randf() * max(total_weight, 0.0001)
	var picked: Dictionary = eligible[0]
	var acc: float = 0.0
	for it in eligible:
		acc += float(it.get("conditions", {}).get("weight", 1.0))
		if roll <= acc:
			picked = it
			break

	var taunts = picked.get("taunt_lines", [])
	var taunt_line: String = ""
	if taunts is Array and taunts.size() > 0:
		taunt_line = str(taunts[randi() % taunts.size()])

	return {
		"intent_id": str(picked.get("id", "")),
		"taunt_line": taunt_line,
	}


## check_jailbreak — substring-match player directive_text against each
## vulnerability's trigger_keywords (case-insensitive). First match wins.
##
## Returns null if no match OR if the matched consequence.type is outside
## CONSEQUENCE_ALLOWLIST (defensive — protects against bad data slipping
## a story-flag write into combat).
##
## Returns { vulnerability_id, consequence } on match.
func check_jailbreak(boss_id: String, directive_text: String) -> Variant:
	if not has_entry(boss_id):
		return null
	if directive_text == null or directive_text.is_empty():
		return null
	var lower: String = directive_text.to_lower()
	var entry: Dictionary = _data[boss_id]
	var vulns = entry.get("jailbreak_vulnerabilities", [])
	if not (vulns is Array):
		return null

	for v in vulns:
		if not (v is Dictionary):
			continue
		var keywords = v.get("trigger_keywords", [])
		if not (keywords is Array):
			continue
		var hit: bool = false
		for kw in keywords:
			var kw_s: String = str(kw).to_lower().strip_edges()
			if kw_s.is_empty():
				continue
			if lower.find(kw_s) != -1:
				hit = true
				break
		if not hit:
			continue
		# Allowlist enforcement: NO consequence outside the safe set.
		var consequence: Dictionary = v.get("consequence", {})
		var ctype: String = str(consequence.get("type", ""))
		if not CONSEQUENCE_ALLOWLIST.has(ctype):
			push_warning("[BossDialogue] vulnerability '%s' has unsupported consequence type '%s' — rejected." % [v.get("id", "?"), ctype])
			return null
		return {
			"vulnerability_id": str(v.get("id", "")),
			"consequence": consequence,
		}
	return null


## try_apply_jailbreak — convenience wrapper: check_jailbreak + emit signal.
## Returns true if a vulnerability landed (signal fired).
func try_apply_jailbreak(boss_id: String, directive_text: String) -> bool:
	var result = check_jailbreak(boss_id, directive_text)
	if result == null:
		return false
	var vuln_id: String = result.get("vulnerability_id", "")
	var consequence: Dictionary = result.get("consequence", {})
	jailbreak_succeeded.emit(boss_id, vuln_id, consequence)
	return true
