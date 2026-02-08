const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get shinydb-zig-client dependency (adjust path as needed)
    const shinydb_zig_client_path = b.path("../shinydb-zig-client/src/root.zig");
    const proto_path = b.path("../proto/src/root.zig");
    const bson_path = b.path("../bson/src/root.zig");

    // Create modules
    const bson_module = b.createModule(.{
        .root_source_file = bson_path,
        .target = target,
        .optimize = optimize,
    });

    const proto_module = b.createModule(.{
        .root_source_file = proto_path,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "bson", .module = bson_module },
        },
    });

    const shinydb_zig_client = b.createModule(.{
        .root_source_file = shinydb_zig_client_path,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "proto", .module = proto_module },
            .{ .name = "bson", .module = bson_module },
        },
    });

    // Create shinydb-shell executable
    const exe = b.addExecutable(.{
        .name = "shinydb-shell",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shinydb_zig_client", .module = shinydb_zig_client },
                .{ .name = "bson", .module = bson_module },
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
