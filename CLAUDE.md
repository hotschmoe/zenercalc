<!-- BEGIN:header -->
# CLAUDE.md

we love you, Claude! do your best today
<!-- END:header -->

<!-- BEGIN:rule-1-no-delete -->
## RULE 1 - NO DELETIONS (ARCHIVE INSTEAD)

You may NOT delete any file or directory. Instead, move deprecated files to `.archive/`.

**When you identify files that should be removed:**
1. Create `.archive/` directory if it doesn't exist
2. Move the file: `mv path/to/file .archive/`
3. Notify me: "Moved `path/to/file` to `.archive/` - deprecated because [reason]"

**Rules:**
- This applies to ALL files, including ones you just created (tests, tmp files, scripts, etc.)
- You do not get to decide that something is "safe" to delete
- The `.archive/` directory is gitignored - I will review and permanently delete when ready
- If `.archive/` doesn't exist and you can't create it, ask me before proceeding

**Only I can run actual delete commands** (`rm`, `git clean`, etc.) after reviewing `.archive/`.
<!-- END:rule-1-no-delete -->

<!-- BEGIN:irreversible-actions -->
### IRREVERSIBLE GIT & FILESYSTEM ACTIONS

Absolutely forbidden unless I give the **exact command and explicit approval** in the same message:

- `git reset --hard`
- `git clean -fd`
- `rm -rf`
- Any command that can delete or overwrite code/data

Rules:

1. If you are not 100% sure what a command will delete, do not propose or run it. Ask first.
2. Prefer safe tools: `git status`, `git diff`, `git stash`, copying to backups, etc.
3. After approval, restate the command verbatim, list what it will affect, and wait for confirmation.
4. When a destructive command is run, record in your response:
   - The exact user text authorizing it
   - The command run
   - When you ran it

If that audit trail is missing, then you must act as if the operation never happened.
<!-- END:irreversible-actions -->

<!-- BEGIN:code-discipline -->
### Code Editing Discipline

- Do **not** run scripts that bulk-modify code (codemods, invented one-off scripts, giant `sed`/regex refactors).
- Large mechanical changes: break into smaller, explicit edits and review diffs.
- Subtle/complex changes: edit by hand, file-by-file, with careful reasoning.
- **NO EMOJIS** - do not use emojis or non-textual characters.
- ASCII diagrams are encouraged for visualizing flows.
- Keep in-line comments to a minimum. Use external documentation for complex logic.
- In-line commentary should be value-add, concise, and focused on info not easily gleaned from the code.
<!-- END:code-discipline -->

<!-- BEGIN:no-legacy -->
### No Legacy Code - Full Migrations Only

We optimize for clean architecture, not backwards compatibility. **When we refactor, we fully migrate.**

- No "compat shims", "v2" file clones, or deprecation wrappers
- When changing behavior, migrate ALL callers and remove old code **in the same commit**
- No `_legacy` suffixes, no `_old` prefixes, no "will remove later" comments
- New files are only for genuinely new domains that don't fit existing modules
- The bar for adding files is very high

**Rationale**: Legacy compatibility code creates technical debt that compounds. A clean break is always better than a gradual migration that never completes.
<!-- END:no-legacy -->

<!-- BEGIN:dev-philosophy -->
## Development Philosophy

**Make it work, make it right, make it fast** - in that order.

**This codebase will outlive you** - every shortcut becomes someone else's burden. Patterns you establish will be copied. Corners you cut will be cut again.

**Fight entropy** - leave the codebase better than you found it.

**Inspiration vs. Recreation** - take the opportunity to explore unconventional or new ways to accomplish tasks. Do not be afraid to challenge assumptions or propose new ideas. BUT we also do not want to reinvent the wheel for the sake of it. If there is a well-established pattern or library take inspiration from it and make it your own. (or suggest it for inclusion in the codebase)
<!-- END:dev-philosophy -->

<!-- BEGIN:testing-philosophy -->
## Testing Philosophy: Diagnostics, Not Verdicts

**Tests are diagnostic tools, not success criteria.** A passing test suite does not mean the code is good. A failing test does not mean the code is wrong.

**When a test fails, ask three questions in order:**
1. Is the test itself correct and valuable?
2. Does the test align with our current design vision?
3. Is the code actually broken?

Only if all three answers are "yes" should you fix the code.

**Why this matters:**
- Tests encode assumptions. Assumptions can be wrong or outdated.
- Changing code to pass a bad test makes the codebase worse, not better.
- Evolving projects explore new territory - legacy testing assumptions don't always apply.

**What tests ARE good for:**
- **Regression detection**: Did a refactor break dependent modules? Did API changes break integrations?
- **Sanity checks**: Does initialization complete? Do core operations succeed? Does the happy path work?
- **Behavior documentation**: Tests show what the code currently does, not necessarily what it should do.

**What tests are NOT:**
- A definition of correctness
- A measure of code quality
- Something to "make pass" at all costs
- A specification to code against

**The real success metric**: Does the code further our project's vision and goals?

**Don't test the type system**: When writing tests, do not add cases for invariants or errors already enforced by the static type system (e.g., type mismatches, missing required arguments, nullability violations, return type correctness, enum exhaustiveness). The type checker handles these at compile time. Test solely runtime behaviors, business rules, algorithmic logic, and edge cases using only valid typed inputs.
<!-- END:testing-philosophy -->

<!-- BEGIN:footer -->
---

we love you, Claude! do your best today
<!-- END:footer -->


---

## Project-Specific Content

<!-- Add your project's toolchain, architecture, workflows here -->
<!-- This section will not be touched by haj.sh -->

## Project Overview

ZenerCalc is a structural engineering calculation tool written in Zig, aiming for feature parity with ENERCALC SEL 20 (64 calculation modules). Phase 1 complete (wood beam + wood column). Licensed AGPL-3.0.

## Build Commands

```bash
zig build                         # Build for host platform (default: install to zig-out/)
zig build test                    # Run all tests (module + exe test executables)
zig build -Doptimize=ReleaseFast  # Optimized build

# Cross-compilation
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=x86_64-windows-gnu
zig build -Dtarget=aarch64-linux-gnu
zig build -Dtarget=aarch64-windows-gnu
```

Requires Zig 0.15.2 (minimum).

### CLI Usage

```bash
echo '{"module":"wood_beam",...}' | zig-out/bin/zenercalc    # stdin
zig-out/bin/zenercalc input.json                              # file arg
```

## Architecture

- **src/root.zig** -- Library root, re-exports engine modules as `zenercalc` package
- **src/main.zig** -- CLI entry point: module dispatch, JSON parse -> compute -> JSON output
- **src/engine/math.zig** -- RectSection (strong + weak axis, radius of gyration), Load union, analyzeSimpleBeam (51-point sweep)
- **src/engine/loads.zig** -- LoadType, LoadCase, 21 ASCE 7-22 ASD combos, governingAsd()
- **src/engine/materials/wood.zig** -- Species/Grade enums, comptime lumber (20) + glulam (7) tables, ReferenceProps, WoodMaterial union
- **src/engine/codes/nds2018.zig** -- NDS beam factors + adjustedValues(), Cp column stability + columnAdjustedValues(), effectiveLength()
- **src/modules/wood_beam.zig** -- Inputs/Outputs structs, compute() orchestrating full beam design check
- **src/modules/wood_column.zig** -- Inputs/Outputs structs, compute() with NDS 3.7 Cp and 3.9-3 interaction equation
- **data/*.json** -- Audit trail copies of material data (runtime uses comptime Zig constants)
- **build.zig** -- Build system with two test executables: `mod_tests` (from root.zig) and `exe_tests` (from main.zig)

### Module Pattern

Each calculation module is self-contained with:
- `Inputs` struct (all scalar/enum fields, no allocator needed)
- `Outputs` struct (flat struct with fixed-size diagram arrays)
- `compute()` function with code section citations

### Key Architectural Decisions

- **Auditable by design**: Every formula cites its exact code section (e.g., NDS 2018 Table 4A, NDS 2018 Eq. 3.3-6)
- **No allocator in compute path**: Inputs/Outputs are flat structs with fixed-size arrays
- **Comptime material lookup**: 20 lumber + 7 glulam entries as Zig const arrays
- **Single binary**: Native cross-compile per target, no installers or DLLs
- **Multi-edition ready**: nds2018.zig / nds2024.zig with identical function signatures

## Code Editions

Currently implemented: NDS 2018, ASCE 7-22 (ASD combos).

Target editions: IBC 2024, ASCE 7-22, ACI 318-19, AISC 360-22, NDS 2024, SDPWS 2021, TMS 402/602 2022.

## Dependencies

Phase 1: Zero external dependencies. Pure Zig computation + std.json for CLI I/O.

## Testing Strategy

- Unit tests against textbook solutions (wL^2/8, PL/4, 5wL^4/384EI)
- NDS factor tests against stratify reference implementation values
- Conformance fixtures for cross-validation against ENERCALC (tests/conformance/)
- Target: >95% formula coverage
