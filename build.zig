const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "voxels",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.entry = .disabled;
    exe.rdynamic = true;
    exe.export_memory = true;

    b.installArtifact(exe);

    const install_web = b.addInstallDirectory(.{
        .source_dir = .{ .path = "web" },
        .install_dir = .prefix,
        .install_subdir = "web",
    });
    b.getInstallStep().dependOn(&install_web.step);
}
