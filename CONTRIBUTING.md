# Contributing to Mochi

Thanks for your interest! Mochi is a small, friendly codebase — a great place to
hack on a desktop pet.

## Dev setup

You only need the Xcode **Command Line Tools** (`xcode-select --install`), not
full Xcode.

```bash
./build.sh     # compile + bundle into build/Mochi.app
./run.sh       # build (if needed) + launch
pkill -x Mochi # stop
```

There is no test suite yet; verify changes by running the app and watching the
pet. To see the pet on a specific display, drag it there or move your cursor to
that screen before launching.

## Architecture in 30 seconds

- **`PetState`** is the single source of truth (an `ObservableObject`).
- **`PetController`** is the brain — it mutates state and animates window movement.
- **`PetView`** is a pure SwiftUI rendering of the state.
- **`PetWindow` / `PetContainerView`** own the floating panel and mouse handling.

To add a behavior: add a case to `PetAction`, drive it from `PetController`, and
render it in `PetView`. To reskin: edit `Palette` and the shapes in `PetView.swift`.

## Guidelines

- Keep the character **asset-free** (vector shapes) unless you're adding an
  opt-in custom-sprite/theme system.
- Keep it **lightweight** — this is a background companion, not a CPU hog. Avoid
  high-frequency timers except during active animation (e.g. walking).
- Match the existing comment style and structure.
- One focused change per PR; describe what you changed and include a screenshot
  or short clip for anything visual.

## Good first issues

- New idle animations (a stretch, a look-around, a happy hop).
- New expressions / moods.
- A "follow the cursor" mode.
- Remember the pet's last position across launches.
- An alternative character or color theme.

By contributing you agree your work is licensed under the project's
[MIT License](LICENSE).
