extends GutTest

## The generic weapon-hit fallback IS the sword hit, deliberately — and until now that contract
## lived only inside a prompt STRING (2026-09-09).
##
##   attack_hit.prompt   "Generic crispy weapon hit fallback (= attack_hit_sword). Used when no
##                        weapon_type is provided."
##   critical_hit.prompt "Generic crit fallback (= attack_hit_sword_crit)."
##
## Both pairs are byte-identical today. Nothing enforced it. Regenerate either side — an
## elevenlabs_sfx.py run, an ffmpeg re-derive, an artist replacement — and the pair silently
## diverges: the prompt keeps ASSERTING the equality while the assets stop honouring it, and a
## weapon with no weapon_type starts sounding like something other than a sword.
##
## 🔑 SHAPE (cowir-sprites, 2026-09-09): an exception justified by a HUMAN JUDGEMENT cannot expire
## on its own, because the judgement is not re-computable. Pin the ARTIFACT'S IDENTITY instead of
## restating the judgement — then a change to the thing that was judged forces the judgement to be
## made again. This asserts CONTENT IDENTITY, not similarity: no threshold, nothing to tune.
##
## ⛔ If you are here because this went red: do NOT re-point the files at each other to get green.
## Decide whether the generic fallback should still be the sword. If yes, make them identical again;
## if no, rewrite both prompts and DELETE this guard — it is the record of a decision, not a rule.

const MANIFEST := "res://data/sfx_manifest.json"

## base -> the key its prompt claims it equals.
const DELIBERATE_ALIASES: Dictionary = {
	"attack_hit": "attack_hit_sword",
	"critical_hit": "attack_hit_sword_crit",
}


func _sfx() -> Dictionary:
	var raw := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(raw, "", "manifest unreadable — every assert below would pass vacuously")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest did not parse as a Dictionary")
	return (parsed as Dictionary).get("sfx", {})


func test_both_sides_of_every_alias_exist() -> void:
	## PREMISE: a missing key makes the identity check below vacuous rather than false.
	var sfx := _sfx()
	assert_gt(sfx.size(), 50, "manifest holds %d entries — not the file we think" % sfx.size())
	for base in DELIBERATE_ALIASES:
		assert_true(sfx.has(base), "%s missing from the manifest" % base)
		assert_true(sfx.has(str(DELIBERATE_ALIASES[base])), "%s missing from the manifest" % DELIBERATE_ALIASES[base])


func test_the_prompt_still_claims_the_alias() -> void:
	## The prompt is the CONTRACT and the generator's input. If someone rewrites it without
	## changing the audio, the assets agree by accident and nothing records why.
	var sfx := _sfx()
	for base in DELIBERATE_ALIASES:
		var alias := str(DELIBERATE_ALIASES[base])
		var prompt := str((sfx.get(base, {}) as Dictionary).get("prompt", ""))
		assert_true(prompt.contains(alias),
			"%s's prompt no longer names %s — the alias contract is only written down there, so if the prompt drops it the identity below becomes an unexplained coincidence" % [base, alias])


func test_the_generic_fallback_is_byte_identical_to_the_sword() -> void:
	## CONTENT IDENTITY, not similarity — no threshold, nothing to tune.
	var sfx := _sfx()
	var checked := 0
	var diverged: Array[String] = []
	for base in DELIBERATE_ALIASES:
		var alias := str(DELIBERATE_ALIASES[base])
		if not (sfx.has(base) and sfx.has(alias)):
			continue
		var pa := "res://" + str((sfx[base] as Dictionary).get("file", ""))
		var pb := "res://" + str((sfx[alias] as Dictionary).get("file", ""))
		if not (FileAccess.file_exists(pa) and FileAccess.file_exists(pb)):
			diverged.append("%s or %s missing from disk" % [pa, pb])
			continue
		assert_gt(FileAccess.get_file_as_bytes(pa).size(), 0, "%s read as empty — the hash below would be of nothing" % base)
		checked += 1
		var ha := FileAccess.get_sha256(pa)
		var hb := FileAccess.get_sha256(pb)
		if ha != hb:
			diverged.append("%s (%s) != %s (%s)" % [base, ha.substr(0, 12), alias, hb.substr(0, 12)])
	assert_eq(checked, DELIBERATE_ALIASES.size(),
		"control: hashed %d of %d pairs — the loop skipped one and the assert below is weaker than it reads" % [checked, DELIBERATE_ALIASES.size()])
	if not diverged.is_empty():
		fail_test("a deliberate alias has diverged — the prompt still says the generic fallback IS the sword, and the audio no longer agrees: %s" % [diverged])
