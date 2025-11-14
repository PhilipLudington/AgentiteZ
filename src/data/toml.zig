// toml.zig
// Generic TOML parsing utilities for the engine
// Provides helper functions for parsing TOML values without external dependencies

const std = @import("std");

// ============================================================================
// TOML Value Parsing Utilities
// ============================================================================

/// Parse string to u32
pub fn parseU32(value: []const u8) !u32 {
    return try std.fmt.parseInt(u32, value, 10);
}

/// Parse string to i32
pub fn parseInt32(value: []const u8) !i32 {
    return try std.fmt.parseInt(i32, value, 10);
}

/// Parse string to f32
pub fn parseF32(value: []const u8) !f32 {
    return try std.fmt.parseFloat(f32, value);
}

/// Parse string to u8
pub fn parseU8(value: []const u8) !u8 {
    return try std.fmt.parseInt(u8, value, 10);
}

/// Parse string to bool
pub fn parseBool(value: []const u8) bool {
    return std.mem.eql(u8, value, "true");
}

/// Remove surrounding quotes from string
/// NOTE: This is the simple version that doesn't handle escape sequences.
/// Use unescapeString() for proper escape sequence handling.
pub fn trimQuotes(value: []const u8) []const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return value[1 .. value.len - 1];
    }
    return value;
}

/// Process escape sequences in a TOML string value
/// Handles: \", \\, \n, \t, \r, \b, \f
/// Returns newly allocated string with escape sequences processed
pub fn unescapeString(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    // Remove quotes first
    const trimmed = trimQuotes(value);

    // Quick check if there are any escape sequences
    if (std.mem.indexOf(u8, trimmed, "\\") == null) {
        // No escape sequences, just duplicate the string
        return try allocator.dupe(u8, trimmed);
    }

    // Process escape sequences
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < trimmed.len) {
        if (trimmed[i] == '\\' and i + 1 < trimmed.len) {
            // Process escape sequence
            switch (trimmed[i + 1]) {
                '"' => try result.append(allocator, '"'),
                '\\' => try result.append(allocator, '\\'),
                'n' => try result.append(allocator, '\n'),
                't' => try result.append(allocator, '\t'),
                'r' => try result.append(allocator, '\r'),
                'b' => try result.append(allocator, '\x08'), // backspace
                'f' => try result.append(allocator, '\x0C'), // form feed
                else => {
                    // Unknown escape sequence, keep as-is
                    try result.append(allocator, '\\');
                    try result.append(allocator, trimmed[i + 1]);
                },
            }
            i += 2;
        } else {
            try result.append(allocator, trimmed[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Parse TOML array of u8 values [1, 2, 3] -> ArrayList(u8)
pub fn parseU8Array(allocator: std.mem.Allocator, value: []const u8) !std.ArrayList(u8) {
    var result = std.ArrayList(u8){};

    // Remove brackets
    if (value.len < 2 or value[0] != '[' or value[value.len - 1] != ']') {
        return result;
    }

    const inner = value[1 .. value.len - 1];
    var items = std.mem.splitScalar(u8, inner, ',');

    while (items.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " \t");
        if (trimmed.len > 0) {
            const val = try parseU8(trimmed);
            try result.append(allocator, val);
        }
    }

    return result;
}

/// Parse TOML array of strings ["a", "b", "c"] -> ArrayList([]const u8)
/// Properly handles escaped quotes within strings
pub fn parseStringArray(allocator: std.mem.Allocator, value: []const u8) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8){};

    // Remove brackets
    if (value.len < 2 or value[0] != '[' or value[value.len - 1] != ']') {
        return result;
    }

    const inner = value[1 .. value.len - 1];
    var in_string = false;
    var current_start: usize = 0;
    var i: usize = 0;

    while (i < inner.len) : (i += 1) {
        if (inner[i] == '\\' and in_string and i + 1 < inner.len) {
            // Skip escaped character (including escaped quotes)
            i += 1;
            continue;
        }

        if (inner[i] == '"') {
            if (!in_string) {
                in_string = true;
                current_start = i + 1;
            } else {
                // End of string - process escape sequences
                const str = inner[current_start..i];
                const temp_str = try std.fmt.allocPrint(allocator, "\"{s}\"", .{str});
                defer allocator.free(temp_str);
                const unescaped = try unescapeString(allocator, temp_str);
                try result.append(allocator, unescaped);
                in_string = false;
            }
        }
    }

    return result;
}

// ============================================================================
// TOML File Loading Utilities
// ============================================================================

/// Load TOML file from a list of possible paths
pub fn loadFile(allocator: std.mem.Allocator, paths: []const []const u8, file_description: []const u8) !?[]u8 {
    for (paths) |path| {
        const file = std.fs.cwd().openFile(path, .{}) catch continue;
        defer file.close();

        const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch continue;
        std.debug.print("[TOML] Loaded {s} from: {s}\n", .{ file_description, path });
        return content;
    }

    std.debug.print("[TOML] WARNING: Could not find {s}\n", .{file_description});
    return null;
}

/// Remove inline comments from a line (everything after #)
pub fn removeInlineComment(line: []const u8) []const u8 {
    if (std.mem.indexOf(u8, line, "#")) |comment_idx| {
        return std.mem.trim(u8, line[0..comment_idx], " \t");
    }
    return line;
}

/// Check if a line is a TOML section header like [section] or [[array]]
pub fn isSectionHeader(line: []const u8) bool {
    return line.len > 0 and line[0] == '[';
}

/// Parse key-value pair from TOML line
pub const KeyValue = struct {
    key: []const u8,
    value: []const u8,
};

pub fn parseKeyValue(line: []const u8) ?KeyValue {
    if (std.mem.indexOf(u8, line, "=")) |eq_idx| {
        const key = std.mem.trim(u8, line[0..eq_idx], " \t");
        var value_raw = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");

        // Remove inline comments
        value_raw = removeInlineComment(value_raw);

        return KeyValue{
            .key = key,
            .value = value_raw,
        };
    }
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "parseU32" {
    try std.testing.expectEqual(@as(u32, 42), try parseU32("42"));
    try std.testing.expectEqual(@as(u32, 0), try parseU32("0"));
}

test "parseF32" {
    try std.testing.expectEqual(@as(f32, 3.14), try parseF32("3.14"));
    try std.testing.expectEqual(@as(f32, 0.5), try parseF32("0.5"));
}

test "parseBool" {
    try std.testing.expectEqual(true, parseBool("true"));
    try std.testing.expectEqual(false, parseBool("false"));
}

test "trimQuotes" {
    try std.testing.expectEqualStrings("hello", trimQuotes("\"hello\""));
    try std.testing.expectEqualStrings("hello", trimQuotes("hello"));
}

test "removeInlineComment" {
    try std.testing.expectEqualStrings("value", removeInlineComment("value # comment"));
    try std.testing.expectEqualStrings("value", removeInlineComment("value"));
}

test "parseKeyValue" {
    const kv = parseKeyValue("key = value # comment");
    try std.testing.expect(kv != null);
    try std.testing.expectEqualStrings("key", kv.?.key);
    try std.testing.expectEqualStrings("value", kv.?.value);
}

test "parseU8Array" {
    var arr = try parseU8Array(std.testing.allocator, "[64, 128]");
    defer arr.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), arr.items.len);
    try std.testing.expectEqual(@as(u8, 64), arr.items[0]);
    try std.testing.expectEqual(@as(u8, 128), arr.items[1]);
}

test "parseStringArray" {
    var arr = try parseStringArray(std.testing.allocator, "[\"hello\", \"world\"]");
    defer {
        for (arr.items) |item| {
            std.testing.allocator.free(item);
        }
        arr.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), arr.items.len);
    try std.testing.expectEqualStrings("hello", arr.items[0]);
    try std.testing.expectEqualStrings("world", arr.items[1]);
}

test "unescapeString - no escapes" {
    const result = try unescapeString(std.testing.allocator, "\"hello world\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("hello world", result);
}

test "unescapeString - escaped quote" {
    const result = try unescapeString(std.testing.allocator, "\"She said \\\"hello\\\"\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("She said \"hello\"", result);
}

test "unescapeString - escaped backslash" {
    const result = try unescapeString(std.testing.allocator, "\"C:\\\\path\\\\to\\\\file\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("C:\\path\\to\\file", result);
}

test "unescapeString - newline" {
    const result = try unescapeString(std.testing.allocator, "\"Line 1\\nLine 2\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Line 1\nLine 2", result);
}

test "unescapeString - tab" {
    const result = try unescapeString(std.testing.allocator, "\"Column1\\tColumn2\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Column1\tColumn2", result);
}

test "unescapeString - carriage return" {
    const result = try unescapeString(std.testing.allocator, "\"Line\\rReturn\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Line\rReturn", result);
}

test "unescapeString - backspace" {
    const result = try unescapeString(std.testing.allocator, "\"Hello\\b\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Hello\x08", result);
}

test "unescapeString - form feed" {
    const result = try unescapeString(std.testing.allocator, "\"Page\\fBreak\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Page\x0CBreak", result);
}

test "unescapeString - multiple escapes" {
    const result = try unescapeString(std.testing.allocator, "\"Line 1\\nLine 2\\tTabbed\\\\Backslash\"");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("Line 1\nLine 2\tTabbed\\Backslash", result);
}

test "unescapeString - unknown escape sequence" {
    const result = try unescapeString(std.testing.allocator, "\"Keep\\xUnknown\"");
    defer std.testing.allocator.free(result);
    // Unknown escape sequences are kept as-is
    try std.testing.expectEqualStrings("Keep\\xUnknown", result);
}

test "parseStringArray - with escaped quotes" {
    var arr = try parseStringArray(std.testing.allocator, "[\"Say \\\"hi\\\"\", \"Path: C:\\\\Users\"]");
    defer {
        for (arr.items) |item| {
            std.testing.allocator.free(item);
        }
        arr.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), arr.items.len);
    try std.testing.expectEqualStrings("Say \"hi\"", arr.items[0]);
    try std.testing.expectEqualStrings("Path: C:\\Users", arr.items[1]);
}

test "parseStringArray - with newlines and tabs" {
    var arr = try parseStringArray(std.testing.allocator, "[\"Line1\\nLine2\", \"Col1\\tCol2\"]");
    defer {
        for (arr.items) |item| {
            std.testing.allocator.free(item);
        }
        arr.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), arr.items.len);
    try std.testing.expectEqualStrings("Line1\nLine2", arr.items[0]);
    try std.testing.expectEqualStrings("Col1\tCol2", arr.items[1]);
}
