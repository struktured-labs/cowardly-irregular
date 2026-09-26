extends GutTest

## The Dancing Tonberry exists only in Harmonia (VillageBar is built there, the exit
## is hardcoded to harmonia_village, the teleport row says "Tavern (Harmonia)").
## Walking in keeps village_harmonia because interior_tavern is unauthored and inherits.
## Continue from the title has no area bed to inherit. Without a home village the cold
## start falls through to this world's generic bed, village_medieval ("Harmonia's Rest"),
## so the same room plays a different theme depending on how you arrived.
## Driven from the call _ready actually makes — constructing TavernInterior builds the
## piano, which is the #224 hang.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const TAVERN := "res://src/maps/interiors/TavernInterior.gd"

var _saved_world: int = 1


func before_each() -> void:
	_saved_world = int(GameState.current_world)
	GameState.current_world = 1
	SoundState.restore()


func after_each() -> void:
	SoundState.restore()
	GameState.current_world = _saved_world


func _bed() -> String:
	var player: AudioStreamPlayer = SoundManager._music_player
	if player == null or player.stream == null:
		return ""
	return player.stream.resource_path.get_file()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## Arguments of the play_area_music call inside _ready: [key, resume, home].
func _tavern_call() -> Array:
	var src := FileAccess.get_file_as_string(TAVERN)
	var ready_at := src.find("func _ready(")
	assert_gt(ready_at, -1, "FLOOR: TavernInterior must still have _ready")
	var body := src.substr(ready_at, 900)
	var m := RegEx.create_from_string("play_area_music\\(\\s*\"([^\"]+)\"(?:\\s*,\\s*([0-9.]+)\\s*,\\s*\"([^\"]+)\")?\\s*\\)").search(body)
	assert_not_null(m, "FLOOR: TavernInterior._ready must call play_area_music")
	var resume := 0.0
	if m.get_string(2) != "":
		resume = m.get_string(2).to_float()
	return [m.get_string(1), resume, m.get_string(3)]


func test_a_save_inside_the_tavern_keeps_harmonias_theme() -> void:
	SoundManager.play_area_music("harmonia_village")
	await _settle()
	var village_bed := _bed()
	assert_eq(village_bed, "village_harmonia.ogg",
		"CONTROL: Harmonia's own theme must load — two empty beds would compare equal and hide the split")

	var args: Array = _tavern_call()
	assert_eq(str(args[0]), "interior_tavern",
		"FLOOR: the tavern must still ask for interior_tavern so a walk-in can inherit the village bed")

	SoundManager.play_area_music(str(args[0]), float(args[1]), str(args[2]))
	await _settle()
	var walked := _bed()
	assert_eq(walked, village_bed,
		"CONTROL: walking into the tavern from Harmonia must keep %s" % village_bed)

	## Title Continue: play_music("title") empties _current_area, so there is nothing to inherit.
	SoundState.restore()
	GameState.current_world = 1
	SoundManager.play_area_music(str(args[0]), float(args[1]), str(args[2]))
	await _settle()
	var cold := _bed()
	assert_eq(cold, walked,
		"loading a save in the Dancing Tonberry played %s; walking in plays %s" % [cold, walked])
