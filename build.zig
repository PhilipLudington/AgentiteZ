const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("AgentiteZ", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // Add stb_truetype include path to module for @cImport
    mod.addIncludePath(b.path("external/stb"));

    // Define bgfx compiler flags once (used by all executables)
    const is_macos = target.result.os.tag == .macos;
    const bgfx_flags = [_][]const u8{
        "-Wno-deprecated-declarations",
        "-fno-strict-aliasing",
        "-fno-exceptions",
        "-fno-rtti",
        "-ffast-math",
        "-DBX_CONFIG_DEBUG=0",
        "-D__STDC_FORMAT_MACROS",
        "-D__STDC_LIMIT_MACROS",
        "-D__STDC_CONSTANT_MACROS",
        "-DBGFX_CONFIG_MULTITHREADED=0",
        "-DBIMG_DECODE_ASTC=0",
        "-DBIMG_ENCODE_ASTC=0",
        "-Wno-error=implicit-function-declaration", // Allow malloc without malloc.h
    };

    // === Executables ===

    // Basic demo executable (full demo from main.zig)
    const basic_exe = createExecutable(b, target, optimize, mod, "AgentiteZ", "src/main.zig", is_macos, &bgfx_flags);
    b.installArtifact(basic_exe);

    // Minimal example - simple window with blue screen
    const minimal_exe = createExecutable(b, target, optimize, mod, "minimal", "examples/minimal.zig", is_macos, &bgfx_flags);
    b.installArtifact(minimal_exe);

    // Demo UI executable (full widget showcase)
    const demo_ui_exe = createExecutable(b, target, optimize, mod, "demo_ui", "examples/demo_ui.zig", is_macos, &bgfx_flags);
    b.installArtifact(demo_ui_exe);

    // ECS Game example - demonstrates ECS with player, enemies, collision
    const ecs_game_exe = createExecutable(b, target, optimize, mod, "ecs_game", "examples/ecs_game.zig", is_macos, &bgfx_flags);
    b.installArtifact(ecs_game_exe);

    // UI Forms example - demonstrates interactive forms with all widget types
    const ui_forms_exe = createExecutable(b, target, optimize, mod, "ui_forms", "examples/ui_forms.zig", is_macos, &bgfx_flags);
    b.installArtifact(ui_forms_exe);

    // Shapes Demo - demonstrates 2D rendering primitives and animation
    const shapes_demo_exe = createExecutable(b, target, optimize, mod, "shapes_demo", "examples/shapes_demo.zig", is_macos, &bgfx_flags);
    b.installArtifact(shapes_demo_exe);

    // ECS Inspector Demo - demonstrates the ECS Inspector debug UI widget
    const ecs_inspector_demo_exe = createExecutable(b, target, optimize, mod, "ecs_inspector_demo", "examples/ecs_inspector_demo.zig", is_macos, &bgfx_flags);
    b.installArtifact(ecs_inspector_demo_exe);

    // Game Speed Demo - demonstrates game speed control with pause/speed presets
    const game_speed_demo_exe = createExecutable(b, target, optimize, mod, "game_speed_demo", "examples/game_speed_demo.zig", is_macos, &bgfx_flags);
    b.installArtifact(game_speed_demo_exe);

    // === Run Steps ===

    // Run step for basic demo
    const run_basic_step = b.step("run-basic", "Run the basic demo");
    const run_basic_cmd = b.addRunArtifact(basic_exe);
    run_basic_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_basic_cmd.addArgs(args);
    }
    run_basic_step.dependOn(&run_basic_cmd.step);

    // Run step for minimal example
    const run_minimal_step = b.step("run-minimal", "Run the minimal example");
    const run_minimal_cmd = b.addRunArtifact(minimal_exe);
    run_minimal_cmd.step.dependOn(b.getInstallStep());
    run_minimal_step.dependOn(&run_minimal_cmd.step);

    // Run step for demo_ui (this is the default run command)
    const run_step = b.step("run", "Run the full UI widget showcase");
    const run_cmd = b.addRunArtifact(demo_ui_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    // Run step for ECS game example
    const run_ecs_game_step = b.step("run-ecs-game", "Run the ECS game example (player, enemies, shooting)");
    const run_ecs_game_cmd = b.addRunArtifact(ecs_game_exe);
    run_ecs_game_cmd.step.dependOn(b.getInstallStep());
    run_ecs_game_step.dependOn(&run_ecs_game_cmd.step);

    // Run step for UI forms example
    const run_ui_forms_step = b.step("run-ui-forms", "Run the UI forms example (interactive forms)");
    const run_ui_forms_cmd = b.addRunArtifact(ui_forms_exe);
    run_ui_forms_cmd.step.dependOn(b.getInstallStep());
    run_ui_forms_step.dependOn(&run_ui_forms_cmd.step);

    // Run step for shapes demo
    const run_shapes_step = b.step("run-shapes", "Run the 2D shapes demo (animation, colors)");
    const run_shapes_cmd = b.addRunArtifact(shapes_demo_exe);
    run_shapes_cmd.step.dependOn(b.getInstallStep());
    run_shapes_step.dependOn(&run_shapes_cmd.step);

    // Run step for ECS Inspector demo
    const run_inspector_step = b.step("run-inspector", "Run the ECS Inspector demo (entity debugging)");
    const run_inspector_cmd = b.addRunArtifact(ecs_inspector_demo_exe);
    run_inspector_cmd.step.dependOn(b.getInstallStep());
    run_inspector_step.dependOn(&run_inspector_cmd.step);

    // Run step for Game Speed demo
    const run_speed_step = b.step("run-speed", "Run the Game Speed demo (pause, speed control)");
    const run_speed_cmd = b.addRunArtifact(game_speed_demo_exe);
    run_speed_cmd.step.dependOn(b.getInstallStep());
    run_speed_step.dependOn(&run_speed_cmd.step);

    // === Tests ===

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the relative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // We don't test the executable root modules (main.zig, demo_ui.zig) because they
    // import the library module and would need all C dependencies linked again.
    // All meaningful tests should be in the library module (mod) anyway.

    // A top level step for running all tests.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}

/// Helper function to create an executable with all common dependencies
/// Eliminates ~230 lines of duplication across 3 executables
fn createExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ethermud_mod: *std.Build.Module,
    name: []const u8,
    root_source: []const u8,
    is_macos: bool,
    bgfx_flags: []const []const u8,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(root_source),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "AgentiteZ", .module = ethermud_mod },
            },
        }),
    });

    // Link against system-installed SDL3
    exe.linkSystemLibrary("SDL3");
    exe.linkLibC();
    exe.linkLibCpp();

    // Build bx (base library)
    exe.addCSourceFile(.{
        .file = b.path("external/bx/src/amalgamated.cpp"),
        .flags = bgfx_flags,
    });
    exe.addIncludePath(b.path("external/bx/include"));
    exe.addIncludePath(b.path("external/bx/3rdparty"));
    if (is_macos) {
        exe.addIncludePath(b.path("external/bx/include/compat/osx"));
    }

    // Build minimal bimg (image library)
    exe.addCSourceFiles(.{
        .files = &[_][]const u8{
            "external/bimg/src/image.cpp",
            "external/bimg/src/image_gnf.cpp", // GNF image format support
        },
        .flags = bgfx_flags,
    });
    exe.addIncludePath(b.path("external/bimg/include"));
    exe.addIncludePath(b.path("external/bimg/3rdparty"));
    exe.addIncludePath(b.path("external/bimg/3rdparty/astc-encoder/include"));
    exe.addIncludePath(b.path("external/bimg/3rdparty/iqa/include"));

    // Build bgfx (rendering library)
    // Use .mm file for macOS to get Metal support
    if (is_macos) {
        exe.addCSourceFile(.{
            .file = b.path("external/bgfx/src/amalgamated.mm"),
            .flags = bgfx_flags,
        });
        exe.linkFramework("Metal");
        exe.linkFramework("QuartzCore");
        exe.linkFramework("Cocoa");
        exe.linkFramework("IOKit"); // For IORegistry* functions
    } else {
        exe.addCSourceFile(.{
            .file = b.path("external/bgfx/src/amalgamated.cpp"),
            .flags = bgfx_flags,
        });
    }
    exe.addIncludePath(b.path("external/bgfx/include"));
    exe.addIncludePath(b.path("external/bgfx/3rdparty"));
    exe.addIncludePath(b.path("external/bgfx/3rdparty/khronos"));

    // Add stb_truetype include path and custom allocator wrapper
    exe.addIncludePath(b.path("external/stb"));
    exe.addCSourceFile(.{
        .file = b.path("src/stb_truetype_wrapper.c"),
        .flags = &.{"-std=c99"},
    });

    return exe;
}
