extends Node

## Tick 258: minimal /root/GameLoop stub for behavioral cutscene tests
## that need an inventory routing target. Real GameLoop isn't booted
## in headless GUT. This stub exposes just the `party` field that
## CutsceneDirector._add_item_to_party_leader and _step_update_item
## look up via `"party" in game_loop`.

var party: Array = []
