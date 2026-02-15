const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get dependencies via the package manager
    const bson_dep = b.dependency("bson", .{});
    const bson_module = bson_dep.module("bson");

    const proto_dep = b.dependency("proto", .{});
    const proto_module = proto_dep.module("proto");

    const client_dep = b.dependency("shinydb_zig_client", .{});
    const client_module = client_dep.module("shinydb_zig_client");

    // Create shinydb-shell executable
    const exe = b.addExecutable(.{
        .name = "shinydb-shell",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shinydb_zig_client", .module = client_module },
                .{ .name = "bson", .module = bson_module },
                .{ .name = "proto", .module = proto_module },
            },
        }),
    });

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the shell");
    run_step.dependOn(&run_cmd.step);
}
