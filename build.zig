const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Density altitude calculator
    const exe = b.addExecutable(.{
        .name = "density_altitude_calculator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("calculator/density_altitude_calculator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // Flight calcuator
    const flight_exe = b.addExecutable(.{
        .name = "flight_calculator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("calculator/flight_calculator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // Turn calcuator
    const turn_exe = b.addExecutable(.{
        .name = "turn_calculator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("calculator/turn_calculator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // VNAV calcuator
    const vnav_exe = b.addExecutable(.{
        .name = "vnav_calculator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("calculator/vnav_calculator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // create executables
    b.installArtifact(exe);
    b.installArtifact(flight_exe);
    b.installArtifact(turn_exe);
    b.installArtifact(vnav_exe);
}