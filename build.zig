const std = @import("std");
//const mach = @import("libs/mach/build.zig");
//const zmath = @import("libs/zmath/build.zig");
//const imgui = @import("libs/imgui/build.zig");
//const zmath = @import("libs/zig-gamedev/libs/zmath/build.zig");

//const zgamedev = @import("libs/zig-gamedev/build.zig");
const zsdl = @import("libs/zig-gamedev/libs/zsdl/build.zig");
const zopengl = @import("libs/zig-gamedev/libs/zopengl/build.zig");
const zstbi = @import("libs/zig-gamedev/libs/zstbi/build.zig");
const zmath = @import("libs/zig-gamedev/libs/zmath/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_exe = b.addExecutable(.{
        .name = "sdl",
        .root_source_file = .{ .path = "src/sdl.zig"},
        .target = target,
        .optimize = optimize,
    });
    const zsdl_pkg = zsdl.Package.build(b, .{});
    const zopengl_pkg = zopengl.Package.build(b, .{});
    const zstbi_pkg = zstbi.Package.build(b, target, optimize, .{});
    const zmath_pkg = zmath.Package.build(b, .{});
    sdl_exe.addModule("zsdl", zsdl_pkg.zsdl);
    sdl_exe.addModule("zopengl", zopengl_pkg.zopengl);
    sdl_exe.addModule("zstbi", zstbi_pkg.zstbi);
    sdl_exe.addModule("zmath", zmath_pkg.zmath);
    zsdl_pkg.link(sdl_exe);
    zstbi_pkg.link(sdl_exe);
    sdl_exe.install();
    const sdl_run = sdl_exe.run();
    sdl_run.step.dependOn(b.getInstallStep());
    //if (b.args) |args| {
    //    run_cmd.addArgs(args);
    //}

    //const exe_tests = b.addTest("src/main.zig");
    //exe_tests.setTarget(target);
    //exe_tests.setBuildMode(mode);
    //const test_step = b.step("test", "Run unit tests");
    //test_step.dependOn(&exe_tests.step);

    //for(@typeInfo(zmath).Struct.decls) |decl| {
    //    std.debug.print("{s}\n", .{ decl.name});
    //}
    //zmath.build(b, .{});
    //std.debug.print("{s}\n", .{ @typeName()});
    //const pkgs = [_]std.Build.ModuleDependency{
    //    .{ .name = "zmath", .module =  },
    //};
    //_ = pkgs;

    //const app = try mach.App.init(
    //    b,
    //    .{
    //        .name = "Test",
    //        .src = "src/main.zig",
    //        .target = target,
    //        .optimize = mode,
    //        .deps = &.{},
    //        .res_dirs = null, //&.{"assets"},
    //        .watch_paths = &.{"src/"},
    //    },
    //);

    //try app.link(mach.Options{});
    //app.install();

    //const compile_step = b.step("compile", "Compile example");
    //compile_step.dependOn(&app.getInstallStep().?.step);

    //const run_cmd = try app.run();
    //run_cmd.dependOn(compile_step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&sdl_run.step);
}
