const std = @import("std");

const SUCCESS: u8 = 0;
const INVALID_ARGS: u8 = 1;
const PARSE_FAILED: u8 = 2;
const SIMULATED: u8 = 3;
const INIT_FAILED: u8 = 4;
const CALCULATION_FAILED: u8 = 5;


// Mathematical constants (AV Rule 52: lowercase)
const deg_to_rad: f64 = std.math.pi / 180.0;
const angle_wrap_limit: f64 = 360.0;
const half_circle: f64 = 180.0;
const wind_calm_threshold: f64 = 0.0;


// JSF-compliant parse function (no exceptions)
fn parseFloat64(str: []const u8, result: *f64) u8 {
    var ret: u8 = SUCCESS;
    const float_num: ?f64 = std.fmt.parseFloat(f64, str) catch null;
    if (float_num) |item|{result.* = item;} 
    else {ret = PARSE_FAILED;}
    return ret;
}


const WindComponents = struct {
    headwind: f64,      // Positive = headwind, negative = tailwind
    crosswind: f64,     // Positive = from right, negative = from left
    total_wind: f64,    // Total wind speed
    wca: f64,          // Wind correction angle
    drift: f64,        // Drift angle (track - heading)
};


// Normalize angle to 0-360 range
// Uses std.math.mod() for deterministic execution time (no variable-iteration loops)
// This is important for real-time and safety-critical systems where
// predictable worst-case execution time (WCET) is required
fn normalizeAngle(angle: f64, result_angle: *f64) u8 {
    var ret: u8 = SUCCESS;
    const float_num: ?f64 = std.math.mod(f64, angle, angle_wrap_limit) catch null;
    if (float_num) |item|{result_angle.* = item;} 
    else {ret = CALCULATION_FAILED;}
    if (0.0 > result_angle.*) {
        result_angle.* += angle_wrap_limit;
    }
    return ret;
}

// Calculate wind components relative to aircraft track
fn calculateWind(track: f64, heading: f64, wind_dir: f64, wind_speed: f64) WindComponents {
    
    // Normalize all angles
    const track_: f64 = normalizeAngle(track);
    const heading_: f64 = normalizeAngle(heading);
    const wind_dir_: f64 = normalizeAngle(wind_dir);
    
    // Calculate drift angle
    var drift = normalizeAngle(track_ - heading_);
    if (drift > half_circle) drift -= angle_wrap_limit;
    
    // Wind direction is where wind comes FROM
    // Calculate angle of wind-from relative to track
    var wind_from_relative: f64 = normalizeAngle(wind_dir_ - track_);
    if (wind_from_relative > half_circle) wind_from_relative -= angle_wrap_limit;
    
    // Convert to radians for trig
    const wind_from_rad: f64 = wind_from_relative * deg_to_rad;
    
    return WindComponents{
        .headwind = -wind_speed * std.math.cos(wind_from_rad),
        .crosswind = wind_speed * std.math.sin(wind_from_rad),
        .total_wind = wind_speed,
        .wca = wind_calm_threshold,
        .drift = drift,
    };
}


// Output results as JSON
fn printJSON(wind: WindComponents) void {
    std.debug.print( "{{\n", .{});
    std.debug.print( "  \"headwind\": {},\n", .{wind.headwind});
    std.debug.print( "  \"crosswind\": {},\n", .{wind.crosswind});
    std.debug.print( "  \"total_wind\": {},\n", .{wind.total_wind});
    std.debug.print( "  \"wca\": {},\n", .{wind.wca});
    std.debug.print( "  \"drift\": {}\n", .{wind.drift});
    std.debug.print( "}}\n", .{});
}


fn printUsage(program_name: []const u8) void {
    std.debug.print( "Usage: {s} <track> <heading> <wind_dir> <wind_speed>\n\n", .{program_name});

    std.debug.print( "Arguments:\n", .{});
    std.debug.print( "  track      : Ground track (degrees true)\n", .{});
    std.debug.print( "  heading    : Aircraft heading (degrees)\n", .{});
    std.debug.print( "  wind_dir   : Wind direction FROM (degrees)\n", .{});
    std.debug.print( "  wind_speed : Wind speed (knots)\n\n", .{});
    std.debug.print( "Example:\n", .{});
    std.debug.print( "  {s} 90 85 270 15\n", .{program_name});
    std.debug.print( "  (Track 90°, Heading 85°, Wind from 270° at 15 knots)\n", .{});
}


pub fn main() u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var result: u8 = SUCCESS;
    var args = std.process.argsWithAllocator(alloc) catch {result = INIT_FAILED;};

    var program_name: []const u8 = undefined;

    var track: f64 = undefined;
    var heading: f64 = undefined;
    var wind_dir: f64 = undefined;
    var wind_speed: f64 = undefined;

    var count: u32 = 0;
    while (args.next()) |item| : (count += 1) {
        if (0 == count) {program_name = item;}
        else if (1 == count) {result = parseFloat64(item, &track);}
        else if (2 == count) {result = parseFloat64(item, &heading);}
        else if (3 == count) {result = parseFloat64(item, &wind_dir);}
        else if (4 == count) {result = parseFloat64(item, &wind_speed);}
        else {result = INVALID_ARGS;}
    } else {
        if (4 >= count) {result = INVALID_ARGS;}
    }

    if (SUCCESS == result){
        const wind: WindComponents = calculateWind(track, heading, wind_dir, wind_speed);
        printJSON(wind);
    }
    return result;
}