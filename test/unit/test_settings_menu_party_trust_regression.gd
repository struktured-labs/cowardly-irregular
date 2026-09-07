extends GutTest

## Queue #4: Settings-side Party Trust surface. The out-of-battle answer to
## cowir-main's "how do I disable trust if it's on?" user complaint (msg
## 2152). Row per PC toggling player_trust without requiring debug mode.

const SettingsScript = preload("res://src/ui/SettingsMenu.gd")


var _menu: Node


func before_each() -> void:
	_menu = SettingsScript.new()
	add_child_autofree(_menu)


func _seed_gs_party(members: Array) -> void:
	# GameState.player_party is typed Array[Dictionary]; drain and repopulate
	# so the typed constraint is honored (bare = Array assignment errors).
	if not GameState:
		return
	GameState.player_party.clear()
	for m in members:
		GameState.player_party.append(m)


## ── snapshot reads both live and dict-mirror paths ──────────────────────

func test_party_snapshot_pulls_from_gamestate_when_no_live_gameloop() -> void:
	_seed_gs_party([
		{"combatant_name": "Hero", "player_trust": false},
		{"combatant_name": "Mira", "player_trust": true},
	])
	var snap: Array = _menu._get_party_snapshot()
	assert_gte(snap.size(), 2, "settings menu must surface every party member for trust toggling")
	var found_mira: bool = false
	for entry in snap:
		if str(entry.get("id", "")) == "mira":
			assert_true(bool(entry.get("player_trust", false)),
				"pre-existing player_trust must surface in the row's toggle state")
			found_mira = true
	assert_true(found_mira, "party member 'mira' must appear in the trust snapshot")


func test_party_snapshot_is_empty_when_no_party() -> void:
	_seed_gs_party([])
	assert_eq(_menu._get_party_snapshot().size(), 0,
		"empty party (main-menu / no save) → no rows rendered, no crash")


## ── toggle mutates player_trust on both sinks ───────────────────────────

func test_toggle_flips_player_trust_on_gamestate_mirror() -> void:
	_seed_gs_party([{"combatant_name": "Hero", "player_trust": false}])
	# selected_index is only used to route to _update_toggle_display; we
	# pre-seed the settings-items list with a matching entry so the display
	# call doesn't NPE.
	_menu._settings_items = [{"control": null, "type": "toggle", "id": "party_trust:hero"}]
	_menu._toggle_party_trust("hero", 0)
	assert_true(bool(GameState.player_party[0].get("player_trust", false)),
		"toggling flips OFF → ON on the GameState mirror")
	_menu._toggle_party_trust("hero", 0)
	assert_false(bool(GameState.player_party[0].get("player_trust", false)),
		"toggling again flips ON → OFF")
