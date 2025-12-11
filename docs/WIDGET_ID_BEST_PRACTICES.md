# Widget ID Best Practices

**Critical Information for AgentiteZ UI Development**

---

## Understanding Widget IDs

AgentiteZ uses a **hybrid immediate-mode UI** system where widget state persists between frames. Each widget needs a unique ID to track its state (hover, active, focused, etc.).

### How IDs are Generated

Most convenience widgets generate IDs by hashing their label text:

```zig
pub fn button(ctx: *Context, text: []const u8, rect: Rect) bool {
    const id = widgetId(text);  // ← Hash of text becomes the ID
    // ...
}
```

**This is fast and convenient but has a critical limitation.**

---

## The ID Collision Problem

### What Happens

When multiple widgets have **identical text**, they **share the same ID** and thus **share the same state**.

### Example - The Bug

```zig
// BAD: Both buttons have ID collision!
for (items) |item| {
    if (button(ctx, "Delete", rect)) {  // ← All "Delete" buttons share ONE state!
        deleteItem(item);
    }
}
```

**What goes wrong:**
1. All "Delete" buttons think they're the same widget
2. Hovering over one highlights all of them
3. Clicking one may trigger multiple deletes
4. Widget state becomes corrupted

### Visual Symptoms

- Multiple widgets highlight when you hover over one
- Clicking one widget affects others
- Focus jumps between widgets unexpectedly
- Checkboxes toggle in groups

---

## ✅ Safe Usage Patterns

### 1. Static UIs with Unique Labels

```zig
// SAFE: Each button has unique text
if (button(ctx, "Save Game", rect1)) { }
if (button(ctx, "Load Game", rect2)) { }
if (button(ctx, "Quit", rect3)) { }
```

**Rule:** If every widget on screen has unique text, you're safe.

### 2. Single Instance Per Screen

```zig
// SAFE: Only one "OK" button visible at a time
if (showing_modal_a) {
    if (button(ctx, "OK", rect)) { closeModalA(); }
} else if (showing_modal_b) {
    if (button(ctx, "OK", rect)) { closeModalB(); }
}
```

**Rule:** If only one instance of the text exists per frame, you're safe.

---

## ❌ Unsafe Usage Patterns

### 1. Dynamic Lists with Repeated Labels

```zig
// DANGEROUS: ID collision!
for (inventory_items) |item| {
    if (button(ctx, "Use", rect)) {  // ← All "Use" buttons = same ID
        useItem(item);
    }
}
```

### 2. Multiple Modals Simultaneously

```zig
// DANGEROUS: ID collision!
if (modal_a_open) {
    if (button(ctx, "OK", rect1)) { }  // ← Both "OK" buttons share ID
}
if (modal_b_open) {
    if (button(ctx, "OK", rect2)) { }
}
```

### 3. Repeated UI Patterns

```zig
// DANGEROUS: ID collision!
for (party_members) |member| {
    checkbox(ctx, "Enable", rect, &member.enabled);  // ← All share ID
}
```

---

## 🛠️ Solutions

### Solution 1: Use `buttonWithId()` (Recommended)

Provide explicit unique IDs to prevent collisions:

```zig
// GOOD: Each button gets unique ID
for (items, 0..) |item, i| {
    // Combine index with namespace for uniqueness
    const id = std.hash.Wyhash.hash(i, "inventory_use_button");

    if (buttonWithId(ctx, "Use", id, rect)) {
        useItem(item);
    }
}
```

### Solution 2: Include Index in Label

Make the text itself unique:

```zig
// GOOD: Each button has unique text
for (items, 0..) |item, i| {
    var label_buf: [32]u8 = undefined;
    const label = std.fmt.bufPrint(&label_buf, "Use #{d}", .{i}) catch "Use";

    if (button(ctx, label, rect)) {
        useItem(item);
    }
}
```

### Solution 3: Use Item-Specific Data

Hash unique item properties:

```zig
// GOOD: Each item has unique name
for (items) |item| {
    const id = widgetId(item.name);  // Assuming names are unique

    if (buttonWithId(ctx, "Use", id, rect)) {
        useItem(item);
    }
}
```

---

## Widget-Specific Guidance

### Buttons

```zig
// Convenience function (safe for static UIs)
button(ctx: *Context, text: []const u8, rect: Rect) bool

// Explicit ID function (use for dynamic UIs)
buttonWithId(ctx: *Context, display_text: []const u8, id: u64, rect: Rect) bool
```

**When to use each:**
- `button()` - Static menus, unique button labels
- `buttonWithId()` - Lists, repeated patterns, multiple modals

### Checkboxes

```zig
// Uses label text as ID
checkbox(ctx: *Context, label_text: []const u8, rect: Rect, checked: *bool) bool
```

**Collision risk:** Multiple checkboxes with same label

**Solution:**
```zig
for (options, 0..) |option, i| {
    const id = std.hash.Wyhash.hash(i, "option_checkbox");
    // Currently no checkboxWithId(), so make labels unique:
    var label_buf: [64]u8 = undefined;
    const label = std.fmt.bufPrint(&label_buf, "{s} #{d}", .{option.name, i}) catch option.name;
    _ = checkbox(ctx, label, rect, &option.enabled);
}
```

### Text Input

```zig
// Uses label text as ID
textInput(ctx: *Context, label_text: []const u8, rect: Rect, buffer: []u8, buffer_len: *usize) void
```

**Less risky** - Usually only one focused text input at a time, but still be careful with multiple inputs on same screen.

### Sliders & Progress Bars

```zig
slider(ctx: *Context, label_text: []const u8, rect: Rect, value: f32, min: f32, max: f32) f32
progressBar(ctx: *Context, label_text: []const u8, rect: Rect, progress: f32, show_percentage: bool) void
```

**Moderate risk** - Multiple sliders with same label (e.g., "Volume") will collide.

### Dropdowns & Tabs

```zig
dropdown(ctx: *Context, label_text: []const u8, options: []const []const u8, rect: Rect, state: *DropdownState) void
tabBar(ctx: *Context, tabs: []const []const u8, rect: Rect, selected_index: *usize) void
```

**Lower risk** - Tab labels are usually unique, dropdown labels often unique per screen.

---

## ID Generation Patterns

### Pattern 1: Index + Namespace

```zig
const id = std.hash.Wyhash.hash(index, "namespace_string");
```

**Best for:** Iterating over lists with indices

### Pattern 2: Unique Property Hash

```zig
const id = widgetId(item.uuid);
const id = widgetId(player.name);
const id = std.hash.Wyhash.hash(entity.id, "button_type");
```

**Best for:** Items with unique identifiers

### Pattern 3: Concatenated String

```zig
var id_buf: [128]u8 = undefined;
const id_string = std.fmt.bufPrint(&id_buf, "{s}_{d}", .{category, index}) catch return;
const id = widgetId(id_string);
```

**Best for:** Complex scenarios needing multiple parameters

### Pattern 4: Enum-Based

```zig
const ButtonId = enum(u64) {
    save_game = 1,
    load_game = 2,
    options = 3,
    quit = 4,
};

if (buttonWithId(ctx, "Save", @intFromEnum(ButtonId.save_game), rect)) { }
```

**Best for:** Fixed, known set of widgets

---

## Quick Reference Table

| Widget Type | ID Source | Collision Risk | Mitigation |
|-------------|-----------|----------------|------------|
| `button()` | Text label | **HIGH** in lists | Use `buttonWithId()` |
| `checkbox()` | Label text | **HIGH** in lists | Make labels unique |
| `textInput()` | Label text | Medium | Usually one focused |
| `slider()` | Label text | Medium | Label sliders uniquely |
| `progressBar()` | Label text | Low | Rarely duplicate |
| `dropdown()` | Label text | Medium | Labels often unique |
| `tabBar()` | Tab labels | **HIGH** | Tab labels must be unique |

---

## Testing for ID Collisions

### Symptoms Checklist

- [ ] Multiple widgets highlight when hovering over one
- [ ] Clicking one widget triggers multiple actions
- [ ] Widget state persists incorrectly between frames
- [ ] Checkboxes toggle in groups
- [ ] Focus jumps unexpectedly

### Debugging

Add logging to track IDs:

```zig
const id = widgetId(text);
std.debug.print("Widget '{s}' has ID: {x}\n", .{text, id});

// If you see duplicate IDs with different widgets, you have a collision!
```

---

## Advanced: Custom Widget IDs

For complete control, always use explicit IDs:

```zig
pub const MyWidgetIds = struct {
    pub const player_health_bar: u64 = 0x1000;
    pub const enemy_health_bar: u64 = 0x1001;
    pub const inventory_slot_0: u64 = 0x2000;
    // ... etc
};

// Use in code
if (buttonWithId(ctx, "Delete", MyWidgetIds.inventory_slot_0 + slot_index, rect)) {
    // Handle delete
}
```

**Pros:**
- Zero collision risk
- Explicit, readable
- Easy to debug

**Cons:**
- More boilerplate
- Manual ID management

---

## Summary

### ✅ DO

- Use `button()` for static UIs with unique labels
- Use `buttonWithId()` for dynamic lists and repeated patterns
- Generate unique IDs using index + namespace pattern
- Make widget labels unique when possible
- Test dynamic UIs for ID collisions

### ❌ DON'T

- Use `button("Delete", ...)` in loops
- Assume text-based IDs are always safe
- Ignore hover/click behavior anomalies
- Use same label for multiple widgets simultaneously

---

**Remember:** When in doubt, use explicit IDs. The small amount of extra code prevents subtle, hard-to-debug state corruption bugs.
