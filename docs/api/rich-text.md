# Rich Text Widget

Formatted text display with inline styling and clickable links (`src/ui/widgets/rich_text.zig`).

## Features

- **Bold/Italic/Underline** - Basic text formatting styles
- **Custom colors** - Inline text coloring with hex RGB
- **Background highlighting** - Colored backgrounds for emphasis
- **Clickable links** - URL links with hover effects and click detection
- **Word wrapping** - Automatic line wrapping within bounds
- **Nested styles** - Tags can be combined and nested
- **Auto-layout** - Both manual positioning and cursor-based placement

## Usage

### Basic Rich Text

```zig
const ui = @import("AgentiteZ").ui;

// Simple formatted text
_ = ui.richText(ctx, "intro_text", rect,
    "Welcome to [b]AgentiteZ[/b]! This is [i]italic[/i] and [u]underlined[/u] text.",
    .{},
);

// Or use auto-layout
_ = ui.richTextAuto(ctx, "intro_text", 400,
    "Welcome to [b]AgentiteZ[/b]!",
    .{},
);
```

### Colored Text

```zig
// Custom text colors
_ = ui.richText(ctx, "colored", rect,
    "[c=#FF0000]Red[/c], [c=#00FF00]Green[/c], [c=#0000FF]Blue[/c]",
    .{},
);

// Background highlighting
_ = ui.richText(ctx, "highlighted", rect,
    "This is [bg=#FFFF00]highlighted[/bg] text.",
    .{},
);
```

### Clickable Links

```zig
// Links return the clicked URL (or null if not clicked)
if (ui.richText(ctx, "link_text", rect,
    "Visit [link=https://example.com]our website[/link] for more info.",
    .{},
)) |clicked_url| {
    // Handle link click
    openUrl(clicked_url);
}
```

### Nested Styles

```zig
// Styles can be combined
_ = ui.richText(ctx, "nested", rect,
    "[b]Bold and [i]also italic[/i][/b] text",
    .{},
);

// Multiple styles on same text
_ = ui.richText(ctx, "combined", rect,
    "[b][u][c=#FF6600]Bold, underlined, orange[/c][/u][/b]",
    .{},
);
```

### Word Wrapping

```zig
// Enable wrapping within a width
_ = ui.richText(ctx, "wrapped", rect,
    "This is a longer text that will [b]automatically wrap[/b] to multiple lines when it exceeds the maximum width.",
    .{
        .wrap = true,
        .max_width = 300,
    },
);
```

## Markup Syntax

| Tag | Description | Example |
|-----|-------------|---------|
| `[b]...[/b]` | Bold text | `[b]bold[/b]` |
| `[i]...[/i]` | Italic text | `[i]italic[/i]` |
| `[u]...[/u]` | Underline | `[u]underlined[/u]` |
| `[c=#RRGGBB]...[/c]` | Text color (hex RGB) | `[c=#FF0000]red[/c]` |
| `[bg=#RRGGBB]...[/bg]` | Background color | `[bg=#FFFF00]highlight[/bg]` |
| `[link=url]...[/link]` | Clickable link | `[link=https://example.com]click[/link]` |

## Data Structures

### TextStyle

Style flags for text spans:

```zig
pub const TextStyle = struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    color: ?Color = null,
    bg_color: ?Color = null,
    link_index: ?usize = null,
};
```

### TextSpan

A segment of text with its style:

```zig
pub const TextSpan = struct {
    text: []const u8,
    style: TextStyle,
};
```

### RichTextOptions

Configuration options:

```zig
pub const RichTextOptions = struct {
    base_color: ?Color = null,       // Default text color
    link_color: ?Color = null,       // Link text color
    link_hover_color: ?Color = null, // Link hover color
    wrap: bool = true,               // Enable word wrapping
    max_width: f32 = 0,              // Max width (0 = rect width)
    line_height_mult: f32 = 1.2,     // Line height multiplier
};
```

## Programmatic Parsing

For advanced use cases, you can parse markup separately:

```zig
const parsed = ui.parseMarkup("[b]Hello[/b] world");

// Access spans
for (parsed.spans) |span| {
    std.debug.print("Text: {s}, Bold: {}\n", .{
        span.text,
        span.style.bold,
    });
}
```

## Style Effects

Since the font atlas typically contains only one font face:

- **Bold** - Rendered as slightly brightened text
- **Italic** - Rendered with a subtle blue tint
- **Underline** - Drawn as a 1px line below text
- **Links** - Underlined by default, blue color, lighter on hover

## Default Colors

| Style | Color | RGB |
|-------|-------|-----|
| Link | Cornflower Blue | (100, 149, 237) |
| Link Hover | Light Sky Blue | (135, 206, 250) |

## Limits

- Maximum 128 spans per widget
- Maximum 32 links per widget
- Maximum 256 characters per URL

## API Reference

### Rich Text Functions

```zig
/// Render rich text in a specified rectangle
/// Returns: clicked link URL, or null
fn richText(
    ctx: *Context,
    label: []const u8,
    rect: Rect,
    markup: []const u8,
    options: RichTextOptions,
) ?[]const u8

/// Render rich text with auto-layout (cursor-based positioning)
/// Returns: clicked link URL, or null
fn richTextAuto(
    ctx: *Context,
    label: []const u8,
    width: f32,
    markup: []const u8,
    options: RichTextOptions,
) ?[]const u8

/// Parse markup into spans (for advanced use)
fn parseMarkup(text: []const u8) ParsedRichText
```

## Tests

9 tests covering simple text, bold/italic/underline, nested tags, colors, links, background colors, color parsing, invalid tags, and style combinations.
