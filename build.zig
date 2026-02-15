const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe_files = .{
        "density_altitude_calculator", 
        "flight_calculator", 
        "turn_calculator", 
        "vnav_calculator"
    };
    inline for (exe_files) |item|{
        const exe = b.addExecutable(.{
            .name = item,
            .root_module = b.createModule(.{
                .root_source_file = b.path("calculator/" ++ item ++ ".zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        b.installArtifact(exe);
    }
}