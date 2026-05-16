# Console Table Library Design

## Goal

Provide a small reusable SourcePawn library for rendering monospaced console panels with:

- optional header text
- optional body table
- optional footer text
- safe truncation for console rendering
- typed cell formatting for `int`, `float`, and `string`

The primary target is `player_fakelag`, but the design should also support other admin/stat/report plugins.

## Scope

This library is intentionally focused on **console panels**, not general-purpose UI rendering.

It should solve these problems:

- stable width per report
- reusable borders and multiline sections
- consistent truncation
- left/right alignment
- reusable table schema
- optional legends/notes below the table

It should **not** solve:

- translations
- command permissions
- audience selection rules
- plugin-specific business logic

Those remain the responsibility of the caller.

## Conceptual Model

The library is divided into three logical sections:

1. Header
- optional text lines
- multiline allowed
- rendered above the table

2. Body
- optional typed table
- fixed-width columns
- rows of cells

3. Footer
- optional text lines
- legends, notes, mappings, summaries

This makes the final output behave like a structured console panel:

```text
|---------------------------------------------------------|
| Header line 1                                           |
| Header line 2                                           |
|---------------------------------------------------------|
| Column A     | Column B | Column C                      |
|---------------------------------------------------------|
| ... rows ...                                            |
|---------------------------------------------------------|
| Footer line 1                                           |
| Footer line 2                                           |
|---------------------------------------------------------|
```

## Data Model

### Panel

Represents the full renderable unit.

Proposed fields:

- `width`
- `headerLineCount`
- `footerLineCount`
- `hasTable`
- `safeAsciiOnly`

Responsibilities:

- own global render settings
- render borders
- render header/footer
- render the body table if present

### Table

Represents the body section.

Proposed fields:

- `columnCount`
- `rowCount`
- `separatorWidth`

Responsibilities:

- hold the schema
- render column titles
- render rows according to column widths and alignment

### Column

Represents one table column.

Proposed fields:

- `title`
- `width`
- `alignment`
- `typeHint`

### Row

Represents one body row.

Proposed fields:

- `cellCount`
- ordered cells

### Cell

Represents one typed value already attached to a row.

Supported logical types:

- `string`
- `int`
- `float`

Proposed fields:

- `type`
- `stringValue`
- `intValue`
- `floatValue`
- `floatPrecision`

## Type System

Recommended enums:

```sourcepawn
enum ConsoleTableAlignment
{
	ConsoleTableAlignment_Left = 0,
	ConsoleTableAlignment_Right,
	ConsoleTableAlignment_Center
}

enum ConsoleTableCellType
{
	ConsoleTableCellType_String = 0,
	ConsoleTableCellType_Int,
	ConsoleTableCellType_Float
}
```

The renderer should format numbers internally and align them according to column settings.

## Rendering Rules

### Width

The panel width is explicit and belongs to the panel instance.

Examples:

- `58` for compact global balance
- `82` for pair balance
- `64` for small stat panels

### Header/Footer

- multiline supported
- always rendered as text blocks
- individually truncated to panel width

### Table

- column widths are explicit
- total content width must be validated against panel width
- table output is monospaced

### Truncation

Two policies are needed:

1. Console-safe ASCII truncation
- replaces unsafe/multibyte characters with `?`
- truncates visually to fit the target width

2. UTF-8 trimmed text
- preserves UTF-8
- truncates by character count
- useful for optional footer legends such as:
  - `#3 = (ꚳ𖤢ꛕꛅꚶꚽꛎ)`

The main body table should default to **console-safe** mode.

### Alignment

- `string`: left by default
- `int`: right by default
- `float`: right by default

Center alignment should be available but not required for the first migration.

## API Proposal

The implementation should stay pragmatic for SourcePawn and avoid overengineering.

### Construction

```sourcepawn
stock void ConsolePanel_Reset(ConsolePanel panel)
stock void ConsolePanel_SetWidth(ConsolePanel panel, int width)
stock void ConsolePanel_EnableSafeAscii(ConsolePanel panel, bool enabled)
```

### Header/Footer

```sourcepawn
stock bool ConsolePanel_AddHeaderLine(ConsolePanel panel, const char[] text)
stock bool ConsolePanel_AddFooterLine(ConsolePanel panel, const char[] text)
```

### Table Schema

```sourcepawn
stock void ConsoleTable_Reset(ConsoleTable table)
stock bool ConsoleTable_AddColumn(ConsoleTable table, const char[] title, int width, ConsoleTableAlignment alignment, ConsoleTableCellType typeHint)
```

### Rows

```sourcepawn
stock bool ConsoleTable_BeginRow(ConsoleTable table)
stock bool ConsoleTable_AddStringCell(ConsoleTable table, const char[] value)
stock bool ConsoleTable_AddIntCell(ConsoleTable table, int value)
stock bool ConsoleTable_AddFloatCell(ConsoleTable table, float value, int precision = 1)
stock bool ConsoleTable_EndRow(ConsoleTable table)
```

### Render

```sourcepawn
stock void ConsolePanel_RenderToClient(ConsolePanel panel, int client)
stock void ConsolePanel_RenderToAudience(ConsolePanel panel, int excludedClient = 0)
```

## Implementation Strategy

### Phase 1

Build a **local** library in this repo:

- `scripting/include/console_table.inc`
- implementation as `stock` helpers in the first version

No separate extension or plugin dependency.

### Phase 2

Migrate `player_fakelag` balance output to the library:

- global balance
- pair balance
- preview variants

### Phase 3

Reuse in other panels/stats/admin diagnostics.

## Why Not Make It Fully Dynamic?

SourcePawn is not a good target for a fully dynamic generic UI object graph.

The library should prefer:

- explicit fixed-size buffers
- bounded row/column counts
- deterministic rendering

instead of:

- unbounded builders
- highly abstract data containers
- complex ownership rules

This keeps it fast, readable, and practical for plugin code.

## Suggested Limits

Reasonable initial bounds:

- max panel width: `96`
- max header lines: `8`
- max footer lines: `8`
- max columns: `8`
- max rows: `32`
- max cell text buffer: `128`

These are enough for admin/report tables without making the library large or fragile.

## Migration Notes For player_fakelag

The current balance renderer already contains most of the required primitives:

- border rendering
- multiline sections
- safe ASCII truncation
- UTF-8 trimmed legends
- per-report width

So the migration path is:

1. extract generic render helpers
2. define panel/table types
3. rebuild balance output on top of the new API

No business logic should move into the library. Only rendering concerns should move.
