# Narrative System for Godot

All-in-one narrative system addon for **Godot 4.4+** — branching dialogue with
choices and conditions, quests (with log/tracker UI), save/load, localization,
barks, alerts, a cutscene sequencer, and authoring/validation tools. Aims at
the position "Dialogue System for Unity" holds, natively in Godot.

- **Engine**: Godot 4.4+ (developed and tested on 4.6.3)
- **Language**: pure GDScript, zero external dependencies
- **License**: MIT ([LICENSE](LICENSE))
- **Repository**: <https://github.com/yskim3271/godot-narrative-system> —
  screenshots, five runnable demos in `examples/`, and per-feature guides in
  `docs/` (Korean; the repo README and all code comments are English).

## Features

- **Branching dialogue**: speaker/text nodes, conditional skips, choices
  (hidden or grayed-out when locked), re-entrant signal-safe runner,
  `has_seen()` first-meeting variations.
- **Graph editor**: a "Narrative" main-screen tab — node canvas with inline
  editing (text, speaker, node id rename with automatic link retargeting,
  choice text/target), full undo/redo, validation, auto-layout.
- **Bottom panel tooling**: database overview, validation with
  double-click-to-focus (jumps the graph to the offending node and opens it
  in the Inspector), a per-locale translation coverage report, and an
  in-editor dialogue **preview** (sandboxed playback with live state view —
  resources are never touched).
- **Text authoring format (.ndlg)**: writer-friendly line-based scripts with
  atomic import and round-trip export. Plus inline `[var=x]` markup with
  editor shortcuts, and BBCode pass-through.
- **Quests**: prerequisites, objectives with clamped progress and
  auto-complete conditions, reward actions, abandon & repeatable quests with
  completion tracking, categories, quest log + tracker reference UI,
  dialogue-action integration.
- **Sequencer (cutscenes)**: runs alongside dialogue lines, cancellable by
  input. Sequential lines plus Unity-DS-style parallel scheduling:
  `cmd() @ 1.5`, `cmd() @ message("ready")`, `cmd() -> "done"`. 16 built-in
  commands (animation, audio, 2D/3D camera, actors), custom command
  registration.
- **Safe DSL**: hand-written lexer/parser/evaluator for conditions, actions
  and sequencer lines — no `eval`, no arbitrary code execution; game functions
  are whitelist-registered.
- **Save/load**: versioned plain-JSON saves, atomic writes with backup
  rotation, corruption isolation, schema migrations, dialogue-position resume.
- **Localization**: layered resolution (current language → inline → fallback),
  convention keys, CSV round-trip, runtime language switching.
- **Barks & alerts**: speech bubbles above 2D and 3D actors, alert queue.
- **Validator**: static analysis of the whole database (broken links,
  unknown ids, DSL parse errors, unreachable nodes, …) — editor panel + CLI.

## Installation

1. Copy the `addons/narrative_system/` folder into your project (installing
   from the Asset Library does this for you).
2. Enable the plugin: **Project Settings → Plugins → Narrative System** — this
   registers the `Narrative` autoload and project settings.
3. Point the `narrative_system/database_path` project setting at your
   `NarrativeDatabase` resource (the bottom **Narrative** panel's *Load* does
   this automatically).

The runtime also works without the editor plugin: register
`runtime/narrative.gd` as an autoload named `Narrative` manually.

## Quick start

```gdscript
# Scene: add ui/dialogue_box.tscn and ui/choice_list.tscn instances, then:
Narrative.start_dialogue("guard_talk")

Narrative.dialogue_ended.connect(func(id): player.can_move = true)
Narrative.quest_updated.connect(func(id): quest_popup.refresh())
```

Everything goes through the `Narrative` facade: signals for presentation,
methods for control (`advance()`, `select_choice()`, `start_quest()`,
`save_game()`, `set_language()`, `bark()`, `play_sequence()`, …). The bundled
UIs are replaceable reference implementations — they only consume public
signals/APIs, so restyling or swapping them is supported.

## Documentation & demos

The source repository ships five runnable demo projects (basic dialogue,
branching choices authored in `.ndlg`, quest cycle, localization + cutscene,
and an integrated showcase) and full documentation: getting started, authoring
guide, graph editor, DSL grammar, quest system, save format, localization,
sequencer command reference, extension guide, API reference, and architecture
notes.
