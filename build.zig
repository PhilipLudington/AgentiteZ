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
    const mod = b.addModule("EtherMud", .{
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

    // === Basic demo executable (simple demo from main.zig) ===
    // This is a minimal demo showing basic engine usage
    const basic_exe = b.addExecutable(.{
        .name = "EtherMud",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "EtherMud", .module = mod },
            },
        }),
    });

    // Link against system-installed SDL3
    basic_exe.linkSystemLibrary("SDL3");
    basic_exe.linkLibC();
    basic_exe.linkLibCpp();

    // Add bgfx and dependencies
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

    // Build bx (base library)
    basic_exe.addCSourceFile(.{
        .file = b.path("external/bx/src/amalgamated.cpp"),
        .flags = &bgfx_flags,
    });
    basic_exe.addIncludePath(b.path("external/bx/include"));
    basic_exe.addIncludePath(b.path("external/bx/3rdparty"));

    // Build minimal bimg (image library)
    basic_exe.addCSourceFiles(.{
        .files = &[_][]const u8{
            "external/bimg/src/image.cpp",
            "external/bimg/src/image_gnf.cpp", // GNF image format support
        },
        .flags = &bgfx_flags,
    });
    basic_exe.addIncludePath(b.path("external/bimg/include"));
    basic_exe.addIncludePath(b.path("external/bimg/3rdparty"));
    basic_exe.addIncludePath(b.path("external/bimg/3rdparty/astc-encoder/include"));
    basic_exe.addIncludePath(b.path("external/bimg/3rdparty/iqa/include"));

    // Build bgfx (rendering library)
    // Use .mm file for macOS to get Metal support
    if (is_macos) {
        basic_exe.addCSourceFile(.{
            .file = b.path("external/bgfx/src/amalgamated.mm"),
            .flags = &bgfx_flags,
        });
        basic_exe.linkFramework("Metal");
        basic_exe.linkFramework("QuartzCore");
        basic_exe.linkFramework("Cocoa");
        basic_exe.linkFramework("IOKit"); // For IORegistry* functions
    } else {
        basic_exe.addCSourceFile(.{
            .file = b.path("external/bgfx/src/amalgamated.cpp"),
            .flags = &bgfx_flags,
        });
    }
    basic_exe.addIncludePath(b.path("external/bgfx/include"));
    basic_exe.addIncludePath(b.path("external/bgfx/3rdparty"));
    basic_exe.addIncludePath(b.path("external/bgfx/3rdparty/khronos"));

    // Add stb_truetype include path and custom allocator wrapper
    basic_exe.addIncludePath(b.path("external/stb"));
    basic_exe.addCSourceFile(.{
        .file = b.path("src/stb_truetype_wrapper.c"),
        .flags = &.{"-std=c99"},
    });

    b.installArtifact(basic_exe);

    // Run step for basic demo
    const run_basic_step = b.step("run-basic", "Run the basic demo");
    const run_basic_cmd = b.addRunArtifact(basic_exe);
    run_basic_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_basic_cmd.addArgs(args);
    }
    run_basic_step.dependOn(&run_basic_cmd.step);

    // === Examples ===

    // Minimal example - simple window with blue screen
    const minimal_exe = b.addExecutable(.{
        .name = "minimal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/minimal.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "EtherMud", .module = mod },
            },
        }),
    });

    // Link the same libraries as main exe
    minimal_exe.linkSystemLibrary("SDL3");
    minimal_exe.linkLibC();
    minimal_exe.linkLibCpp();

    // Add bgfx and dependencies (same as main exe)
    minimal_exe.addCSourceFile(.{
        .file = b.path("external/bx/src/amalgamated.cpp"),
        .flags = &bgfx_flags,
    });
    minimal_exe.addIncludePath(b.path("external/bx/include"));
    minimal_exe.addIncludePath(b.path("external/bx/3rdparty"));

    minimal_exe.addCSourceFiles(.{
        .files = &[_][]const u8{
            "external/bimg/src/image.cpp",
            "external/bimg/src/image_gnf.cpp",
        },
        .flags = &bgfx_flags,
    });
    minimal_exe.addIncludePath(b.path("external/bimg/include"));
    minimal_exe.addIncludePath(b.path("external/bimg/3rdparty"));
    minimal_exe.addIncludePath(b.path("external/bimg/3rdparty/astc-encoder/include"));
    minimal_exe.addIncludePath(b.path("external/bimg/3rdparty/iqa/include"));

    if (is_macos) {
        minimal_exe.addCSourceFile(.{
            .file = b.path("external/bgfx/src/amalgamated.mm"),
            .flags = &bgfx_flags,
        });
        minimal_exe.linkFramework("Metal");
        minimal_exe.linkFramework("QuartzCore");
        minimal_exe.linkFramework("Cocoa");
        minimal_exe.linkFramework("IOKit");
    } else {
        minimal_exe.addCSourceFile(.{
            .file = b.path("external/bgfx/src/amalgamated.cpp"),
            .flags = &bgfx_flags,
        });
    }
    minimal_exe.addIncludePath(b.path("external/bgfx/include"));
    minimal_exe.addIncludePath(b.path("external/bgfx/3rdparty"));
    minimal_exe.addIncludePath(b.path("external/bgfx/3rdparty/khronos"));

    minimal_exe.addIncludePath(b.path("external/stb"));
    minimal_exe.addCSourceFile(.{
        .file = b.path("src/stb_truetype_wrapper.c"),
        .flags = &.{"-std=c99"},
    });

    b.installArtifact(minimal_exe);

    // Run step for minimal example
    const run_minimal_step = b.step("run-minimal", "Run the minimal example");
    const run_minimal_cmd = b.addRunArtifact(minimal_exe);
    run_minimal_cmd.step.dependOn(b.getInstallStep());
    run_minimal_step.dependOn(&run_minimal_cmd.step);

    // === demo_ui executable (full widget showcase) ===
    const demo_ui_exe = b.addExecutable(.{
        .name = "demo_ui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo_ui.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "EtherMud", .module = mod },
            },
        }),
    });

    // Link the same libraries as main exe
    demo_ui_exe.linkSystemLibrary("SDL3");
    demo_ui_exe.linkLibC();
    demo_ui_exe.linkLibCpp();

    // Add bgfx and dependencies (same as main exe)
    demo_ui_exe.addCSourceFile(.{
        .file = b.path("external/bx/src/amalgamated.cpp"),
        .flags = &bgfx_flags,
    });
    demo_ui_exe.addIncludePath(b.path("external/bx/include"));
    demo_ui_exe.addIncludePath(b.path("external/bx/3rdparty"));

    demo_ui_exe.addCSourceFiles(.{
        .files = &[_][]const u8{
            "external/bimg/src/image.cpp",
            "external/bimg/src/image_gnf.cpp",
        },
        .flags = &bgfx_flags,
    });
    demo_ui_exe.addIncludePath(b.path("external/bimg/include"));
    demo_ui_exe.addIncludePath(b.path("external/bimg/3rdparty"));
    demo_ui_exe.addIncludePath(b.path("external/bimg/3rdparty/astc-encoder/include"));
    demo_ui_exe.addIncludePath(b.path("external/bimg/3rdparty/iqa/include"));

    if (is_macos) {
        demo_ui_exe.addCSourceFile(.{
            .file = b.path("external/bgfx/src/amalgamated.mm"),
            .flags = &bgfx_flags,
        });
        demo_ui_exe.linkFramework("Metal");
        demo_ui_exe.linkFramework("QuartzCore");
        demo_ui_exe.linkFramework("Cocoa");
        demo_ui_exe.linkFramework("IOKit");
    } else {
        demo_ui_exe.addCSourceFile(.{
            .file = b.path("external/bgfx/src/amalgamated.cpp"),
            .flags = &bgfx_flags,
        });
    }
    demo_ui_exe.addIncludePath(b.path("external/bgfx/include"));
    demo_ui_exe.addIncludePath(b.path("external/bgfx/3rdparty"));
    demo_ui_exe.addIncludePath(b.path("external/bgfx/3rdparty/khronos"));

    demo_ui_exe.addIncludePath(b.path("external/stb"));
    demo_ui_exe.addCSourceFile(.{
        .file = b.path("src/stb_truetype_wrapper.c"),
        .flags = &.{"-std=c99"},
    });

    b.installArtifact(demo_ui_exe);

    // Run step for demo_ui (this is the default run command)
    const run_step = b.step("run", "Run the full UI widget showcase");
    const run_cmd = b.addRunArtifact(demo_ui_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
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
