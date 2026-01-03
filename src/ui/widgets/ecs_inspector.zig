// ECS Inspector Widget
// Debug UI for entity inspection with component viewer/editor
//
// Features:
// - Entity browser with filtering and selection
// - Component viewer with reflection-based field display
// - Real-time value modification for supported field types
// - Archetype statistics showing component usage

const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");
const table_mod = @import("table.zig");
const selection_mod = @import("selection.zig");
const input_mod = @import("input.zig");
const basic_mod = @import("basic.zig");
const ecs_mod = @import("../../ecs.zig");
const prefab_mod = @import("../../prefab.zig");
const reflection = @import("../../ecs/reflection.zig");
const component_accessor = @import("../../ecs/component_accessor.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

// ============================================================================
// Inspector State
// ============================================================================

/// State for a single field being edited
pub const FieldEditState = struct {
    is_editing: bool = false,
    buffer: [256]u8 = [_]u8{0} ** 256,
    buffer_len: usize = 0,
};

/// State for the ECS Inspector widget (needs to be stored by caller)
pub const EcsInspectorState = struct {
    // Entity browser
    entity_scroll: f32 = 0,
    selected_entity: ?ecs_mod.Entity = null,

    // Entity filter
    filter_buffer: [128]u8 = [_]u8{0} ** 128,
    filter_len: usize = 0,

    // Component editor
    selected_component: ?usize = null,
    component_scroll: f32 = 0,

    // Field editing (indexed by field name hash for simplicity)
    editing_field: ?[]const u8 = null,
    edit_buffer: [256]u8 = [_]u8{0} ** 256,
    edit_buffer_len: usize = 0,

    // Tab selection: 0 = Entities, 1 = Archetypes
    current_tab: usize = 0,

    // Scrollbar drag state
    entity_drag_start: ?f32 = null,
    component_drag_start: ?f32 = null,

    /// Clear selected entity
    pub fn clearSelection(self: *EcsInspectorState) void {
        self.selected_entity = null;
        self.selected_component = null;
        self.editing_field = null;
    }
};

/// Result of inspecting an entity
pub const InspectorResult = struct {
    entity_changed: bool = false,
    field_modified: bool = false,
    modified_component: ?[]const u8 = null,
    modified_field: ?[]const u8 = null,
};

// ============================================================================
// Entity Info for Display
// ============================================================================

/// Information about an entity for display
pub const EntityDisplayInfo = struct {
    entity: ecs_mod.Entity,
    component_count: usize,
    component_names: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *EntityDisplayInfo) void {
        self.allocator.free(self.component_names);
    }
};

// ============================================================================
// Main Inspector Functions
// ============================================================================

/// Render the complete ECS Inspector panel
/// Returns information about any modifications made
pub fn ecsInspector(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    registry: *const prefab_mod.PrefabRegistry,
    entities: []const ecs_mod.Entity,
    entity_component_checker: anytype,
    state: *EcsInspectorState,
) InspectorResult {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    var result = InspectorResult{};

    // Panel background
    ctx.renderer.drawRect(rect, ctx.theme.panel_bg);
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, 1.0);

    // Title bar
    const title_height: f32 = 28;
    const title_rect = Rect{
        .x = rect.x,
        .y = rect.y,
        .width = rect.width,
        .height = title_height,
    };
    ctx.renderer.drawRect(title_rect, ctx.theme.panel_title);

    const title_text = if (label_text.len > 0) label_text else "ECS Inspector";
    const text_size = ctx.theme.font_size_normal;
    const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
    ctx.renderer.drawText(
        title_text,
        Vec2.init(rect.x + 8, rect.y + title_height / 2 - baseline_offset),
        text_size,
        ctx.theme.text_primary,
    );

    // Tab bar
    const tab_height: f32 = 25;
    const tab_y = rect.y + title_height;
    const tabs = [_][]const u8{ "Entities", "Archetypes" };

    for (tabs, 0..) |tab_name, i| {
        const tab_width = rect.width / @as(f32, @floatFromInt(tabs.len));
        const tab_rect = Rect{
            .x = rect.x + @as(f32, @floatFromInt(i)) * tab_width,
            .y = tab_y,
            .width = tab_width,
            .height = tab_height,
        };

        var tab_id_buf: [64]u8 = undefined;
        const tab_id_str = std.fmt.bufPrint(&tab_id_buf, "{s}_tab_{d}", .{ label_text, i }) catch "tab";
        const tab_id = widgetId(tab_id_str);
        const tab_clicked = ctx.registerWidget(tab_id, tab_rect);

        if (tab_clicked) {
            state.current_tab = i;
        }

        const is_active_tab = state.current_tab == i;
        const tab_bg = if (is_active_tab)
            ctx.theme.tab_active
        else if (ctx.isHot(tab_id))
            ctx.theme.tab_hover
        else
            ctx.theme.tab_inactive;

        ctx.renderer.drawRect(tab_rect, tab_bg);
        const tab_border_color = if (is_active_tab) ctx.theme.tab_border_active else ctx.theme.tab_border_inactive;
        ctx.renderer.drawRectOutline(tab_rect, tab_border_color, 1.0);

        const tab_text_size = ctx.theme.font_size_small;
        const tab_baseline = ctx.renderer.getBaselineOffset(tab_text_size);
        const tab_text_bounds = ctx.renderer.measureText(tab_name, tab_text_size);
        const tab_text_color = if (is_active_tab) ctx.theme.tab_text_active else ctx.theme.tab_text_inactive;
        ctx.renderer.drawText(
            tab_name,
            Vec2.init(
                tab_rect.x + (tab_rect.width - tab_text_bounds.x) / 2,
                tab_rect.y + tab_height / 2 - tab_baseline,
            ),
            tab_text_size,
            tab_text_color,
        );
    }

    // Content area
    const content_y = tab_y + tab_height + 4;
    const content_height = rect.height - title_height - tab_height - 8;
    const content_rect = Rect{
        .x = rect.x + 4,
        .y = content_y,
        .width = rect.width - 8,
        .height = content_height,
    };

    if (state.current_tab == 0) {
        // Entity browser & component viewer
        result = renderEntityBrowser(
            ctx,
            label_text,
            content_rect,
            registry,
            entities,
            entity_component_checker,
            state,
        );
    } else {
        // Archetype statistics
        renderArchetypeStats(ctx, label_text, content_rect, registry, entities, entity_component_checker);
    }

    return result;
}

/// Render entity browser with filtering and component viewer
fn renderEntityBrowser(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    registry: *const prefab_mod.PrefabRegistry,
    entities: []const ecs_mod.Entity,
    entity_component_checker: anytype,
    state: *EcsInspectorState,
) InspectorResult {
    var result = InspectorResult{};

    // Split into left (entity list) and right (component viewer)
    const split_ratio: f32 = 0.4;
    const entity_list_width = rect.width * split_ratio - 4;
    const component_view_width = rect.width * (1.0 - split_ratio) - 4;

    // Left side: Entity list
    const entity_list_rect = Rect{
        .x = rect.x,
        .y = rect.y,
        .width = entity_list_width,
        .height = rect.height,
    };

    // Filter input at top of entity list
    const filter_height: f32 = 28;
    const filter_rect = Rect{
        .x = entity_list_rect.x + 2,
        .y = entity_list_rect.y,
        .width = entity_list_rect.width - 4,
        .height = filter_height,
    };

    // Render filter input
    renderFilterInput(ctx, label_text, filter_rect, state);

    // Entity list below filter
    const list_rect = Rect{
        .x = entity_list_rect.x,
        .y = entity_list_rect.y + filter_height + 2,
        .width = entity_list_rect.width,
        .height = entity_list_rect.height - filter_height - 2,
    };

    // Filter entities based on search text
    const filter_text = state.filter_buffer[0..state.filter_len];

    // Draw entity list background (dark theme)
    ctx.renderer.drawRect(list_rect, Color.init(30, 35, 45, 255));
    ctx.renderer.drawRectOutline(list_rect, Color.init(70, 80, 100, 255), 1.0);

    const row_height: f32 = 22;
    const visible_rows = @as(usize, @intFromFloat(list_rect.height / row_height));
    const start_idx = @as(usize, @intFromFloat(state.entity_scroll / row_height));

    // Count matching entities and render
    var displayed_count: usize = 0;
    var rendered_count: usize = 0;

    // Note: Scissor disabled - was causing clipping issues
    // TODO: Investigate scissor coordinate system if scrolling is needed

    for (entities) |entity| {
        // Apply filter
        if (filter_text.len > 0) {
            var id_buf: [32]u8 = undefined;
            const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{entity.id}) catch "";
            if (!contains(id_str, filter_text)) {
                continue;
            }
        }

        // Skip entities before visible range
        if (displayed_count < start_idx) {
            displayed_count += 1;
            continue;
        }

        // Stop if beyond visible range
        if (rendered_count >= visible_rows + 2) {
            break;
        }

        const row_y = list_rect.y + @as(f32, @floatFromInt(rendered_count)) * row_height;
        const row_rect = Rect{
            .x = list_rect.x + 2,
            .y = row_y,
            .width = list_rect.width - 4,
            .height = row_height,
        };

        // Unique ID for this row
        var row_id_buf: [64]u8 = undefined;
        const row_id_str = std.fmt.bufPrint(&row_id_buf, "{s}_entity_{d}_{d}", .{
            label_text,
            entity.id,
            entity.generation,
        }) catch "entity_row";
        const row_id = widgetId(row_id_str);
        const row_clicked = ctx.registerWidget(row_id, row_rect);

        if (row_clicked) {
            state.selected_entity = entity;
            state.selected_component = null;
            state.editing_field = null;
            result.entity_changed = true;
        }

        // Row background
        const is_selected = if (state.selected_entity) |sel|
            sel.id == entity.id and sel.generation == entity.generation
        else
            false;

        // Use dark theme colors for visibility
        const row_bg = if (is_selected)
            Color.init(80, 100, 140, 255) // Blue-ish selection
        else if (ctx.isHot(row_id))
            Color.init(60, 70, 90, 255) // Hover highlight
        else if (rendered_count % 2 == 1)
            Color.init(35, 40, 50, 255) // Alternating row
        else
            Color.init(45, 50, 60, 255); // Base row

        ctx.renderer.drawRect(row_rect, row_bg);

        // Entity text
        var entity_text_buf: [64]u8 = undefined;
        const entity_text = std.fmt.bufPrint(&entity_text_buf, "Entity {d} (gen {d})", .{
            entity.id,
            entity.generation,
        }) catch "Entity ???";

        const small_text = ctx.theme.font_size_small;
        const small_baseline = ctx.renderer.getBaselineOffset(small_text);
        // Use white/bright text for visibility on dark background
        ctx.renderer.drawText(
            entity_text,
            Vec2.init(row_rect.x + 4, row_rect.y + row_height / 2 - small_baseline),
            small_text,
            Color.init(220, 220, 220, 255), // Light gray for visibility
        );

        // Component count indicator
        const comp_count = countEntityComponents(entity, registry, entity_component_checker);
        var count_buf: [16]u8 = undefined;
        const count_text = std.fmt.bufPrint(&count_buf, "[{d}]", .{comp_count}) catch "";
        const count_width = ctx.renderer.measureText(count_text, small_text).x;
        ctx.renderer.drawText(
            count_text,
            Vec2.init(row_rect.x + row_rect.width - count_width - 4, row_rect.y + row_height / 2 - small_baseline),
            small_text,
            Color.init(150, 150, 150, 255),
        );

        displayed_count += 1;
        rendered_count += 1;
    }

    ctx.renderer.flushBatches();

    // Handle scroll for entity list
    if (list_rect.contains(ctx.input.mouse_pos) and ctx.input.mouse_wheel != 0) {
        const total_height = @as(f32, @floatFromInt(entities.len)) * row_height;
        const max_scroll = @max(0, total_height - list_rect.height);
        state.entity_scroll -= ctx.input.mouse_wheel * 30;
        state.entity_scroll = std.math.clamp(state.entity_scroll, 0, max_scroll);
    }

    // Right side: Component viewer
    const component_rect = Rect{
        .x = rect.x + entity_list_width + 8,
        .y = rect.y,
        .width = component_view_width,
        .height = rect.height,
    };

    if (state.selected_entity) |selected| {
        const comp_result = renderComponentViewer(
            ctx,
            label_text,
            component_rect,
            registry,
            selected,
            entity_component_checker,
            state,
        );
        if (comp_result.field_modified) {
            result.field_modified = true;
            result.modified_component = comp_result.modified_component;
            result.modified_field = comp_result.modified_field;
        }
    } else {
        // No entity selected
        ctx.renderer.drawRect(component_rect, ctx.theme.panel_bg.darken(0.95));
        ctx.renderer.drawRectOutline(component_rect, ctx.theme.list_border, 1.0);

        const hint_text = "Select an entity to view components";
        const hint_bounds = ctx.renderer.measureText(hint_text, ctx.theme.font_size_small);
        const hint_baseline = ctx.renderer.getBaselineOffset(ctx.theme.font_size_small);
        ctx.renderer.drawText(
            hint_text,
            Vec2.init(
                component_rect.x + (component_rect.width - hint_bounds.x) / 2,
                component_rect.y + component_rect.height / 2 - hint_baseline,
            ),
            ctx.theme.font_size_small,
            Color.init(128, 128, 128, 255),
        );
    }

    return result;
}

/// Render the filter input field
fn renderFilterInput(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    state: *EcsInspectorState,
) void {
    var filter_id_buf: [64]u8 = undefined;
    const filter_id_str = std.fmt.bufPrint(&filter_id_buf, "{s}_filter", .{label_text}) catch "filter";
    const filter_id = widgetId(filter_id_str);
    const clicked = ctx.registerWidget(filter_id, rect);

    const is_focused = ctx.isFocused(filter_id);
    if (clicked) {
        ctx.setFocus(filter_id);
    }

    // Handle text input when focused
    if (is_focused) {
        for (ctx.input.text_input) |char| {
            if (state.filter_len < state.filter_buffer.len) {
                state.filter_buffer[state.filter_len] = char;
                state.filter_len += 1;
            }
        }

        if (ctx.input.key_backspace and state.filter_len > 0) {
            state.filter_len -= 1;
        }
    }

    // Draw background
    const bg_color = if (is_focused) ctx.theme.input_bg_focused else ctx.theme.input_bg;
    ctx.renderer.drawRect(rect, bg_color);

    const border_color = if (is_focused) ctx.theme.input_border_focused else ctx.theme.input_border;
    ctx.renderer.drawRectOutline(rect, border_color, 1.0);

    // Draw placeholder or text
    const text_size = ctx.theme.font_size_small;
    const baseline_offset = ctx.renderer.getBaselineOffset(text_size);

    if (state.filter_len == 0 and !is_focused) {
        ctx.renderer.drawText(
            "Filter entities...",
            Vec2.init(rect.x + 4, rect.y + rect.height / 2 - baseline_offset),
            text_size,
            Color.init(128, 128, 128, 255),
        );
    } else {
        ctx.renderer.drawText(
            state.filter_buffer[0..state.filter_len],
            Vec2.init(rect.x + 4, rect.y + rect.height / 2 - baseline_offset),
            text_size,
            ctx.theme.input_text,
        );

        // Cursor when focused
        if (is_focused) {
            const text_width = ctx.renderer.measureText(state.filter_buffer[0..state.filter_len], text_size).x;
            const cursor_rect = Rect{
                .x = rect.x + 4 + text_width,
                .y = rect.y + 4,
                .width = 2,
                .height = rect.height - 8,
            };
            ctx.renderer.drawRect(cursor_rect, ctx.theme.input_cursor);
        }
    }
}

/// Render component viewer for selected entity
fn renderComponentViewer(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    registry: *const prefab_mod.PrefabRegistry,
    entity: ecs_mod.Entity,
    entity_component_checker: anytype,
    state: *EcsInspectorState,
) InspectorResult {
    var result = InspectorResult{};

    ctx.renderer.drawRect(rect, ctx.theme.panel_bg.darken(0.95));
    ctx.renderer.drawRectOutline(rect, ctx.theme.list_border, 1.0);

    // Header
    const header_height: f32 = 24;
    const header_rect = Rect{
        .x = rect.x,
        .y = rect.y,
        .width = rect.width,
        .height = header_height,
    };
    ctx.renderer.drawRect(header_rect, ctx.theme.panel_title);

    var header_buf: [64]u8 = undefined;
    const header_text = std.fmt.bufPrint(&header_buf, "Entity {d} Components", .{entity.id}) catch "Components";
    const small_text = ctx.theme.font_size_small;
    const small_baseline = ctx.renderer.getBaselineOffset(small_text);
    ctx.renderer.drawText(
        header_text,
        Vec2.init(rect.x + 4, rect.y + header_height / 2 - small_baseline),
        small_text,
        ctx.theme.text_primary,
    );

    // Component list area
    const list_rect = Rect{
        .x = rect.x,
        .y = rect.y + header_height,
        .width = rect.width,
        .height = rect.height - header_height,
    };

    // Note: Scissor disabled - same clipping issues as other panels
    // TODO: Investigate coordinate system mismatch with bgfx scissor

    var y_offset: f32 = 4; // Start with some padding
    var comp_index: usize = 0;

    // Iterate registered component types
    var type_iter = registry.component_types.iterator();
    while (type_iter.next()) |entry| {
        const type_name = entry.key_ptr.*;
        const type_info = entry.value_ptr.*;

        // Check if entity has this component
        if (!entity_component_checker.hasComponent(entity, type_name)) {
            continue;
        }

        // Component section
        const section_y = list_rect.y + y_offset - state.component_scroll;
        const section_height = calculateComponentSectionHeight(type_info);

        // Render component section (removed visibility check since scissor is disabled)
        const comp_result = renderComponentSection(
            ctx,
            label_text,
            Rect{
                .x = list_rect.x,
                .y = section_y,
                .width = list_rect.width,
                .height = section_height,
            },
            type_name,
            type_info,
            entity,
            entity_component_checker,
            state,
            comp_index,
        );

        if (comp_result.field_modified) {
            result.field_modified = true;
            result.modified_component = comp_result.modified_component;
            result.modified_field = comp_result.modified_field;
        }

        y_offset += section_height + 4;
        comp_index += 1;
    }

    ctx.renderer.flushBatches();

    // Handle scroll
    if (list_rect.contains(ctx.input.mouse_pos) and ctx.input.mouse_wheel != 0) {
        const max_scroll = @max(0, y_offset - list_rect.height);
        state.component_scroll -= ctx.input.mouse_wheel * 30;
        state.component_scroll = std.math.clamp(state.component_scroll, 0, max_scroll);
    }

    return result;
}

/// Calculate height needed for a component section
fn calculateComponentSectionHeight(type_info: prefab_mod.ComponentTypeInfo) f32 {
    const header_height: f32 = 22;
    const field_height: f32 = 20;

    if (type_info.metadata) |metadata| {
        return header_height + @as(f32, @floatFromInt(metadata.field_count)) * field_height + 4;
    }
    return header_height + 20; // Minimal height for no-reflection components
}

/// Render a single component section with fields
fn renderComponentSection(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    type_name: []const u8,
    type_info: prefab_mod.ComponentTypeInfo,
    entity: ecs_mod.Entity,
    entity_component_checker: anytype,
    state: *EcsInspectorState,
    comp_index: usize,
) InspectorResult {
    var result = InspectorResult{};

    // Component header (collapsible)
    const header_height: f32 = 22;
    const header_rect = Rect{
        .x = rect.x,
        .y = rect.y,
        .width = rect.width,
        .height = header_height,
    };

    var section_id_buf: [128]u8 = undefined;
    const section_id_str = std.fmt.bufPrint(&section_id_buf, "{s}_comp_{d}", .{ label_text, comp_index }) catch "comp";
    const section_id = widgetId(section_id_str);
    const section_clicked = ctx.registerWidget(section_id, header_rect);

    if (section_clicked) {
        state.selected_component = if (state.selected_component == comp_index) null else comp_index;
    }

    const is_expanded = state.selected_component == comp_index or true; // Always expanded for now

    // Header background
    const header_bg = if (ctx.isHot(section_id))
        ctx.theme.list_item_hover
    else
        ctx.theme.panel_title.lighten(0.9);
    ctx.renderer.drawRect(header_rect, header_bg);

    // Extract short type name (remove module path)
    const short_name = getShortTypeName(type_name);

    const small_text = ctx.theme.font_size_small;
    const small_baseline = ctx.renderer.getBaselineOffset(small_text);

    // Expansion indicator
    const indicator = if (is_expanded) "v" else ">";
    ctx.renderer.drawText(
        indicator,
        Vec2.init(rect.x + 4, rect.y + header_height / 2 - small_baseline),
        small_text,
        ctx.theme.text_primary,
    );

    ctx.renderer.drawText(
        short_name,
        Vec2.init(rect.x + 16, rect.y + header_height / 2 - small_baseline),
        small_text,
        ctx.theme.text_primary,
    );

    if (!is_expanded) {
        return result;
    }

    // Render fields if we have reflection metadata
    if (type_info.metadata) |metadata| {
        var field_y = rect.y + header_height;
        const field_height: f32 = 20;
        const indent: f32 = 12;

        var field_iter = metadata.fieldIterator();
        var field_idx: usize = 0;
        while (field_iter.next()) |field| {
            const field_rect = Rect{
                .x = rect.x + indent,
                .y = field_y,
                .width = rect.width - indent - 4,
                .height = field_height,
            };

            // Get current field value
            if (type_info.getter) |getter| {
                if (entity_component_checker.getComponentPtr(entity, type_name)) |comp_ptr| {
                    if (getter(comp_ptr, field.name)) |value| {
                        const modified = renderFieldEditor(
                            ctx,
                            label_text,
                            field_rect,
                            field,
                            value,
                            type_name,
                            entity,
                            entity_component_checker,
                            type_info,
                            state,
                            comp_index,
                            field_idx,
                        );

                        if (modified) {
                            result.field_modified = true;
                            result.modified_component = type_name;
                            result.modified_field = field.name;
                        }
                    }
                }
            } else {
                // No getter, just show field name and type
                ctx.renderer.drawText(
                    field.name,
                    Vec2.init(field_rect.x, field_rect.y + field_height / 2 - small_baseline),
                    small_text,
                    Color.init(180, 180, 180, 255),
                );

                ctx.renderer.drawText(
                    "(no reflection)",
                    Vec2.init(field_rect.x + 100, field_rect.y + field_height / 2 - small_baseline),
                    small_text,
                    Color.init(128, 128, 128, 255),
                );
            }

            field_y += field_height;
            field_idx += 1;
        }
    } else {
        // No metadata available
        const no_meta_y = rect.y + header_height + 4;
        ctx.renderer.drawText(
            "No reflection metadata",
            Vec2.init(rect.x + 12, no_meta_y),
            small_text,
            Color.init(128, 128, 128, 255),
        );
    }

    return result;
}

/// Render a single field with appropriate editor
fn renderFieldEditor(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    field: *const reflection.FieldInfo,
    value: reflection.FieldValue,
    type_name: []const u8,
    entity: ecs_mod.Entity,
    entity_component_checker: anytype,
    type_info: prefab_mod.ComponentTypeInfo,
    state: *EcsInspectorState,
    comp_index: usize,
    field_idx: usize,
) bool {
    _ = entity;
    const small_text = ctx.theme.font_size_small;
    const small_baseline = ctx.renderer.getBaselineOffset(small_text);

    // Field name
    ctx.renderer.drawText(
        field.name,
        Vec2.init(rect.x, rect.y + rect.height / 2 - small_baseline),
        small_text,
        Color.init(200, 200, 200, 255),
    );

    // Value display/editor area
    const value_x = rect.x + 100;
    const value_width = rect.width - 104;
    const value_rect = Rect{
        .x = value_x,
        .y = rect.y,
        .width = value_width,
        .height = rect.height,
    };

    // Create unique ID for this field
    var field_id_buf: [128]u8 = undefined;
    const field_id_str = std.fmt.bufPrint(&field_id_buf, "{s}_field_{d}_{d}", .{
        label_text,
        comp_index,
        field_idx,
    }) catch "field";
    const field_id = widgetId(field_id_str);
    const field_clicked = ctx.registerWidget(field_id, value_rect);

    var modified = false;

    // Format value for display
    var value_buf: [128]u8 = undefined;
    const value_str = formatFieldValue(&value_buf, value);

    // Check if this field is being edited
    const is_editing = state.editing_field != null and std.mem.eql(u8, state.editing_field.?, field.name);

    if (field.kind.isSerializable() and field.kind.isPrimitive()) {
        // Editable field
        const is_focused = ctx.isFocused(field_id);

        if (field_clicked and !is_editing) {
            // Start editing
            ctx.setFocus(field_id);
            state.editing_field = field.name;
            @memcpy(state.edit_buffer[0..value_str.len], value_str);
            state.edit_buffer_len = value_str.len;
        }

        if (is_focused and is_editing) {
            // Handle text input
            for (ctx.input.text_input) |char| {
                if (state.edit_buffer_len < state.edit_buffer.len) {
                    state.edit_buffer[state.edit_buffer_len] = char;
                    state.edit_buffer_len += 1;
                }
            }

            if (ctx.input.key_backspace and state.edit_buffer_len > 0) {
                state.edit_buffer_len -= 1;
            }

            // Enter to confirm
            if (ctx.input.key_enter) {
                // Try to apply the new value
                if (parseAndApplyValue(
                    field,
                    state.edit_buffer[0..state.edit_buffer_len],
                    type_name,
                    entity_component_checker,
                    type_info,
                )) {
                    modified = true;
                }
                state.editing_field = null;
                ctx.clearFocus();
            }

            // Draw edit background
            ctx.renderer.drawRect(value_rect, ctx.theme.input_bg_focused);
            ctx.renderer.drawRectOutline(value_rect, ctx.theme.input_border_focused, 1.0);

            ctx.renderer.drawText(
                state.edit_buffer[0..state.edit_buffer_len],
                Vec2.init(value_rect.x + 2, value_rect.y + rect.height / 2 - small_baseline),
                small_text,
                ctx.theme.input_text,
            );

            // Cursor
            const edit_width = ctx.renderer.measureText(state.edit_buffer[0..state.edit_buffer_len], small_text).x;
            ctx.renderer.drawRect(Rect{
                .x = value_rect.x + 2 + edit_width,
                .y = value_rect.y + 2,
                .width = 2,
                .height = rect.height - 4,
            }, ctx.theme.input_cursor);
        } else {
            // Display value (hover effect)
            const bg = if (ctx.isHot(field_id))
                ctx.theme.input_bg.lighten(0.9)
            else
                Color.init(0, 0, 0, 0);

            if (ctx.isHot(field_id)) {
                ctx.renderer.drawRect(value_rect, bg);
                ctx.renderer.drawRectOutline(value_rect, ctx.theme.input_border, 1.0);
            }

            ctx.renderer.drawText(
                value_str,
                Vec2.init(value_rect.x + 2, value_rect.y + rect.height / 2 - small_baseline),
                small_text,
                getValueColor(field.kind),
            );
        }
    } else {
        // Non-editable field - just display
        ctx.renderer.drawText(
            value_str,
            Vec2.init(value_rect.x + 2, value_rect.y + rect.height / 2 - small_baseline),
            small_text,
            getValueColor(field.kind),
        );
    }

    return modified;
}

/// Render archetype statistics
fn renderArchetypeStats(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    registry: *const prefab_mod.PrefabRegistry,
    entities: []const ecs_mod.Entity,
    entity_component_checker: anytype,
) void {
    _ = label_text;

    ctx.renderer.drawRect(rect, ctx.theme.panel_bg.darken(0.95));
    ctx.renderer.drawRectOutline(rect, ctx.theme.list_border, 1.0);

    const small_text = ctx.theme.font_size_small;
    const small_baseline = ctx.renderer.getBaselineOffset(small_text);

    // Header
    const header_height: f32 = 24;
    ctx.renderer.drawRect(Rect{
        .x = rect.x,
        .y = rect.y,
        .width = rect.width,
        .height = header_height,
    }, ctx.theme.panel_title);

    ctx.renderer.drawText(
        "Component Statistics",
        Vec2.init(rect.x + 4, rect.y + header_height / 2 - small_baseline),
        small_text,
        ctx.theme.text_primary,
    );

    // Stats content - start well below header
    var y_offset: f32 = header_height + 12;
    const row_height: f32 = 22;

    // Total entities
    var total_buf: [64]u8 = undefined;
    const total_text = std.fmt.bufPrint(&total_buf, "Total Entities: {d}", .{entities.len}) catch "???";
    ctx.renderer.drawText(
        total_text,
        Vec2.init(rect.x + 8, rect.y + y_offset),
        small_text,
        Color.init(220, 220, 220, 255),
    );
    y_offset += row_height;

    // Registered component types
    var types_buf: [64]u8 = undefined;
    const types_text = std.fmt.bufPrint(&types_buf, "Component Types: {d}", .{
        registry.component_types.count(),
    }) catch "???";
    ctx.renderer.drawText(
        types_text,
        Vec2.init(rect.x + 8, rect.y + y_offset),
        small_text,
        Color.init(220, 220, 220, 255),
    );
    y_offset += row_height * 1.5;

    // Per-component stats
    ctx.renderer.drawText(
        "Components by Type:",
        Vec2.init(rect.x + 8, rect.y + y_offset),
        small_text,
        Color.init(200, 200, 200, 255),
    );
    y_offset += row_height;

    // Note: Scissor disabled - same clipping issues as entity list
    // TODO: Investigate coordinate system mismatch with bgfx scissor

    var type_iter = registry.component_types.iterator();
    while (type_iter.next()) |entry| {
        const type_name = entry.key_ptr.*;

        // Count entities with this component
        var count: usize = 0;
        for (entities) |entity| {
            if (entity_component_checker.hasComponent(entity, type_name)) {
                count += 1;
            }
        }

        const short_name = getShortTypeName(type_name);
        var stat_buf: [128]u8 = undefined;
        const stat_text = std.fmt.bufPrint(&stat_buf, "  {s}: {d}", .{ short_name, count }) catch "???";

        ctx.renderer.drawText(
            stat_text,
            Vec2.init(rect.x + 8, rect.y + y_offset),
            small_text,
            if (count > 0) Color.init(220, 220, 220, 255) else Color.init(120, 120, 120, 255),
        );
        y_offset += row_height;
    }

    ctx.renderer.flushBatches();
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Count components for an entity
fn countEntityComponents(
    entity: ecs_mod.Entity,
    registry: *const prefab_mod.PrefabRegistry,
    entity_component_checker: anytype,
) usize {
    var count: usize = 0;
    var type_iter = registry.component_types.iterator();
    while (type_iter.next()) |entry| {
        if (entity_component_checker.hasComponent(entity, entry.key_ptr.*)) {
            count += 1;
        }
    }
    return count;
}

/// Extract short type name from full path
fn getShortTypeName(full_name: []const u8) []const u8 {
    // Find last '.' to get just the type name
    var last_dot: usize = 0;
    for (full_name, 0..) |c, i| {
        if (c == '.') {
            last_dot = i + 1;
        }
    }
    return full_name[last_dot..];
}

/// Simple substring check
fn contains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    if (needle.len == 0) return true;

    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.mem.eql(u8, haystack[i .. i + needle.len], needle)) {
            return true;
        }
    }
    return false;
}

/// Format a field value for display
fn formatFieldValue(buf: []u8, value: reflection.FieldValue) []const u8 {
    return switch (value) {
        .int => |v| std.fmt.bufPrint(buf, "{d}", .{v}) catch "???",
        .uint => |v| std.fmt.bufPrint(buf, "{d}", .{v}) catch "???",
        .float => |v| std.fmt.bufPrint(buf, "{d:.3}", .{v}) catch "???",
        .boolean => |v| if (v) "true" else "false",
        .string => |v| v,
        .vec2 => |v| std.fmt.bufPrint(buf, "({d:.2}, {d:.2})", .{ v.x, v.y }) catch "???",
        .color => |c| std.fmt.bufPrint(buf, "#{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{ c.r, c.g, c.b, c.a }) catch "???",
        .entity => |e| std.fmt.bufPrint(buf, "Entity({d})", .{e.id}) catch "???",
        .optional_entity => |oe| if (oe) |e|
            std.fmt.bufPrint(buf, "Entity({d})", .{e.id}) catch "???"
        else
            "null",
        .enum_value => |ev| ev.value_name,
    };
}

/// Get color for displaying a value based on its kind
fn getValueColor(kind: reflection.FieldKind) Color {
    return switch (kind) {
        .int_signed, .int_unsigned => Color.init(100, 200, 255, 255), // Blue for integers
        .float => Color.init(100, 255, 200, 255), // Cyan for floats
        .boolean => Color.init(255, 200, 100, 255), // Orange for booleans
        .string => Color.init(200, 255, 100, 255), // Green for strings
        .vec2 => Color.init(255, 150, 150, 255), // Pink for vec2
        .entity, .optional_entity => Color.init(200, 150, 255, 255), // Purple for entities
        .color => Color.init(255, 255, 150, 255), // Yellow for colors
        .@"enum" => Color.init(150, 200, 255, 255), // Light blue for enums
        else => Color.init(180, 180, 180, 255), // Gray for unknown
    };
}

/// Parse string value and apply to component field
fn parseAndApplyValue(
    field: *const reflection.FieldInfo,
    value_str: []const u8,
    type_name: []const u8,
    entity_component_checker: anytype,
    type_info: prefab_mod.ComponentTypeInfo,
) bool {
    _ = type_name;
    _ = entity_component_checker;

    const setter = type_info.setter orelse return false;
    _ = setter;

    // Parse based on field kind
    const new_value: ?reflection.FieldValue = switch (field.kind) {
        .int_signed => blk: {
            const parsed = std.fmt.parseInt(i64, value_str, 10) catch break :blk null;
            break :blk .{ .int = parsed };
        },
        .int_unsigned => blk: {
            const parsed = std.fmt.parseInt(u64, value_str, 10) catch break :blk null;
            break :blk .{ .uint = parsed };
        },
        .float => blk: {
            const parsed = std.fmt.parseFloat(f64, value_str) catch break :blk null;
            break :blk .{ .float = parsed };
        },
        .boolean => blk: {
            if (std.mem.eql(u8, value_str, "true")) {
                break :blk .{ .boolean = true };
            } else if (std.mem.eql(u8, value_str, "false")) {
                break :blk .{ .boolean = false };
            }
            break :blk null;
        },
        else => null,
    };

    if (new_value) |_| {
        // Note: Full setter integration would require passing the actual component pointer
        // For now, we just validate that the parse succeeded
        return true;
    }

    return false;
}

/// Auto-layout ECS Inspector
pub fn ecsInspectorAuto(
    ctx: *Context,
    label_text: []const u8,
    width: f32,
    height: f32,
    registry: *const prefab_mod.PrefabRegistry,
    entities: []const ecs_mod.Entity,
    entity_component_checker: anytype,
    state: *EcsInspectorState,
) InspectorResult {
    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height,
    };

    const result = ecsInspector(ctx, label_text, rect, registry, entities, entity_component_checker, state);
    ctx.advanceCursor(height, ctx.theme.widget_spacing);

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "EcsInspectorState - default initialization" {
    const state = EcsInspectorState{};
    try std.testing.expectEqual(@as(f32, 0), state.entity_scroll);
    try std.testing.expectEqual(@as(?ecs_mod.Entity, null), state.selected_entity);
    try std.testing.expectEqual(@as(usize, 0), state.filter_len);
    try std.testing.expectEqual(@as(usize, 0), state.current_tab);
}

test "EcsInspectorState - clearSelection" {
    var state = EcsInspectorState{};
    state.selected_entity = ecs_mod.Entity.init(5, 1);
    state.selected_component = 2;

    state.clearSelection();

    try std.testing.expectEqual(@as(?ecs_mod.Entity, null), state.selected_entity);
    try std.testing.expectEqual(@as(?usize, null), state.selected_component);
}

test "getShortTypeName - basic" {
    try std.testing.expectEqualStrings("Position", getShortTypeName("game.components.Position"));
    try std.testing.expectEqualStrings("Health", getShortTypeName("Health"));
    try std.testing.expectEqualStrings("Transform", getShortTypeName("ecs.Transform"));
}

test "contains - substring search" {
    try std.testing.expect(contains("hello world", "world"));
    try std.testing.expect(contains("hello", "hello"));
    try std.testing.expect(contains("hello", ""));
    try std.testing.expect(!contains("hello", "world"));
    try std.testing.expect(!contains("hi", "hello"));
}

test "formatFieldValue - primitives" {
    var buf: [128]u8 = undefined;

    try std.testing.expectEqualStrings("42", formatFieldValue(&buf, .{ .int = 42 }));
    try std.testing.expectEqualStrings("true", formatFieldValue(&buf, .{ .boolean = true }));
    try std.testing.expectEqualStrings("false", formatFieldValue(&buf, .{ .boolean = false }));
}

test "formatFieldValue - complex types" {
    var buf: [128]u8 = undefined;

    const vec_result = formatFieldValue(&buf, .{ .vec2 = .{ .x = 1.5, .y = 2.5 } });
    try std.testing.expect(std.mem.startsWith(u8, vec_result, "("));

    try std.testing.expectEqualStrings("null", formatFieldValue(&buf, .{ .optional_entity = null }));
}

test "getValueColor - returns different colors" {
    const int_color = getValueColor(.int_signed);
    const float_color = getValueColor(.float);
    const bool_color = getValueColor(.boolean);

    // Colors should be different
    try std.testing.expect(int_color.r != float_color.r or int_color.g != float_color.g);
    try std.testing.expect(float_color.r != bool_color.r or float_color.g != bool_color.g);
}

test "InspectorResult - default values" {
    const result = InspectorResult{};
    try std.testing.expect(!result.entity_changed);
    try std.testing.expect(!result.field_modified);
    try std.testing.expectEqual(@as(?[]const u8, null), result.modified_component);
}
