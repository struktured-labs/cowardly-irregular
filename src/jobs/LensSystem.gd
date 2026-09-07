extends Node

## LensSystem — layer 3 of the character model (Primary locked / Secondary job / Lens).
##
## Design: docs/design/lens-system-and-evolutions-proposal.md (canonical, 2026-07-08)
##         docs/design/lens-system-addendum-2026-07-27.md (acquisition pipeline)
##
## struktured ruling 2026-07-27: **Lenses are POOLED.** "killing blow feels wrong, the lens
## should be equippable by anyone." So there is no binding, no killer attribution, and no
## re-bind cost — a crafted Lens sits in shared inventory and any party member can equip it.
##
## Pipeline: defeat a masterite of axis X -> recipe X unlocks -> gather materials -> craft -> equip.
##
## Deliberately NOT stored in passives.json. AbilitiesMenu.gd:116 stubs its learned check with
## `or true`, so every passive listed there is equippable by anyone with no gate — which would
## hand out Lenses for free. Lenses keep their own inventory and their own equip surface, and
## expose mods in PassiveSystem's exact vocabulary so battle code can compose the two.

signal recipe_unlocked(axis: String)
signal lens_crafted(axis: String)
signal lens_equipped(char_id: String, axis: String)
signal lens_unequipped(char_id: String, axis: String)

const LENS_DATA_PATH := "res://data/lenses.json"

## Mirrors PassiveSystem.get_passive_mods' identity dict so the two compose without translation.
const NEUTRAL_MODS := {
	"attack_multiplier": 1.0,
	"defense_multiplier": 1.0,
	"magic_multiplier": 1.0,
	"speed_multiplier": 1.0,
	"max_hp_multiplier": 1.0,
	"max_mp_multiplier": 1.0,
	"mp_cost_multiplier": 1.0,
	"healing_multiplier": 1.0,
	"crit_chance": 0.0,
	"evasion": 0.0,
}

var lenses: Dictionary = {}


func _ready() -> void:
	_load_lens_data()


func _load_lens_data() -> void:
	if not FileAccess.file_exists(LENS_DATA_PATH):
		push_warning("[LensSystem] %s not found — the Lens layer will be inert" % LENS_DATA_PATH)
		return
	var file := FileAccess.open(LENS_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("[LensSystem] %s exists but could not be opened — Lens layer inert" % LENS_DATA_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_warning("[LensSystem] %s did not parse to a Dictionary — Lens layer inert" % LENS_DATA_PATH)
		return
	var raw = parsed.get("lenses", {})
	if not (raw is Dictionary):
		push_warning("[LensSystem] lenses.json has no 'lenses' object — Lens layer inert")
		return
	lenses = raw
	print("[LensSystem] Loaded %d lenses" % lenses.size())


func get_lens(axis: String) -> Dictionary:
	var entry = lenses.get(axis, {})
	return entry if entry is Dictionary else {}


func all_axes() -> Array:
	var out: Array = []
	for k in lenses:
		out.append(str(k))
	out.sort()
	return out


# ── Acquisition ──────────────────────────────────────────────────────

## Called when a masterite of this axis is defeated. Idempotent — five masterites share an axis,
## and defeating the second must not re-announce or duplicate anything.
func unlock_recipe(axis: String) -> bool:
	if not lenses.has(axis):
		push_warning("[LensSystem] unlock_recipe: unknown axis '%s' — no such Lens" % axis)
		return false
	if GameState == null:
		return false
	if axis in GameState.unlocked_lens_recipes:
		return false
	GameState.unlocked_lens_recipes.append(axis)
	recipe_unlocked.emit(axis)
	print("[LensSystem] Recipe unlocked: %s" % axis)
	return true


func is_recipe_unlocked(axis: String) -> bool:
	return GameState != null and axis in GameState.unlocked_lens_recipes


## Retroactive unlock for masterites already dead when the Lens system arrived (cowir-main default
## 2026-07-27, reversible). Without it an existing save can never see the system — the recipe gate
## waits on a defeat that already happened and will not happen again. Called on load; idempotent.
func reconcile_retroactive_unlocks() -> int:
	if GameState == null:
		return 0
	var src := FileAccess.get_file_as_string("res://data/monsters.json")
	if src == "":
		return 0
	var parsed = JSON.parse_string(src)
	if not (parsed is Dictionary):
		return 0
	var monsters = parsed.get("monsters", parsed)
	if not (monsters is Dictionary):
		return 0
	var granted := 0
	for mid in monsters:
		var m = monsters[mid]
		if not (m is Dictionary) or not m.get("masterite", false):
			continue
		var axis := str(m.get("masterite_type", ""))
		if axis == "" or is_recipe_unlocked(axis):
			continue
		if BestiarySystem.is_defeated(str(mid)):
			if unlock_recipe(axis):
				granted += 1
	if granted > 0:
		print("[LensSystem] Retroactively unlocked %d recipe(s) from already-defeated masterites" % granted)
	return granted


## Materials required to craft, as {item_id: count}.
func get_recipe(axis: String) -> Dictionary:
	var lens := get_lens(axis)
	var r = lens.get("recipe", {})
	return r.duplicate() if r is Dictionary else {}


## The live party. Inventory is per-Combatant (Combatant.gd:102) with party[0] as the de-facto
## shared holder — drops (BattleManager:801) and shop purchases (ShopScene:595) both write there.
## We scan the WHOLE party anyway: party order changes with the leader, so materials can legitimately
## sit on any member, and assuming index 0 would report "not enough shards" while holding six.
func _party() -> Array:
	var gl := get_tree().root.get_node_or_null("GameLoop") if is_inside_tree() else null
	if gl == null or not ("party" in gl):
		return []
	return gl.party if gl.party is Array else []


func material_count(item_id: String) -> int:
	var total := 0
	for member in _party():
		if member != null and is_instance_valid(member) and member.has_method("get_item_count"):
			total += int(member.get_item_count(item_id))
	return total


## Why crafting is blocked, or "" when it can proceed. A reason string rather than a bool so the
## UI can say WHICH material is short instead of greying a button with no explanation.
func craft_blocked_reason(axis: String) -> String:
	if not lenses.has(axis):
		return "No such Lens."
	if not is_recipe_unlocked(axis):
		return "Recipe not yet unlocked — defeat a %s masterite." % axis
	if owns_lens(axis):
		return "You already hold this Lens."
	var recipe := get_recipe(axis)
	for item_id in recipe:
		var need: int = int(recipe[item_id])
		var have: int = material_count(item_id)
		if have < need:
			var iname: String = item_id
			if ItemSystem != null and ItemSystem.has_method("get_item"):
				iname = str(ItemSystem.get_item(item_id).get("name", item_id))
			return "Need %d %s (have %d)." % [need, iname, have]
	return ""


func can_craft(axis: String) -> bool:
	return craft_blocked_reason(axis) == ""


## Consumes materials and adds the Lens to the shared pool. Checks affordability BEFORE spending
## anything, so a partial consume can't leave the player short with no Lens to show for it.
func craft_lens(axis: String) -> bool:
	if not can_craft(axis):
		return false
	var recipe := get_recipe(axis)
	for item_id in recipe:
		var remaining: int = int(recipe[item_id])
		for member in _party():
			if remaining <= 0:
				break
			if member == null or not is_instance_valid(member) or not member.has_method("get_item_count"):
				continue
			var take: int = mini(remaining, int(member.get_item_count(item_id)))
			if take > 0 and member.remove_item(item_id, take):
				remaining -= take
		if remaining > 0:
			# can_craft passed, so this means the party changed under us mid-craft.
			push_warning("[LensSystem] craft_lens('%s'): %d %s went missing mid-craft — Lens NOT granted" % [axis, remaining, item_id])
			return false
	GameState.owned_lenses.append(axis)
	lens_crafted.emit(axis)
	print("[LensSystem] Crafted Lens: %s" % axis)
	return true


func owns_lens(axis: String) -> bool:
	return GameState != null and axis in GameState.owned_lenses


# ── Equipping (pooled — any PC, no binding) ──────────────────────────

## Which axis this character has equipped, or "" for none.
func get_equipped(char_id: String) -> String:
	if GameState == null:
		return ""
	return str(GameState.lens_assignments.get(char_id, ""))


## The character currently holding this axis, or "" if unequipped. One Lens exists per axis, so
## equipping it elsewhere moves it rather than duplicating it.
func holder_of(axis: String) -> String:
	if GameState == null:
		return ""
	for char_id in GameState.lens_assignments:
		if str(GameState.lens_assignments[char_id]) == axis:
			return str(char_id)
	return ""


## Equips to char_id, transferring from whoever held it. Free and unrestricted per struktured's
## pooled ruling — there is no cost and no save-point gate.
func equip_lens(char_id: String, axis: String) -> bool:
	if char_id == "" or not owns_lens(axis):
		return false
	var previous := holder_of(axis)
	if previous == char_id:
		return true
	if previous != "":
		GameState.lens_assignments.erase(previous)
		lens_unequipped.emit(previous, axis)
	var displaced := get_equipped(char_id)
	if displaced != "":
		lens_unequipped.emit(char_id, displaced)
	GameState.lens_assignments[char_id] = axis
	lens_equipped.emit(char_id, axis)
	return true


func unequip_lens(char_id: String) -> bool:
	if GameState == null or not GameState.lens_assignments.has(char_id):
		return false
	var axis := get_equipped(char_id)
	GameState.lens_assignments.erase(char_id)
	lens_unequipped.emit(char_id, axis)
	return true


# ── Effects ─────────────────────────────────────────────────────────

## Stat modifiers from this character's Lens, in PassiveSystem.get_passive_mods' exact shape so
## battle code can compose them without translating between two vocabularies.
func get_lens_mods(char_id: String) -> Dictionary:
	var mods := NEUTRAL_MODS.duplicate()
	var axis := get_equipped(char_id)
	if axis == "":
		return mods
	var lens := get_lens(axis)
	var stat_mods = lens.get("stat_mods", {})
	if not (stat_mods is Dictionary):
		return mods
	for key in stat_mods:
		if not mods.has(key):
			push_warning("[LensSystem] lens '%s' declares unknown stat_mod '%s' — ignored. Keys must match PassiveSystem.get_passive_mods." % [axis, key])
			continue
		# Multipliers compose; flat bonuses (crit_chance, evasion) add.
		match key:
			"crit_chance", "evasion":
				mods[key] += float(stat_mods[key])
			_:
				mods[key] *= float(stat_mods[key])
	return mods


## Non-stat effects (lens_lethal_floor, lens_execute_threshold, lens_ap_echo, …). Consumers live
## in battle code — cowir-battle's lane; this is the read surface.
func get_lens_meta_effects(char_id: String) -> Dictionary:
	var axis := get_equipped(char_id)
	if axis == "":
		return {}
	var me = get_lens(axis).get("meta_effects", {})
	return me.duplicate() if me is Dictionary else {}


## Dialogue tone tag for this character's Lens — cowir-story authors lines against these.
func get_voice_tint(char_id: String) -> String:
	var axis := get_equipped(char_id)
	return "" if axis == "" else str(get_lens(axis).get("voice_tint", ""))
