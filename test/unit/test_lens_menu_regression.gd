extends GutTest

## Lens screen + retroactive unlock.
##
## The screen is the whole system's visibility: recipe unlock, crafting, pooled assignment and
## four combat effects are all invisible without it. So this pins that it BUILDS and that its
## states are distinguishable — a screen that renders every Lens identically would make a working
## system look broken.

const MenuScript := preload("res://src/ui/LensMenu.gd")

var _saved_recipes: Array[String] = []
var _saved_owned: Array[String] = []
var _saved_assign: Dictionary = {}
var _saved_defeated: Dictionary = {}
var _viewport: SubViewport


func before_each() -> void:
	_saved_recipes = GameState.unlocked_lens_recipes.duplicate()
	_saved_owned = GameState.owned_lenses.duplicate()
	_saved_assign = GameState.lens_assignments.duplicate()
	_saved_defeated = (GameState.game_constants.get("defeated_monsters", {}) as Dictionary).duplicate()
	GameState.unlocked_lens_recipes.clear()
	GameState.owned_lenses.clear()
	GameState.lens_assignments.clear()
	GameState.game_constants["defeated_monsters"] = {}
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	add_child(_viewport)


func after_each() -> void:
	_viewport.queue_free()
	GameState.unlocked_lens_recipes = _saved_recipes
	GameState.owned_lenses = _saved_owned
	GameState.lens_assignments = _saved_assign
	GameState.game_constants["defeated_monsters"] = _saved_defeated


func _make_menu() -> Control:
	var m: Control = MenuScript.new()
	m.size = Vector2(1280, 720)
	_viewport.add_child(m)
	await get_tree().process_frame
	return m


# ── Retroactive unlock (cowir-main default 2026-07-27) ──────────────

func test_retroactive_unlock_grants_recipes_for_already_dead_masterites() -> void:
	# Without this an existing save can NEVER see the system: the gate waits on a defeat that
	# already happened and will not happen again.
	GameState.game_constants["defeated_monsters"]["masterite_warden_medieval"] = true
	var granted := LensSystem.reconcile_retroactive_unlocks()
	assert_eq(granted, 1, "one already-dead masterite should unlock exactly one recipe")
	assert_true(LensSystem.is_recipe_unlocked("warden"))


func test_retroactive_unlock_is_idempotent() -> void:
	GameState.game_constants["defeated_monsters"]["masterite_warden_medieval"] = true
	LensSystem.reconcile_retroactive_unlocks()
	assert_eq(LensSystem.reconcile_retroactive_unlocks(), 0,
		"a second reconcile must grant nothing — the screen calls this on every open")
	assert_eq(GameState.unlocked_lens_recipes.count("warden"), 1, "no duplicate entries")


func test_retroactive_unlock_grants_nothing_on_a_fresh_save() -> void:
	assert_eq(LensSystem.reconcile_retroactive_unlocks(), 0,
		"a save with no masterite kills must unlock nothing — retroactive must not mean free")
	assert_eq(GameState.unlocked_lens_recipes.size(), 0)


func test_five_masterites_of_one_axis_still_yield_one_recipe() -> void:
	for mid in ["masterite_warden_medieval", "masterite_warden_suburban", "masterite_warden_industrial"]:
		GameState.game_constants["defeated_monsters"][mid] = true
	LensSystem.reconcile_retroactive_unlocks()
	assert_eq(GameState.unlocked_lens_recipes.count("warden"), 1,
		"the axis unlocks once no matter how many of its masterites died")


# ── The screen ──────────────────────────────────────────────────────

func test_menu_builds_with_no_lenses_owned() -> void:
	var m = await _make_menu()
	assert_gt(m.get_child_count(), 0, "the screen must build on a save with nothing unlocked")
	m.free()


func test_menu_builds_with_lenses_owned_and_assigned() -> void:
	GameState.unlocked_lens_recipes.append("warden")
	GameState.owned_lenses.append("warden")
	GameState.lens_assignments["fighter"] = "warden"
	var m = await _make_menu()
	assert_gt(m.get_child_count(), 0, "the screen must build with a Lens equipped")
	m.free()


func test_the_three_states_render_differently() -> void:
	# Locked / craftable / owned must be visually distinguishable, or a working system
	# reads as a static list.
	GameState.unlocked_lens_recipes.append("warden")   # craftable-but-unaffordable
	GameState.unlocked_lens_recipes.append("tempo")
	GameState.owned_lenses.append("tempo")             # owned
	# arbiter + curator stay locked
	var m = await _make_menu()
	var texts: Array = []
	_collect_labels(m, texts)
	var joined := " | ".join(texts)
	assert_string_contains(joined, "Unknown", "locked axes must say so")
	assert_true(joined.contains("Unassigned") or joined.contains("Worn by"),
		"an owned Lens must show its wearer or say it is unassigned")
	m.free()


func test_every_axis_shows_its_passive() -> void:
	# Two of four axes carry their identity ENTIRELY in the passive (Tempo, Curator have no stat
	# tilt), so a screen that hid it would make them look like empty Lenses.
	var m = await _make_menu()
	var texts: Array = []
	_collect_labels(m, texts)
	var joined := " | ".join(texts)
	for passive_name in ["Iron Will", "Final Word", "Stolen Beat", "Accounting"]:
		assert_string_contains(joined, passive_name,
			"'%s' must be visible on the Lens screen" % passive_name)
	m.free()


func test_menu_is_reachable_from_the_overworld_menu() -> void:
	# A screen with no entry point is the shipped-unwired defect class.
	var src := FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_string_contains(src, '"id": "lenses"', "Lenses must appear in the overworld menu list")
	assert_string_contains(src, "_open_lens_menu", "and the dispatch must route to it")
	assert_string_contains(src, "LensMenu.gd", "and the opener must load the screen")


func _collect_labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_labels(c, out)
