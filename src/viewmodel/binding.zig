//! Widget binding helpers for two-way data binding.
//!
//! These functions connect Observable properties to UI widgets, enabling
//! automatic synchronization between data and UI.
//!
//! ## Example
//! ```zig
//! var settings = SettingsViewModel.init(allocator);
//! defer settings.deinit();
//!
//! // Two-way binding: slider updates observable, observable value shown in slider
//! Binding.sliderFloatAuto(ctx, "Volume", 300, &settings.volume, 0, 1);
//!
//! // Two-way binding: checkbox toggles observable
//! Binding.checkboxBoolAuto(ctx, "Mute", &settings.muted);
//! ```

const std = @import("std");
const observable = @import("observable.zig");
const computed = @import("computed.zig");
const Observable = observable.Observable;
const Computed = computed.Computed;

// Import UI types - these are the public interface types from the UI module
const ui_widgets = @import("../ui/widgets.zig");
const ui_types = @import("../ui/types.zig");

const Context = ui_widgets.Context;
const Rect = ui_types.Rect;
const Vec2 = ui_types.Vec2;
const Color = ui_types.Color;

/// Widget bindings for connecting observables to UI widgets.
/// Follows existing immediate-mode pattern with optional data binding.
pub const Binding = struct {
    // =========================================================================
    // Slider Bindings
    // =========================================================================

    /// Two-way bind a float observable to a slider widget.
    /// The slider displays the observable's current value and updates it when dragged.
    pub fn sliderFloat(
        ctx: *Context,
        label_text: []const u8,
        rect: Rect,
        obs: *Observable(f32),
        min_val: f32,
        max_val: f32,
    ) void {
        const current = obs.get();
        const new_value = ui_widgets.slider(ctx, label_text, rect, current, min_val, max_val);

        // Two-way: update observable if slider changed
        if (@abs(new_value - current) > 0.0001) {
            obs.set(new_value);
        }
    }

    /// Auto-layout version of sliderFloat
    pub fn sliderFloatAuto(
        ctx: *Context,
        label_text: []const u8,
        width: f32,
        obs: *Observable(f32),
        min_val: f32,
        max_val: f32,
    ) void {
        const current = obs.get();
        const new_value = ui_widgets.sliderAuto(ctx, label_text, width, current, min_val, max_val);

        if (@abs(new_value - current) > 0.0001) {
            obs.set(new_value);
        }
    }

    /// One-way display of a computed float as a slider (read-only visual)
    pub fn sliderFloatComputed(
        ctx: *Context,
        label_text: []const u8,
        rect: Rect,
        comp: *const Computed(f32),
        min_val: f32,
        max_val: f32,
    ) void {
        const value = comp.get();
        // Display only - ignore return value since computed properties are read-only
        _ = ui_widgets.slider(ctx, label_text, rect, value, min_val, max_val);
    }

    // =========================================================================
    // Checkbox Bindings
    // =========================================================================

    /// Two-way bind a bool observable to a checkbox widget.
    /// The checkbox displays the observable's current value and updates it when clicked.
    /// Returns true if the value was changed.
    pub fn checkboxBool(
        ctx: *Context,
        label_text: []const u8,
        rect: Rect,
        obs: *Observable(bool),
    ) bool {
        var value = obs.get();
        const changed = ui_widgets.checkbox(ctx, label_text, rect, &value);

        if (changed) {
            obs.set(value);
        }

        return changed;
    }

    /// Auto-layout version of checkboxBool
    pub fn checkboxBoolAuto(
        ctx: *Context,
        label_text: []const u8,
        obs: *Observable(bool),
    ) bool {
        var value = obs.get();
        const changed = ui_widgets.checkboxAuto(ctx, label_text, &value);

        if (changed) {
            obs.set(value);
        }

        return changed;
    }

    // =========================================================================
    // Text Input Bindings
    // =========================================================================

    /// State needed for text input binding (must be persisted by caller)
    pub const TextInputState = struct {
        buffer: [256]u8 = undefined,
        buffer_len: usize = 0,
        last_obs_value: []const u8 = "",

        /// Sync buffer from observable value
        pub fn syncFromObservable(self: *TextInputState, obs_value: []const u8) void {
            const len = @min(obs_value.len, self.buffer.len);
            @memcpy(self.buffer[0..len], obs_value[0..len]);
            self.buffer_len = len;
            self.last_obs_value = obs_value;
        }
    };

    /// Two-way bind a string observable to a text input widget.
    /// Requires a TextInputState to manage the buffer.
    ///
    /// Note: String observables store []const u8, so the binding maintains
    /// a mutable buffer for editing. Changes are synced back to the observable
    /// after each edit.
    pub fn textInputString(
        ctx: *Context,
        label_text: []const u8,
        rect: Rect,
        obs: *Observable([]const u8),
        state: *TextInputState,
    ) void {
        const current = obs.get();

        // Sync from observable if it changed externally
        if (!std.mem.eql(u8, current, state.last_obs_value)) {
            state.syncFromObservable(current);
        }

        const prev_len = state.buffer_len;
        ui_widgets.textInput(ctx, label_text, rect, &state.buffer, &state.buffer_len);

        // Update observable if buffer changed
        if (state.buffer_len != prev_len or
            !std.mem.eql(u8, state.buffer[0..state.buffer_len], current))
        {
            obs.set(state.buffer[0..state.buffer_len]);
            state.last_obs_value = state.buffer[0..state.buffer_len];
        }
    }

    /// Auto-layout version of textInputString
    pub fn textInputStringAuto(
        ctx: *Context,
        label_text: []const u8,
        width: f32,
        obs: *Observable([]const u8),
        state: *TextInputState,
    ) void {
        const height: f32 = 30;
        const label_height: f32 = if (label_text.len > 0) 16 else 0;

        const rect = Rect{
            .x = ctx.cursor.x,
            .y = ctx.cursor.y + label_height,
            .width = width,
            .height = height,
        };

        textInputString(ctx, label_text, rect, obs, state);
        ctx.advanceCursor(height + label_height, 5);
    }

    // =========================================================================
    // Integer Bindings
    // =========================================================================

    /// Two-way bind an integer observable to a slider widget.
    /// The value is converted to/from float for the slider.
    pub fn sliderInt(
        ctx: *Context,
        label_text: []const u8,
        rect: Rect,
        obs: *Observable(i32),
        min_val: i32,
        max_val: i32,
    ) void {
        const current: f32 = @floatFromInt(obs.get());
        const min_f: f32 = @floatFromInt(min_val);
        const max_f: f32 = @floatFromInt(max_val);

        const new_value = ui_widgets.slider(ctx, label_text, rect, current, min_f, max_f);
        const new_int: i32 = @intFromFloat(@round(new_value));

        if (new_int != obs.get()) {
            obs.set(new_int);
        }
    }

    /// Auto-layout version of sliderInt
    pub fn sliderIntAuto(
        ctx: *Context,
        label_text: []const u8,
        width: f32,
        obs: *Observable(i32),
        min_val: i32,
        max_val: i32,
    ) void {
        const current: f32 = @floatFromInt(obs.get());
        const min_f: f32 = @floatFromInt(min_val);
        const max_f: f32 = @floatFromInt(max_val);

        const new_value = ui_widgets.sliderAuto(ctx, label_text, width, current, min_f, max_f);
        const new_int: i32 = @intFromFloat(@round(new_value));

        if (new_int != obs.get()) {
            obs.set(new_int);
        }
    }

    // =========================================================================
    // Display Helpers (One-Way Binding)
    // =========================================================================

    /// Display a label with an observable float value
    pub fn labelFloat(
        ctx: *Context,
        prefix: []const u8,
        obs: *const Observable(f32),
        pos: Vec2,
        size: f32,
        color: Color,
    ) void {
        var buf: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{s}{d:.2}", .{ prefix, obs.get() }) catch prefix;
        ui_widgets.label(ctx, text, pos, size, color);
    }

    /// Display a label with an observable int value
    pub fn labelInt(
        ctx: *Context,
        prefix: []const u8,
        obs: *const Observable(i32),
        pos: Vec2,
        size: f32,
        color: Color,
    ) void {
        var buf: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{s}{d}", .{ prefix, obs.get() }) catch prefix;
        ui_widgets.label(ctx, text, pos, size, color);
    }

    /// Display a label with a computed float value
    pub fn labelFloatComputed(
        ctx: *Context,
        prefix: []const u8,
        comp: *const Computed(f32),
        pos: Vec2,
        size: f32,
        color: Color,
    ) void {
        var buf: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{s}{d:.2}", .{ prefix, comp.get() }) catch prefix;
        ui_widgets.label(ctx, text, pos, size, color);
    }
};

// ============================================================================
// Tests
// ============================================================================

// Note: Full widget binding tests require a mock Context, which is complex.
// These tests verify the binding logic in isolation where possible.

test "Binding: TextInputState syncFromObservable" {
    var state = Binding.TextInputState{};

    state.syncFromObservable("hello");

    try std.testing.expectEqual(@as(usize, 5), state.buffer_len);
    try std.testing.expectEqualStrings("hello", state.buffer[0..state.buffer_len]);
}

test "Binding: TextInputState handles empty string" {
    var state = Binding.TextInputState{};

    state.syncFromObservable("");

    try std.testing.expectEqual(@as(usize, 0), state.buffer_len);
}

test "Binding: TextInputState truncates long strings" {
    var state = Binding.TextInputState{};

    // Create a string longer than buffer
    var long_string: [300]u8 = undefined;
    @memset(&long_string, 'x');

    state.syncFromObservable(&long_string);

    try std.testing.expectEqual(@as(usize, 256), state.buffer_len);
}
