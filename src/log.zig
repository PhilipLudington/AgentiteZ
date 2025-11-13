const std = @import("std");

/// Log levels for filtering messages
pub const LogLevel = enum(u8) {
    err = 0,   // Critical errors that prevent operation
    warn = 1,  // Warnings about potential issues
    info = 2,  // Informational messages about normal operation
    debug = 3, // Debug information for development
    trace = 4, // Verbose tracing for detailed debugging

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .err => "ERROR",
            .warn => "WARN ",
            .info => "INFO ",
            .debug => "DEBUG",
            .trace => "TRACE",
        };
    }

    pub fn toColor(self: LogLevel) []const u8 {
        return switch (self) {
            .err => "\x1b[31m",   // Red
            .warn => "\x1b[33m",  // Yellow
            .info => "\x1b[32m",  // Green
            .debug => "\x1b[36m", // Cyan
            .trace => "\x1b[37m", // White
        };
    }
};

/// Global log level - can be set at runtime
/// In release builds, only err/warn/info are available
var global_log_level: LogLevel = if (@import("builtin").mode == .Debug) .debug else .info;

/// Set the global log level
pub fn setLogLevel(level: LogLevel) void {
    global_log_level = level;
}

/// Get the current log level
pub fn getLogLevel() LogLevel {
    return global_log_level;
}

/// Check if a log level is enabled
pub inline fn isEnabled(level: LogLevel) bool {
    return @intFromEnum(level) <= @intFromEnum(global_log_level);
}

/// Log an error message (always compiled in)
pub fn err(comptime category: []const u8, comptime fmt: []const u8, args: anytype) void {
    logInternal(.err, category, fmt, args);
}

/// Log a warning message (always compiled in)
pub fn warn(comptime category: []const u8, comptime fmt: []const u8, args: anytype) void {
    logInternal(.warn, category, fmt, args);
}

/// Log an info message (always compiled in)
pub fn info(comptime category: []const u8, comptime fmt: []const u8, args: anytype) void {
    logInternal(.info, category, fmt, args);
}

/// Log a debug message (compiled out in release builds)
pub fn debug(comptime category: []const u8, comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").mode == .Debug) {
        logInternal(.debug, category, fmt, args);
    }
}

/// Log a trace message (compiled out in release builds)
pub fn trace(comptime category: []const u8, comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").mode == .Debug) {
        logInternal(.trace, category, fmt, args);
    }
}

/// Internal logging function
fn logInternal(comptime level: LogLevel, comptime category: []const u8, comptime fmt: []const u8, args: anytype) void {
    // Check if this log level is enabled
    if (!isEnabled(level)) return;

    // Get timestamp
    const timestamp = std.time.milliTimestamp();
    const seconds = @divTrunc(timestamp, 1000);
    const millis = @mod(timestamp, 1000);

    // Format: [LEVEL] [Category] Message
    const color_start = level.toColor();
    const color_end = "\x1b[0m";

    // Thread-safe mutex for logging
    const log_mutex = struct {
        var mutex: std.Thread.Mutex = .{};
    };

    log_mutex.mutex.lock();
    defer log_mutex.mutex.unlock();

    // Write log message with color using std.debug.print
    std.debug.print("{s}[{s}]{s} ", .{ color_start, level.toString(), color_end });
    std.debug.print("[{s}] ", .{category});
    std.debug.print(fmt, args);
    std.debug.print(" ({d}.{d:0>3}s)\n", .{ seconds, millis });
}

// Convenience functions for common categories

/// Renderer logging
pub const renderer = struct {
    pub fn err(comptime fmt: []const u8, args: anytype) void {
        logInternal(.err, "Renderer", fmt, args);
    }
    pub fn warn(comptime fmt: []const u8, args: anytype) void {
        logInternal(.warn, "Renderer", fmt, args);
    }
    pub fn info(comptime fmt: []const u8, args: anytype) void {
        logInternal(.info, "Renderer", fmt, args);
    }
    pub fn debug(comptime fmt: []const u8, args: anytype) void {
        if (@import("builtin").mode == .Debug) {
            logInternal(.debug, "Renderer", fmt, args);
        }
    }
    pub fn trace(comptime fmt: []const u8, args: anytype) void {
        if (@import("builtin").mode == .Debug) {
            logInternal(.trace, "Renderer", fmt, args);
        }
    }
};

/// UI logging
pub const ui = struct {
    pub fn err(comptime fmt: []const u8, args: anytype) void {
        logInternal(.err, "UI", fmt, args);
    }
    pub fn warn(comptime fmt: []const u8, args: anytype) void {
        logInternal(.warn, "UI", fmt, args);
    }
    pub fn info(comptime fmt: []const u8, args: anytype) void {
        logInternal(.info, "UI", fmt, args);
    }
    pub fn debug(comptime fmt: []const u8, args: anytype) void {
        if (@import("builtin").mode == .Debug) {
            logInternal(.debug, "UI", fmt, args);
        }
    }
    pub fn trace(comptime fmt: []const u8, args: anytype) void {
        if (@import("builtin").mode == .Debug) {
            logInternal(.trace, "UI", fmt, args);
        }
    }
};

/// Input logging
pub const input = struct {
    pub fn err(comptime fmt: []const u8, args: anytype) void {
        logInternal(.err, "Input", fmt, args);
    }
    pub fn warn(comptime fmt: []const u8, args: anytype) void {
        logInternal(.warn, "Input", fmt, args);
    }
    pub fn info(comptime fmt: []const u8, args: anytype) void {
        logInternal(.info, "Input", fmt, args);
    }
    pub fn debug(comptime fmt: []const u8, args: anytype) void {
        if (@import("builtin").mode == .Debug) {
            logInternal(.debug, "Input", fmt, args);
        }
    }
    pub fn trace(comptime fmt: []const u8, args: anytype) void {
        if (@import("builtin").mode == .Debug) {
            logInternal(.trace, "Input", fmt, args);
        }
    }
};

/// Font logging
pub const font = struct {
    pub fn err(comptime fmt: []const u8, args: anytype) void {
        logInternal(.err, "Font", fmt, args);
    }
    pub fn warn(comptime fmt: []const u8, args: anytype) void {
        logInternal(.warn, "Font", fmt, args);
    }
    pub fn info(comptime fmt: []const u8, args: anytype) void {
        logInternal(.info, "Font", fmt, args);
    }
    pub fn debug(comptime fmt: []const u8, args: anytype) void {
        if (@import("builtin").mode == .Debug) {
            logInternal(.debug, "Font", fmt, args);
        }
    }
    pub fn trace(comptime fmt: []const u8, args: anytype) void {
        if (@import("builtin").mode == .Debug) {
            logInternal(.trace, "Font", fmt, args);
        }
    }
};

test "log - levels" {
    // Test that log levels are ordered correctly
    try std.testing.expect(@intFromEnum(LogLevel.err) < @intFromEnum(LogLevel.warn));
    try std.testing.expect(@intFromEnum(LogLevel.warn) < @intFromEnum(LogLevel.info));
    try std.testing.expect(@intFromEnum(LogLevel.info) < @intFromEnum(LogLevel.debug));
    try std.testing.expect(@intFromEnum(LogLevel.debug) < @intFromEnum(LogLevel.trace));
}

test "log - level filtering" {
    // Set to info level
    setLogLevel(.info);

    try std.testing.expect(isEnabled(.err));
    try std.testing.expect(isEnabled(.warn));
    try std.testing.expect(isEnabled(.info));
    try std.testing.expect(!isEnabled(.debug));
    try std.testing.expect(!isEnabled(.trace));

    // Set to debug level
    setLogLevel(.debug);

    try std.testing.expect(isEnabled(.err));
    try std.testing.expect(isEnabled(.warn));
    try std.testing.expect(isEnabled(.info));
    try std.testing.expect(isEnabled(.debug));
    try std.testing.expect(!isEnabled(.trace));
}

test "log - basic logging" {
    // These should not crash
    setLogLevel(.trace);

    err("Test", "Error message: {}", .{42});
    warn("Test", "Warning message: {s}", .{"test"});
    info("Test", "Info message", .{});
    debug("Test", "Debug message", .{});
    trace("Test", "Trace message", .{});

    // Test convenience functions
    renderer.info("Renderer initialized", .{});
    ui.debug("Widget count: {}", .{10});
}
