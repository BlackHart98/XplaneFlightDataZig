const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const src_files = .{
        "calculator/density_altitude_calculator.zig", 
        "calculator/flight_calculator.zig", 
        "calculator/turn_calculator.zig", 
        "calculator/vnav_calculator.zig"
    };
    const exe_files = .{
        "density_altitude_calculator", 
        "flight_calculator", 
        "turn_calculator", 
        "vnav_calculator"
    };
    inline for (0..src_files.len) |i|{
        // Density altitude calculator
        const exe = b.addExecutable(.{
            .name = exe_files[i],
            .root_module = b.createModule(.{
                .root_source_file = b.path(src_files[i]),
                .target = target,
                .optimize = optimize,
            }),
        });
        b.installArtifact(exe);
    }
}