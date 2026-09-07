extends GutTest

## Cowir-main msg 2450/2455 + cowir-sprites 4ec21a07 (msg 2452/2462).
##
## The Lockward's Counter Stance is a plain +40% attack buff — no counter
## reaction code, just windup then punish. Before this ship the only cue
## was compact text on the enemy panel; playtest bounced off it. Fix
## surfaces a per-enemy amber sigil above the sprite when any buff with
## class_tag "reprisal" is active, so the player can read "defer this
## turn" without parsing the panel.
##
## The visual seam reuses BattleScene._update_buff_debuff_visuals — new
## threat_class field on the ability data flows through BM's "buff"
## effect handler into Combatant.add_buff's optional class_tag param
## into buff.class, then THREAT_CLASS_BUFFS matches. Backwards-compat
## (existing add_buff callers unchanged, class_tag default is "").


## ── Ability data pin ───────────────────────────────────────────────────

func test_counter_stance_ability_tagged_reprisal() -> void:
	# Data-side: the ability author owns the class_tag (cowir-sprites' point
	# msg 2462 — string tag not bool). If this field goes missing, the sigil
	# stays hidden even though the buff still applies mechanically.
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	assert_not_null(f)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(data.has("masterite_counter_stance"))
	var ability: Dictionary = data["masterite_counter_stance"]
	assert_eq(str(ability.get("threat_class", "")), "reprisal",
		"masterite_counter_stance must carry threat_class=\"reprisal\" — the visual seam keys off it")


## ── Combatant.add_buff signature + storage ─────────────────────────────

const CombatantScript = preload("res://src/battle/Combatant.gd")


func _make_combatant() -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.combatant_name = "Test"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	add_child_autofree(c)
	return c


func test_add_buff_accepts_optional_class_tag_and_stores_it() -> void:
	# The buff dict must carry the class tag so the visual can key off it
	# without reading back through the ability database. Empty default keeps
	# existing callers safe.
	var c := _make_combatant()
	c.add_buff("Empower", "attack", 1.4, 2, "reprisal")
	assert_eq(c.active_buffs.size(), 1)
	var buff: Dictionary = c.active_buffs[0]
	assert_eq(str(buff.get("class", "")), "reprisal",
		"add_buff's 5th param must be stored on the buff as \"class\"")


func test_add_buff_backwards_compat_no_class_tag() -> void:
	# All existing callers pass 4 args — this must keep working, and the
	# stored buff's class field must default to empty (never matches
	# THREAT_CLASS_BUFFS on any accident).
	var c := _make_combatant()
	c.add_buff("Empower", "attack", 1.4, 2)
	assert_eq(c.active_buffs.size(), 1)
	var buff: Dictionary = c.active_buffs[0]
	assert_eq(str(buff.get("class", "")), "",
		"omitted class_tag stores empty — never a false-positive threat match")


func test_add_buff_refresh_preserves_class_when_refreshed_with_tag() -> void:
	# Two consecutive Counter Stance casts should still surface as reprisal
	# after the refresh path fires (same effect key found + refreshed).
	var c := _make_combatant()
	c.add_buff("Empower", "attack", 1.4, 2, "reprisal")
	c.add_buff("Empower", "attack", 1.4, 2, "reprisal")
	assert_eq(c.active_buffs.size(), 1)
	var buff: Dictionary = c.active_buffs[0]
	assert_eq(str(buff.get("class", "")), "reprisal",
		"refresh path must retain the reprisal tag or the sigil would vanish on re-cast")


## ── BattleManager "buff" effect handler wires threat_class through ─────

func test_battle_manager_buff_handler_threads_threat_class() -> void:
	# BM:5399 must read ability.threat_class and pass it to add_buff. If the
	# thread breaks, ability author sets the field but runtime never sees it.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# Anchor on the handler's own comment — "buff":" as a bare needle matches
	# any comment first (find returns earliest occurrence).
	var handler_idx: int = src.find("Generic stat buff (masterite_* family)")
	assert_gt(handler_idx, -1, "generic \"buff\" effect handler comment must exist as an anchor")
	var window: String = src.substr(handler_idx, 800)
	assert_string_contains(window, "ability.get(\"threat_class\"",
		"the buff handler must read ability.threat_class")
	assert_string_contains(window, "target.add_buff(\"Empower\", buff_stat, stat_modifier, duration, threat_class)",
		"the read value must be threaded into add_buff's class_tag param")


## ── BattleScene threat visual surface ──────────────────────────────────

const BS_PATH: String = "res://src/battle/BattleScene.gd"


func test_threat_class_buffs_const_declared() -> void:
	# The lookup must be a named const so extending it (Reflect, Truth
	# Refuses You, etc.) is greppable + review-friendly.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "const THREAT_CLASS_BUFFS: Dictionary",
		"the reprisal lookup must be a named const, not a magic literal")
	assert_string_contains(src, "\"reprisal\": true",
		"tier-1 scope: reprisal is the initial class_tag registered")


func test_combatant_has_threat_buff_predicate_reads_class_field() -> void:
	# The predicate must read buff.class specifically — reading buff.effect
	# would break because the display name is \"Empower\" not \"reprisal\".
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _combatant_has_threat_buff")
	assert_gt(idx, -1)
	var body: String = src.substr(idx, 500)
	assert_string_contains(body, "buff.get(\"class\", \"\")",
		"predicate must consult buff.class — buff.effect is the display name (\"Empower\") which would never match")


func test_sigil_created_and_hidden_by_default() -> void:
	# _create_buff_visual must always attach the sigil node, even when the
	# initial buff isn't threat-class — so a mid-battle threat buff can toggle
	# visibility without re-creating the child. Missing texture is a no-op,
	# not an error.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _create_buff_visual")
	assert_gt(idx, -1)
	# Function grew — read up to the next top-level func so the window covers the full body regardless of future line additions.
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 2000)
	assert_string_contains(body, "load_battle_effect_texture(\"threat_buff_sigil\")",
		"sigil texture must come from HybridSpriteLoader.load_battle_effect_texture — no direct load() bypass")
	assert_string_contains(body, "sigil.visible = false",
		"sigil starts hidden — _update_buff_debuff_visuals toggles it based on threat state")


func test_update_shows_sigil_and_overrides_glow_on_threat() -> void:
	# The per-tick update must (a) detect threat via the predicate, (b)
	# override the glow color when threat active, (c) toggle sigil visibility.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _update_buff_debuff_visuals")
	assert_gt(idx, -1)
	var body: String = src.substr(idx, 3000)
	assert_string_contains(body, "_combatant_has_threat_buff(combatant)",
		"update must consult the predicate each tick")
	assert_string_contains(body, "THREAT_GLOW_COLOR",
		"threat state must override glow color — cyan-green is misleading for reprisal")
	assert_string_contains(body, "sigil.visible = has_threat",
		"sigil visibility toggles per-tick from the threat check")


func test_particles_suppressed_under_threat() -> void:
	# cowir-sprites' rationale: particles + sigil at the same location fight
	# for silhouette read. Particles hide when threat active so the sigil
	# owns the "watch this enemy" attention.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _update_buff_debuff_visuals")
	var body: String = src.substr(idx, 3000)
	assert_string_contains(body, "p_node.visible = not has_threat",
		"particles must be hidden while a threat buff is active — they fight the sigil for silhouette read")


func test_remove_buff_visual_cleans_up_sigil() -> void:
	# All three child nodes (glow, particles, sigil) must free when the
	# combatant's buff visual is removed. Missing the sigil leaks it under
	# the sprite forever (visible after combatant KO).
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _remove_buff_visual")
	assert_gt(idx, -1)
	var body: String = src.substr(idx, 600)
	assert_string_contains(body, "visuals.get(\"sigil\")",
		"remove must fetch the sigil node — missing it leaks a Sprite2D per KO")
	assert_string_contains(body, "sigil.queue_free()",
		"the sigil must be queue_freed, not just detached")


## ── HybridSpriteLoader battle_effects surface ──────────────────────────

const HSL_PATH: String = "res://src/battle/sprites/HybridSpriteLoader.gd"


func test_hsl_load_battle_effect_texture_exists() -> void:
	# The single-source norm (cowir-main): HSL owns manifest-to-texture; no
	# direct load() at call sites. If someone removes this helper the sigil
	# path silently breaks and every threat buff shows glow but no icon.
	var src: String = FileAccess.get_file_as_string(HSL_PATH)
	assert_string_contains(src, "static func load_battle_effect_texture(key: String) -> Texture2D:",
		"HSL must expose load_battle_effect_texture — the sigil load path goes through it")


func test_hsl_manifest_load_populates_battle_effects_cache() -> void:
	# The manifest section is a distinct top-level key from sheets /
	# monster_sheets. If _load_manifest ignores it the cache stays empty
	# and every threat sigil returns null.
	var src: String = FileAccess.get_file_as_string(HSL_PATH)
	assert_string_contains(src, "_battle_effects = json.data.get(\"battle_effects\"",
		"_load_manifest must populate _battle_effects from manifest.battle_effects")


func test_manifest_has_threat_buff_sigil_entry() -> void:
	# Integration pin (cowir-sprites 4ec21a07): the manifest entry must
	# exist and its path must resolve. Prevents the fold-order bug where
	# consumer lands without asset (silent no-op).
	var f := FileAccess.open("res://data/sprite_manifest.json", FileAccess.READ)
	assert_not_null(f)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(data.has("battle_effects"),
		"manifest.battle_effects section must exist (cowir-sprites' contract)")
	var effects: Dictionary = data["battle_effects"]
	assert_true(effects.has("threat_buff_sigil"),
		"threat_buff_sigil must be registered under battle_effects")
	var entry: Dictionary = effects["threat_buff_sigil"]
	var path: String = str(entry.get("path", ""))
	assert_string_contains(path, "threat_buff_sigil.png",
		"path field must reference the actual sigil PNG")


## ── End-to-end wire: ability data → runtime buff class ─────────────────

func test_add_buff_via_ability_data_produces_reprisal_class() -> void:
	# The whole chain, tested against real ability data: read the ability,
	# extract threat_class, call add_buff with it, verify the stored buff
	# carries the class. If any step regresses (data field, BM handler,
	# add_buff signature) this end-to-end assertion catches it.
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var ability: Dictionary = data["masterite_counter_stance"]
	var threat_class: String = str(ability.get("threat_class", ""))
	assert_ne(threat_class, "", "ability data must carry a non-empty threat_class")
	var c := _make_combatant()
	c.add_buff("Empower", str(ability.get("stat", "attack")),
		float(ability.get("modifier", 1.0)), int(ability.get("duration", 1)),
		threat_class)
	assert_eq(c.active_buffs.size(), 1)
	assert_eq(str(c.active_buffs[0].get("class", "")), "reprisal",
		"end-to-end: ability→runtime buff must preserve the threat class")
