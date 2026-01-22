# Cowardly Irregular - Test Suite

This directory contains regression tests using the [GUT (Godot Unit Test)](https://github.com/bitwes/Gut) framework.

## Running Tests

### In the Godot Editor

1. Open the project in Godot Editor
2. Enable the GUT plugin: `Project > Project Settings > Plugins > GUT > Enable`
3. Open the GUT panel: `Project > Tools > GUT` or press `Ctrl+Shift+G`
4. Click "Run All" to run all tests

### From Command Line (CI)

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit
```

Note: You may need to run `godot --headless --import` first to import GUT classes.

## Test Structure

```
test/
├── README.md          # This file
├── run_tests.gd       # Simple test runner script
└── unit/
    ├── test_autobattle_system.gd  # AutobattleSystem regression tests
    ├── test_combatant.gd          # Combatant class tests
    └── test_game_state.gd         # GameState singleton tests
```

## Writing New Tests

1. Create a new file in `test/unit/` with the prefix `test_`
2. Extend `GutTest`:
   ```gdscript
   extends GutTest

   func test_example() -> void:
       assert_true(true, "This should pass")
   ```
3. Use assertions like:
   - `assert_true(condition, message)`
   - `assert_false(condition, message)`
   - `assert_eq(actual, expected, message)`
   - `assert_ne(actual, expected, message)`
   - `assert_gt(actual, expected, message)`
   - `assert_lt(actual, expected, message)`
   - `assert_typeof(value, type, message)`
   - `assert_not_null(value, message)`

## Key Regressions to Watch

- **Autobattle Profile Loading**: `execute_grid_autobattle()` must use `get_character_script()`, not raw `character_scripts` dict
- **HP/MP Calculations**: `get_hp_percentage()` and `get_mp_percentage()` must handle edge cases
- **Input Handling**: Controller button mappings may vary; use input actions, not raw button indices
