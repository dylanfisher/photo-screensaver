# Code map

Where things live, and how to find one before you build a second. Read this before creating any
new file.

This file describes **shape, not contents** — conventions and search commands, never an inventory.
An inventory would be a second copy of facts the code already holds, it would rot within a week,
and it would have no error message when it diverged. If you catch yourself listing what exists
here, stop: the grep is the list.

## Find before you create

The single rule that matters. AGENTS.md principles 1–3 (single source of truth, match the
surrounding code, DRY on the third occurrence) all depend on it — none of them can be followed
against a codebase you haven't searched.

| Before adding… | Run |
|---|---|
| any named thing | `rg -i '<name>' --type swift` |
| a primitive | `ls Sources/Primitives/` |
| a core part | `ls Sources/Core/` |
| a function | `rg 'func <name>' Sources/` |
| a setting | `rg '<key>' Sources/Settings` — settings are loaded in one module only |
| a type | `rg '(struct\|class\|enum\|protocol\|actor) <Name>'` |

If a search turns up something close but not identical, that's the second occurrence. Use it or
duplicate it — do not abstract yet (principle 3).

## Tiers

Each tier is a Swift Package Manager module, so its imports are visible as `import <Tier>` lines.

| Tier | Path | What belongs here | May import from |
|---|---|---|---|
| **primitives** | `Sources/Primitives` | Smallest reusable units. No knowledge of this app, no config reads. Portable to another project as-is. | nothing in this table |
| **config** | `Sources/Settings` | The settings type and the one place the config file is read and validated. Throws on a bad or missing value. | nothing |
| **core** | `Sources/Core` | App-specific parts: photo index, preloader, Ken Burns, motion scheduling, display power. | Settings, Primitives |
| **app** | `Sources/App` | The executable: menu bar, full-screen window, wiring core parts together. | Core, Settings, Primitives |

**Dependency direction is one-way: app → core → primitives.** Never upward. If a primitive needs
something from core, it isn't a primitive.

`scripts/arch` enforces this table; it holds the same map in code and fails on any forbidden
`import`. A new module joins both this table and that script, and is declared in `Package.swift`.

## Naming

- One thing per file; the filename is the thing's name.
- Module directories are named for the tier (`Primitives`, `Core`); files are `UpperCamelCase` after the type they hold.
- Tests mirror the tree: `Sources/<Module>/Foo.swift` is tested in `Tests/<Module>Tests/FooTests.swift`.
- Types are `public` only when another module uses them.

## Promotion

Things move up a tier deliberately, never by accident:

- **Third occurrence** → extract to the lowest tier that all three callers can reach (principle 3).
- **Component loses its project knowledge** → it's a primitive now; move it down.
- **Primitive grows a config read or a domain type** → it was never a primitive; move it up.

A promotion is its own commit, separate from whatever work revealed it (principle 4).

<!-- paths: Sources/Primitives Sources/Settings Sources/Core Sources/App -->
<!-- ↑ scripts/check verifies every path above exists. Keep it in sync with the Tiers table;
     a rename that misses this line fails the gate, which is the point. -->
