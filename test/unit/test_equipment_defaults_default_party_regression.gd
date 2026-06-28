extends GutTest

## tick 321: EquipmentSystem._create_default_equipment now includes
## every equipment_id referenced by GameLoop._create_party.
##
## Pre-fix the default party setup (lines 1885-1999 of GameLoop) called
## EquipmentSystem.equip_weapon / equip_armor / equip_accessory with 13
## different IDs across hero / mira / rogue / vex / bard. Of those, 6
## were MISSING from EquipmentSystem._create_default_equipment:
##
##   weapons:  oak_staff (mira), iron_dagger (rogue), shadow_rod (vex)
##   armors:   cloth_robe (mira+bard), thief_garb (rogue), dark_robe (vex)
##
## If equipment.json failed to load (push_warning paths in
## EquipmentSystem at lines 31/40/58/61), every one of those equip_*
## calls fired its "equipment_id not found" warning and left the slot
## empty. New game with equipment.json failure → mira/rogue/vex
## unarmed AND unarmored; bard unarmored (piano_scythe fixed in tick
## 320). 4-of-5 party members crippled out the gate.
##
## Same cross-file silent-fallback gap class as tick 318 (max_mp),
## tick 319 (encore), and tick 320 (piano_scythe). Test pins the
## cross-file invariant — every equip_weapon / equip_armor /
## equip_accessory ID in GameLoop._create_party must exist in
## EquipmentSystem defaults.

const EQUIP_SYSTEM_PATH := "res://src/jobs/EquipmentSystem.gd"
const GAME_LOOP_PATH := "res://src/GameLoop.gd"

# IDs we just added (must exist in defaults after this tick).
const REQUIRED_IDS := [
	"oak_staff", "iron_dagger", "shadow_rod",      # weapons
	"cloth_robe", "thief_garb", "dark_robe",       # armors
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: every newly-added ID is in defaults ─────────────────

func test_added_equipment_ids_in_defaults() -> void:
	var src := _read(EQUIP_SYSTEM_PATH)
	var fn_idx: int = src.find("func _create_default_equipment")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	for eid in REQUIRED_IDS:
		var marker: String = "\"%s\":" % eid
		assert_true(body.contains(marker),
			"Default equipment must include '%s' — referenced by GameLoop._create_party" % eid)


# ── Cross-file invariant: every GameLoop._create_party ref exists ───

func test_every_create_party_equip_ref_in_defaults() -> void:
	var equip_src := _read(EQUIP_SYSTEM_PATH)
	var gl_src := _read(GAME_LOOP_PATH)

	# Slice EquipmentSystem._create_default_equipment.
	var efn_idx: int = equip_src.find("func _create_default_equipment")
	var enext_fn: int = equip_src.find("\nfunc ", efn_idx + 1)
	var equip_body: String = equip_src.substr(efn_idx, enext_fn - efn_idx) if enext_fn > 0 else equip_src.substr(efn_idx)

	# Slice GameLoop._create_party — must use the parenthesized form
	# `func _create_party()` because `_create_party_from_customizations`
	# is earlier in the file and `func _create_party` matches it first.
	var gfn_idx: int = gl_src.find("func _create_party()")
	var gnext_fn: int = gl_src.find("\nfunc ", gfn_idx + 1)
	var gl_body: String = gl_src.substr(gfn_idx, gnext_fn - gfn_idx) if gnext_fn > 0 else gl_src.substr(gfn_idx)

	# Extract every EquipmentSystem.equip_*(member, "<id>") call.
	var rx := RegEx.new()
	rx.compile("EquipmentSystem\\.equip_[a-z]+\\([a-z]+, \"([a-z_]+)\"\\)")
	var matches: Array = rx.search_all(gl_body)
	var refs: Array[String] = []
	for m in matches:
		refs.append(m.get_string(1))
	assert_gt(refs.size(), 0, "regex must find equip_* calls inside _create_party")

	# Verify each ref exists as a key in equip_body.
	var missing: Array[String] = []
	for ref in refs:
		var marker: String = "\"%s\":" % ref
		if not equip_body.contains(marker):
			missing.append(ref)
	assert_eq(missing.size(), 0,
		"Every EquipmentSystem.equip_* ref in _create_party must exist in EquipmentSystem defaults. Missing: %s" % str(missing))


# ── Behavioral: stats match data/equipment.json (regression guard) ──

func test_oak_staff_stats_match_canonical() -> void:
	var src := _read(EQUIP_SYSTEM_PATH)
	var fn_idx: int = src.find("func _create_default_equipment")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# oak_staff: magic 12 / attack 3 / max_mp 10
	var os_idx: int = body.find("\"oak_staff\":")
	var os_body: String = body.substr(os_idx, 400)
	assert_true(os_body.contains("\"magic\": 12"),
		"oak_staff must have magic=12")
	assert_true(os_body.contains("\"attack\": 3"),
		"oak_staff must have attack=3")
	assert_true(os_body.contains("\"max_mp\": 10"),
		"oak_staff must have max_mp=10")


# ── Behavioral: at runtime, autoload sees every required id ─────────

func test_real_autoload_has_all_required_ids() -> void:
	assert_not_null(EquipmentSystem, "EquipmentSystem autoload required")
	if EquipmentSystem == null:
		return
	for eid in REQUIRED_IDS:
		# weapons vs armors check — search both maps.
		var present: bool = EquipmentSystem.weapons.has(eid) or EquipmentSystem.armors.has(eid)
		assert_true(present,
			"EquipmentSystem.weapons or .armors must include '%s' (whether via json or defaults — both must agree)" % eid)
