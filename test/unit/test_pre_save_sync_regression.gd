extends GutTest

## Silent failure: SaveSystem.save_game / quick_save / auto_save read
## GameState.player_party — the SERIALIZED snapshot — but the live
## Combatant array (in GameLoop.party) is the source of truth. The
## sync from runtime → serialized only ran in _open_overworld_menu.
##
## So any save that fired without the player opening the menu since
## the last battle (zone-transition auto-save, 5-min auto-save tick,
## boss-defeat auto-save from tick 10) silently saved stale party
## data. Loading the save reverted XP, HP, items, status — anything
## the battle had changed since the last sync.
##
## Fix: SaveSystem fires pre_save_sync BEFORE _create_save_data reads
## GameState. GameLoop listens and calls _sync_party_to_game_state.

const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"
const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_save_system_declares_pre_save_sync_signal() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("signal pre_save_sync"),
		"SaveSystem must declare a pre_save_sync signal that listeners use to flush runtime state")


func test_save_game_emits_pre_save_sync_before_read() -> void:
	# Critical ordering: the emit must come BEFORE _create_save_data,
	# otherwise the snapshot reads stale data and the sync is for nothing.
	var src := _read(SAVE_SYSTEM)
	var idx := src.find("func save_game")
	assert_gt(idx, -1, "save_game must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	var emit_at := body.find("pre_save_sync.emit()")
	var read_at := body.find("_create_save_data()")
	assert_gt(emit_at, -1, "save_game must emit pre_save_sync")
	assert_gt(read_at, -1, "save_game must call _create_save_data")
	assert_lt(emit_at, read_at,
		"pre_save_sync.emit() must run BEFORE _create_save_data() — otherwise the flush is wasted")


func test_game_loop_connects_pre_save_sync_to_sync_party() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("pre_save_sync.connect(_sync_party_to_game_state)"),
		"GameLoop must wire its _sync_party_to_game_state to SaveSystem.pre_save_sync — otherwise the signal is unobserved and saves stay stale")
