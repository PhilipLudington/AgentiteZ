// Rich Text Widget - Formatted text display with inline styling and links
// Supports BBCode-style markup: [b], [i], [u], [c=#RRGGBB], [bg=#RRGGBB], [link=url]

const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

/// Maximum spans per rich text widget
pub const max_spans = 128;

/// Maximum links per rich text widget
pub const max_links = 32;

/// Maximum URL length for links
pub const max_url_len = 256;

/// Text style flags
pub const TextStyle = struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    color: ?Color = null,
    bg_color: ?Color = null,
    link_index: ?usize = null, // Index into links array if this is a link

    pub fn withBold(self: TextStyle) TextStyle {
        var copy = self;
        copy.bold = true;
        return copy;
    }

    pub fn withItalic(self: TextStyle) TextStyle {
        var copy = self;
        copy.italic = true;
        return copy;
    }

    pub fn withUnderline(self: TextStyle) TextStyle {
        var copy = self;
        copy.underline = true;
        return copy;
    }

    pub fn withColor(self: TextStyle, color: Color) TextStyle {
        var copy = self;
        copy.color = color;
        return copy;
    }

    pub fn withBgColor(self: TextStyle, color: Color) TextStyle {
        var copy = self;
        copy.bg_color = color;
        return copy;
    }

    pub fn withLink(self: TextStyle, index: usize) TextStyle {
        var copy = self;
        copy.link_index = index;
        copy.underline = true; // Links are underlined by default
        return copy;
    }
};

/// A span of text with associated style
pub const TextSpan = struct {
    text: []const u8,
    style: TextStyle,
};

/// A clickable link region
pub const LinkRegion = struct {
    url: []const u8,
    rect: Rect,
};

/// Parsed rich text result
pub const ParsedRichText = struct {
    spans: []const TextSpan,
    links: []const []const u8,
    span_count: usize,
    link_count: usize,

    // Storage arrays (for static parsing)
    span_storage: [max_spans]TextSpan,
    link_storage: [max_links][max_url_len]u8,
    link_lens: [max_links]usize,
};

/// Rich text options
pub const RichTextOptions = struct {
    /// Base text color (used when no [c=] tag is active)
    base_color: ?Color = null,
    /// Color for links
    link_color: ?Color = null,
    /// Color for links when hovered
    link_hover_color: ?Color = null,
    /// Enable word wrapping
    wrap: bool = true,
    /// Maximum width for wrapping (0 = no limit)
    max_width: f32 = 0,
    /// Line height multiplier
    line_height_mult: f32 = 1.2,
};

/// Link click callback type
pub const LinkCallback = *const fn (url: []const u8) void;

/// Parse BBCode-style markup into spans
/// Supported tags:
///   [b]...[/b]           - Bold
///   [i]...[/i]           - Italic
///   [u]...[/u]           - Underline
///   [c=#RRGGBB]...[/c]   - Text color (hex RGB)
///   [bg=#RRGGBB]...[/bg] - Background color
///   [link=url]...[/link] - Clickable link
pub fn parseMarkup(text: []const u8) ParsedRichText {
    var result = ParsedRichText{
        .spans = &[_]TextSpan{},
        .links = &[_][]const u8{},
        .span_count = 0,
        .link_count = 0,
        .span_storage = undefined,
        .link_storage = undefined,
        .link_lens = undefined,
    };

    var style_stack: [16]TextStyle = undefined;
    var stack_depth: usize = 0;
    style_stack[0] = TextStyle{};

    var pos: usize = 0;
    var span_start: usize = 0;

    while (pos < text.len) {
        if (text[pos] == '[') {
            // Save any text before this tag
            if (pos > span_start) {
                if (result.span_count < max_spans) {
                    result.span_storage[result.span_count] = TextSpan{
                        .text = text[span_start..pos],
                        .style = style_stack[stack_depth],
                    };
                    result.span_count += 1;
                }
            }

            // Parse the tag
            const tag_result = parseTag(text, pos, &style_stack, &stack_depth, &result);
            if (tag_result.valid) {
                pos = tag_result.end_pos;
                span_start = pos;
                continue;
            }
        }
        pos += 1;
    }

    // Save remaining text
    if (pos > span_start) {
        if (result.span_count < max_spans) {
            result.span_storage[result.span_count] = TextSpan{
                .text = text[span_start..pos],
                .style = style_stack[stack_depth],
            };
            result.span_count += 1;
        }
    }

    // Set up slices
    result.spans = result.span_storage[0..result.span_count];

    return result;
}

const TagResult = struct {
    valid: bool,
    end_pos: usize,
};

fn parseTag(
    text: []const u8,
    start: usize,
    style_stack: *[16]TextStyle,
    stack_depth: *usize,
    result: *ParsedRichText,
) TagResult {
    // Find closing bracket
    var end = start + 1;
    while (end < text.len and text[end] != ']') {
        end += 1;
    }
    if (end >= text.len) {
        return .{ .valid = false, .end_pos = start };
    }

    const tag_content = text[start + 1 .. end];
    const tag_end = end + 1;

    // Check for closing tags first
    if (tag_content.len > 0 and tag_content[0] == '/') {
        const close_tag = tag_content[1..];
        if (std.mem.eql(u8, close_tag, "b") or
            std.mem.eql(u8, close_tag, "i") or
            std.mem.eql(u8, close_tag, "u") or
            std.mem.eql(u8, close_tag, "c") or
            std.mem.eql(u8, close_tag, "bg") or
            std.mem.eql(u8, close_tag, "link"))
        {
            if (stack_depth.* > 0) {
                stack_depth.* -= 1;
            }
            return .{ .valid = true, .end_pos = tag_end };
        }
        return .{ .valid = false, .end_pos = start };
    }

    // Opening tags
    var new_style = style_stack[stack_depth.*];

    if (std.mem.eql(u8, tag_content, "b")) {
        new_style = new_style.withBold();
    } else if (std.mem.eql(u8, tag_content, "i")) {
        new_style = new_style.withItalic();
    } else if (std.mem.eql(u8, tag_content, "u")) {
        new_style = new_style.withUnderline();
    } else if (std.mem.startsWith(u8, tag_content, "c=")) {
        const color_str = tag_content[2..];
        if (parseColor(color_str)) |color| {
            new_style = new_style.withColor(color);
        }
    } else if (std.mem.startsWith(u8, tag_content, "bg=")) {
        const color_str = tag_content[3..];
        if (parseColor(color_str)) |color| {
            new_style = new_style.withBgColor(color);
        }
    } else if (std.mem.startsWith(u8, tag_content, "link=")) {
        const url = tag_content[5..];
        if (result.link_count < max_links and url.len < max_url_len) {
            // Store the URL
            const len = @min(url.len, max_url_len);
            @memcpy(result.link_storage[result.link_count][0..len], url[0..len]);
            result.link_lens[result.link_count] = len;
            new_style = new_style.withLink(result.link_count);
            result.link_count += 1;
        }
    } else {
        return .{ .valid = false, .end_pos = start };
    }

    // Push new style onto stack
    if (stack_depth.* < 15) {
        stack_depth.* += 1;
        style_stack[stack_depth.*] = new_style;
    }

    return .{ .valid = true, .end_pos = tag_end };
}

/// Parse a color from hex string (with or without #)
fn parseColor(str: []const u8) ?Color {
    var hex = str;
    if (hex.len > 0 and hex[0] == '#') {
        hex = hex[1..];
    }

    if (hex.len == 6) {
        const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return null;
        const g = std.fmt.parseInt(u8, hex[2..4], 16) catch return null;
        const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return null;
        return Color.rgb(r, g, b);
    }

    return null;
}

/// Render rich text at a position
pub fn richText(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    markup: []const u8,
    options: RichTextOptions,
) ?[]const u8 {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    const parsed = parseMarkup(markup);
    return renderParsedRichText(ctx, rect, parsed, options);
}

/// Render rich text with automatic layout
pub fn richTextAuto(
    ctx: *Context,
    label_text: []const u8,
    width: f32,
    markup: []const u8,
    options: RichTextOptions,
) ?[]const u8 {
    // Measure height first
    const parsed = parseMarkup(markup);
    var opts = options;
    opts.max_width = width;
    const height = measureRichTextHeight(ctx, parsed, opts);

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height,
    };

    const result = richText(ctx, label_text, rect, markup, opts);
    ctx.advanceCursor(height, ctx.theme.widget_spacing);

    return result;
}

/// Measure the height needed to render rich text
fn measureRichTextHeight(ctx: *Context, parsed: ParsedRichText, options: RichTextOptions) f32 {
    const font_size = ctx.theme.font_size_normal;
    const line_height = font_size * options.line_height_mult;

    if (!options.wrap or options.max_width <= 0) {
        // Single line
        return line_height;
    }

    // Calculate wrapped height
    var current_x: f32 = 0;
    var lines: f32 = 1;
    const max_width = options.max_width;

    for (parsed.spans) |span| {
        var word_start: usize = 0;
        var i: usize = 0;

        while (i <= span.text.len) {
            const is_space = i < span.text.len and span.text[i] == ' ';
            const is_end = i == span.text.len;

            if (is_space or is_end) {
                if (i > word_start) {
                    const word = span.text[word_start..i];
                    const word_width = ctx.renderer.measureText(word, font_size).x;

                    if (current_x + word_width > max_width and current_x > 0) {
                        lines += 1;
                        current_x = 0;
                    }
                    current_x += word_width;
                }

                if (is_space) {
                    const space_width = ctx.renderer.measureText(" ", font_size).x;
                    current_x += space_width;
                    word_start = i + 1;
                }
            }
            i += 1;
        }
    }

    return lines * line_height;
}

/// Internal render function for parsed rich text
fn renderParsedRichText(
    ctx: *Context,
    rect: Rect,
    parsed: ParsedRichText,
    options: RichTextOptions,
) ?[]const u8 {
    const font_size = ctx.theme.font_size_normal;
    const line_height = font_size * options.line_height_mult;
    const base_color = options.base_color orelse ctx.theme.text_primary;
    const link_color = options.link_color orelse Color.rgb(100, 149, 237); // Cornflower blue
    const link_hover_color = options.link_hover_color orelse Color.rgb(135, 206, 250); // Light sky blue

    var current_x = rect.x;
    var current_y = rect.y;
    const max_width = if (options.wrap and options.max_width > 0) options.max_width else rect.width;
    var clicked_link: ?[]const u8 = null;

    // Track link regions for click detection
    var link_regions: [max_links]Rect = undefined;
    var link_region_urls: [max_links][]const u8 = undefined;
    var link_region_count: usize = 0;

    for (parsed.spans) |span| {
        const style = span.style;

        // Determine text color
        var text_color = style.color orelse base_color;
        if (style.link_index != null) {
            text_color = link_color;
        }

        // Apply bold effect (brighten color slightly)
        if (style.bold) {
            text_color = text_color.lighten(0.15);
        }

        // Apply italic effect (slight color shift - blue tint)
        if (style.italic) {
            text_color = Color.rgb(
                text_color.r,
                @min(255, text_color.g + 10),
                @min(255, text_color.b + 20),
            );
        }

        if (options.wrap and max_width > 0) {
            // Word wrapping mode
            var word_start: usize = 0;
            var i: usize = 0;

            while (i <= span.text.len) {
                const is_space = i < span.text.len and span.text[i] == ' ';
                const is_end = i == span.text.len;

                if (is_space or is_end) {
                    if (i > word_start) {
                        const word = span.text[word_start..i];
                        const word_bounds = ctx.renderer.measureText(word, font_size);

                        // Check for line wrap
                        if (current_x - rect.x + word_bounds.x > max_width and current_x > rect.x) {
                            current_x = rect.x;
                            current_y += line_height;
                        }

                        // Draw background if specified
                        if (style.bg_color) |bg| {
                            ctx.renderer.drawRect(Rect{
                                .x = current_x,
                                .y = current_y,
                                .width = word_bounds.x,
                                .height = font_size,
                            }, bg);
                        }

                        // Draw text
                        ctx.renderer.drawText(word, Vec2{ .x = current_x, .y = current_y }, font_size, text_color);

                        // Draw underline
                        if (style.underline) {
                            ctx.renderer.drawRect(Rect{
                                .x = current_x,
                                .y = current_y + font_size - 2,
                                .width = word_bounds.x,
                                .height = 1,
                            }, text_color);
                        }

                        // Track link region
                        if (style.link_index) |link_idx| {
                            if (link_region_count < max_links and link_idx < parsed.link_count) {
                                const url = parsed.link_storage[link_idx][0..parsed.link_lens[link_idx]];
                                link_regions[link_region_count] = Rect{
                                    .x = current_x,
                                    .y = current_y,
                                    .width = word_bounds.x,
                                    .height = font_size,
                                };
                                link_region_urls[link_region_count] = url;
                                link_region_count += 1;
                            }
                        }

                        current_x += word_bounds.x;
                    }

                    // Add space width
                    if (is_space) {
                        const space_width = ctx.renderer.measureText(" ", font_size).x;
                        current_x += space_width;
                        word_start = i + 1;
                    }
                }
                i += 1;
            }
        } else {
            // No wrapping - render entire span
            const span_bounds = ctx.renderer.measureText(span.text, font_size);

            // Draw background if specified
            if (style.bg_color) |bg| {
                ctx.renderer.drawRect(Rect{
                    .x = current_x,
                    .y = current_y,
                    .width = span_bounds.x,
                    .height = font_size,
                }, bg);
            }

            // Draw text
            ctx.renderer.drawText(span.text, Vec2{ .x = current_x, .y = current_y }, font_size, text_color);

            // Draw underline
            if (style.underline) {
                ctx.renderer.drawRect(Rect{
                    .x = current_x,
                    .y = current_y + font_size - 2,
                    .width = span_bounds.x,
                    .height = 1,
                }, text_color);
            }

            // Track link region
            if (style.link_index) |link_idx| {
                if (link_region_count < max_links and link_idx < parsed.link_count) {
                    const url = parsed.link_storage[link_idx][0..parsed.link_lens[link_idx]];
                    link_regions[link_region_count] = Rect{
                        .x = current_x,
                        .y = current_y,
                        .width = span_bounds.x,
                        .height = font_size,
                    };
                    link_region_urls[link_region_count] = url;
                    link_region_count += 1;
                }
            }

            current_x += span_bounds.x;
        }
    }

    // Check for link clicks
    const mouse_pos = ctx.input.mouse_pos;
    for (0..link_region_count) |i| {
        const region = link_regions[i];
        if (region.contains(mouse_pos)) {
            // Hover effect - redraw with hover color
            const hover_rect = Rect{
                .x = region.x,
                .y = region.y + font_size - 2,
                .width = region.width,
                .height = 1,
            };
            ctx.renderer.drawRect(hover_rect, link_hover_color);

            if (ctx.input.mouse_clicked) {
                clicked_link = link_region_urls[i];
            }
        }
    }

    return clicked_link;
}

// ============================================================================
// Tests
// ============================================================================

test "rich_text - parse simple text" {
    const parsed = parseMarkup("Hello, world!");
    try std.testing.expectEqual(@as(usize, 1), parsed.span_count);
    try std.testing.expectEqualStrings("Hello, world!", parsed.spans[0].text);
    try std.testing.expect(!parsed.spans[0].style.bold);
}

test "rich_text - parse bold" {
    const parsed = parseMarkup("Hello [b]bold[/b] world");
    try std.testing.expectEqual(@as(usize, 3), parsed.span_count);
    try std.testing.expectEqualStrings("Hello ", parsed.spans[0].text);
    try std.testing.expect(!parsed.spans[0].style.bold);
    try std.testing.expectEqualStrings("bold", parsed.spans[1].text);
    try std.testing.expect(parsed.spans[1].style.bold);
    try std.testing.expectEqualStrings(" world", parsed.spans[2].text);
    try std.testing.expect(!parsed.spans[2].style.bold);
}

test "rich_text - parse nested tags" {
    const parsed = parseMarkup("[b]bold [i]bold-italic[/i][/b]");
    try std.testing.expectEqual(@as(usize, 2), parsed.span_count);
    try std.testing.expectEqualStrings("bold ", parsed.spans[0].text);
    try std.testing.expect(parsed.spans[0].style.bold);
    try std.testing.expect(!parsed.spans[0].style.italic);
    try std.testing.expectEqualStrings("bold-italic", parsed.spans[1].text);
    try std.testing.expect(parsed.spans[1].style.bold);
    try std.testing.expect(parsed.spans[1].style.italic);
}

test "rich_text - parse color" {
    const parsed = parseMarkup("[c=#FF0000]red[/c]");
    try std.testing.expectEqual(@as(usize, 1), parsed.span_count);
    try std.testing.expectEqualStrings("red", parsed.spans[0].text);
    const color = parsed.spans[0].style.color.?;
    try std.testing.expectEqual(@as(u8, 255), color.r);
    try std.testing.expectEqual(@as(u8, 0), color.g);
    try std.testing.expectEqual(@as(u8, 0), color.b);
}

test "rich_text - parse link" {
    const parsed = parseMarkup("[link=https://example.com]click here[/link]");
    try std.testing.expectEqual(@as(usize, 1), parsed.span_count);
    try std.testing.expectEqualStrings("click here", parsed.spans[0].text);
    try std.testing.expect(parsed.spans[0].style.link_index != null);
    try std.testing.expect(parsed.spans[0].style.underline); // Links are underlined
    try std.testing.expectEqual(@as(usize, 1), parsed.link_count);
    const url = parsed.link_storage[0][0..parsed.link_lens[0]];
    try std.testing.expectEqualStrings("https://example.com", url);
}

test "rich_text - parse background color" {
    const parsed = parseMarkup("[bg=#FFFF00]highlighted[/bg]");
    try std.testing.expectEqual(@as(usize, 1), parsed.span_count);
    const bg = parsed.spans[0].style.bg_color.?;
    try std.testing.expectEqual(@as(u8, 255), bg.r);
    try std.testing.expectEqual(@as(u8, 255), bg.g);
    try std.testing.expectEqual(@as(u8, 0), bg.b);
}

test "rich_text - parse color helper" {
    // With hash
    const c1 = parseColor("#FF00FF").?;
    try std.testing.expectEqual(@as(u8, 255), c1.r);
    try std.testing.expectEqual(@as(u8, 0), c1.g);
    try std.testing.expectEqual(@as(u8, 255), c1.b);

    // Without hash
    const c2 = parseColor("00FF00").?;
    try std.testing.expectEqual(@as(u8, 0), c2.r);
    try std.testing.expectEqual(@as(u8, 255), c2.g);
    try std.testing.expectEqual(@as(u8, 0), c2.b);

    // Invalid
    try std.testing.expect(parseColor("invalid") == null);
    try std.testing.expect(parseColor("FFF") == null);
}

test "rich_text - invalid tags preserved" {
    const parsed = parseMarkup("Hello [invalid]tag world");
    // Invalid tag should be preserved as text
    try std.testing.expectEqual(@as(usize, 1), parsed.span_count);
    try std.testing.expectEqualStrings("Hello [invalid]tag world", parsed.spans[0].text);
}

test "rich_text - underline" {
    const parsed = parseMarkup("[u]underlined[/u]");
    try std.testing.expectEqual(@as(usize, 1), parsed.span_count);
    try std.testing.expect(parsed.spans[0].style.underline);
}
