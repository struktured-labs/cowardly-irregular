extends GutTest

## tick 296: JobSystem._create_default_abilities now includes the
## 4 rogue + 4 bard abilities that the default jobs reference.
##
## Pre-fix _create_default_jobs (tick 295) listed:
##   rogue.abilities = [sneak_attack, steal, smoke_bomb, vanish]
##   bard.abilities  = [battle_hymn, lullaby, discord, inspiring_melody]
##
## But _create_default_abilities (the parallel fallback) only had
## fighter/cleric/mage/scriptweaver moves. So when both data/jobs
## .json AND data/abilities.json were broken, rogue and bard PCs
## would have ability ids pointing at nothing. Cascading silent
## degradation: assign_job succeeded, but every ability invocation
## downstream surfaced "ability not found" push_warnings.
##
## Now both fallback paths are coherent.

const JOB_SYSTEM := "res://src/jobs/JobSystem.gd"

const ROGUE_ABILITIES: Array[String] = [
	"sneak_attack", "steal", "smoke_bomb", "vanish",
]
const BARD_ABILITIES: Array[String] = [
	"battle_hymn", "lullaby", "discord", "inspiring_melody",
]


# ── Source pin: each rogue/bard ability has a default entry ───────

func test_rogue_abilities_in_defaults() -> void:
	var src: String = FileAccess.get_file_as_string(JOB_SYSTEM)
	var fn_idx: int = src.find("func _create_default_abilities")
	assert_gt(fn_idx, -1, "_create_default_abilities must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var missing: Array[String] = []
	for aid in ROGUE_ABILITIES:
		if not body.contains("\"id\": \"%s\"" % aid):
			missing.append(aid)
	assert_eq(missing.size(), 0,
		"_create_default_abilities must include every rogue ability: %s" % str(missing))


func test_bard_abilities_in_defaults() -> void:
	var src: String = FileAccess.get_file_as_string(JOB_SYSTEM)
	var fn_idx: int = src.find("func _create_default_abilities")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var missing: Array[String] = []
	for aid in BARD_ABILITIES:
		if not body.contains("\"id\": \"%s\"" % aid):
			missing.append(aid)
	assert_eq(missing.size(), 0,
		"_create_default_abilities must include every bard ability: %s" % str(missing))


# ── Behavioral: defaults path produces both ability sets ─────────

func test_defaults_actually_load_rogue_and_bard_abilities() -> void:
	var script: GDScript = load(JOB_SYSTEM)
	var inst: Object = script.new()
	add_child_autofree(inst)
	inst._create_default_abilities()
	for aid in ROGUE_ABILITIES + BARD_ABILITIES:
		assert_true(inst.abilities.has(aid),
			"after _create_default_abilities runs, abilities['%s'] must be present" % aid)


# ── Each new ability has required fields ─────────────────────────

func test_each_new_ability_has_required_fields() -> void:
	var script: GDScript = load(JOB_SYSTEM)
	var inst: Object = script.new()
	add_child_autofree(inst)
	inst._create_default_abilities()
	const REQUIRED := ["id", "name", "type", "mp_cost", "description", "target_type"]
	var partial: Array[String] = []
	for aid in ROGUE_ABILITIES + BARD_ABILITIES:
		var entry: Dictionary = inst.abilities.get(aid, {})
		for k in REQUIRED:
			if not entry.has(k):
				partial.append("%s missing %s" % [aid, k])
	assert_eq(partial.size(), 0,
		"each new ability must have id/name/type/mp_cost/description/target_type: %s" % str(partial))


# ── Cross-pin: tick 295 rogue job default still landed ───────────

func test_tick_295_rogue_job_default_preserved() -> void:
	var src: String = FileAccess.get_file_as_string(JOB_SYSTEM)
	assert_true(src.contains("\"id\": \"rogue\""),
		"tick 295 rogue job entry must still be in _create_default_jobs (precondition for this fix)")


# ── Cross-pin: rogue/bard ability arrays in _create_default_jobs ─

func test_rogue_bard_ability_arrays_in_default_jobs() -> void:
	# If someone removes rogue's `abilities` list from the job default,
	# the abilities I added become orphans. Catch that.
	var script: GDScript = load(JOB_SYSTEM)
	var inst: Object = script.new()
	add_child_autofree(inst)
	inst._create_default_jobs()
	var rogue: Dictionary = inst.jobs.get("rogue", {})
	var rogue_abilities: Array = rogue.get("abilities", [])
	for aid in ROGUE_ABILITIES:
		assert_true(aid in rogue_abilities,
			"rogue job entry must list '%s' in abilities (else defaults pair is broken)" % aid)
	var bard: Dictionary = inst.jobs.get("bard", {})
	var bard_abilities: Array = bard.get("abilities", [])
	for aid in BARD_ABILITIES:
		assert_true(aid in bard_abilities,
			"bard job entry must list '%s' in abilities" % aid)
