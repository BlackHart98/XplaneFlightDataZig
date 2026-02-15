const std = @import("std");

const SUCCESS: u8 = 0;
const INVALID_ARGS: u8 = 1;
const PARSE_FAILED: u8 = 2;
const SIMULATED: u8 = 3;
const INIT_FAILED: u8 = 4;
const CALCULATION_FAILED: u8 = 5;

// Error codes (AV Rule 52: lowercase)
const error_success: i32 = 0;
const error_invalid_args: i32 = 1;
const error_parse_failed: i32 = 2;

// Mathematical constants (AV Rule 52: lowercase)
const deg_to_rad: f64 = std.math.pi / 180.0;
const rad_to_deg: f64 = 180.0 / std.math.pi;
const nm_to_ft: f64 = 6076.12;
const three_deg_rad: f64 = 3.0 * deg_to_rad;

// Calculation constants (AV Rule 151: no magic numbers)
const vs_conversion_factor: f64 = 101.27;  // Converts GS*tan(γ) to VS in fpm
const min_distance_nm: f64 = 0.01;
const min_groundspeed_kts: f64 = 1.0;
const min_vs_for_time_calc: f64 = 1.0;
const infinite_time: f64 = 999.9;
const zero_distance: f64 = 0.0;
const thousand_feet: f64 = 1000.0;


// JSF-compliant parse function (no exceptions)
fn parseFloat64(str: []const u8, result: *f64) u8 {
    var ret: u8 = SUCCESS;
    const float_num: ?f64 = std.fmt.parseFloat(f64, str) catch null;
    if (float_num) |item|{result.* = item;} 
    else {ret = PARSE_FAILED;}
    return ret;
}


fn absFloat(f: f64) f64 {
    if (0.0 <= f){return f;} else {return (-1 * f);}
}


const VNAVData = struct {
    altitude_to_lose_ft: f64,      // Altitude change required
    flight_path_angle_deg: f64,    // Flight path angle (negative = descent)
    required_vs_fpm: f64,          // Required vertical speed
    tod_distance_nm: f64,          // Top of descent distance (for 3° path)
    time_to_constraint_min: f64,   // Time to reach altitude at current VS
    distance_per_1000ft: f64,      // Distance traveled per 1000 ft altitude change
    vs_for_3deg: f64,              // Vertical speed required for 3° path
    is_descent: bool,                  // True if descending, false if climbing
};

// Calculate VNAV parameters
fn calculateVNAV(current_alt_ft: f64, target_alt_ft: f64, 
                        distance_nm: f64, groundspeed_kts: f64, current_vs_fpm: f64) VNAVData {
    // Calculate altitude change (positive = climb, negative = descend)
    const altitude_change_ft: f64 = target_alt_ft - current_alt_ft;
    const altitude_to_lose_ft: f64 = -altitude_change_ft;  // Legacy field name
    const is_descent: bool = altitude_change_ft < zero_distance;
    
    // Avoid division by zero
    var distance_nm_ = distance_nm;
    var groundspeed_kts_ = groundspeed_kts;
    if (distance_nm_ < min_distance_nm) distance_nm_ = min_distance_nm;
    if (groundspeed_kts_ < min_groundspeed_kts) groundspeed_kts_ = min_groundspeed_kts;
    
    // Calculate flight path angle (positive = climb, negative = descent)
    const distance_ft: f64 = distance_nm_ * nm_to_ft;
    const gamma_rad: f64 = std.math.atan(altitude_change_ft / distance_ft);
    const flight_path_angle_deg: f64 = gamma_rad * rad_to_deg;
    
    // Required vertical speed to meet constraint
    // VS = 101.27 * GS * tan(γ)
    const required_vs_fpm: f64 = vs_conversion_factor * groundspeed_kts_ * std.math.tan(gamma_rad);
    
    // Calculate TOD for standard 3° descent path
    // D = h / (6076 * tan(3°)) or simplified: h / 319
    const abs_alt_change: f64 = absFloat(altitude_change_ft);
    const tod_distance_nm: f64 = abs_alt_change / (nm_to_ft * std.math.tan(three_deg_rad));
    
    // Vertical speed for 3° descent: VS ≈ 5 * GS (rule of thumb)
    // More precisely: VS = 101.27 * GS * tan(3°) ≈ 5.3 * GS
    const vs_for_3deg: f64 = vs_conversion_factor * groundspeed_kts_ * std.math.tan(three_deg_rad);
    
    return VNAVData {
        .altitude_to_lose_ft = altitude_to_lose_ft,     
        .flight_path_angle_deg = flight_path_angle_deg,   
        .required_vs_fpm = required_vs_fpm, 
        .tod_distance_nm = tod_distance_nm,         
        .time_to_constraint_min = if (absFloat(current_vs_fpm) > min_vs_for_time_calc) altitude_change_ft / current_vs_fpm else infinite_time,   
        .distance_per_1000ft = if (abs_alt_change > min_vs_for_time_calc) (distance_nm_ * thousand_feet) / abs_alt_change else zero_distance,     
        .vs_for_3deg = if (!is_descent) -vs_for_3deg else vs_for_3deg,             
        .is_descent = is_descent,                 
    };
}


// Output results as JSON
fn printJSON(vnav: VNAVData) void {
    const is_decent_as_s: [:0]const u8 = if (vnav.is_descent) "true" else "false"; 
    std.debug.print( "{{\n", .{});
    std.debug.print( "  \"altitude_to_lose_ft\": {},\n", .{vnav.altitude_to_lose_ft});
    std.debug.print( "  \"flight_path_angle_deg\": {},\n", .{vnav.flight_path_angle_deg});
    std.debug.print( "  \"required_vs_fpm\": {},\n", .{vnav.required_vs_fpm});
    std.debug.print( "  \"tod_distance_nm\": {},\n", .{vnav.tod_distance_nm});
    std.debug.print( "  \"time_to_constraint_min\": {},\n", .{vnav.time_to_constraint_min});
    std.debug.print( "  \"distance_per_1000ft\": {},\n", .{vnav.distance_per_1000ft});
    std.debug.print( "  \"vs_for_3deg\": {},\n", .{vnav.vs_for_3deg});
    std.debug.print( "  \"is_descent\": {s}\n", .{is_decent_as_s});
    std.debug.print( "}}\n", .{});
}


fn printUsage(program_name: []const u8) void {
    std.debug.print( "Usage: {s} <current_alt_ft> <target_alt_ft> <distance_nm> <groundspeed_kts> <current_vs_fpm>\n\n", .{program_name});
    std.debug.print( "Arguments:\n", .{});
    std.debug.print( "  current_alt_ft  : Current altitude (feet)\n", .{});
    std.debug.print( "  target_alt_ft   : Target altitude (feet)\n", .{});
    std.debug.print( "  distance_nm     : Distance to constraint (nautical miles)\n", .{});
    std.debug.print( "  groundspeed_kts : Groundspeed (knots)\n", .{});
    std.debug.print( "  current_vs_fpm  : Current vertical speed (feet per minute)\n\n", .{});
    std.debug.print( "Example:\n", .{});
    std.debug.print( "  {s} 35000 10000 100 450 -1500\n", .{program_name});
    std.debug.print( "  (FL350 to 10000 ft, 100 NM, 450 kts GS, -1500 fpm)\n", .{});
}


pub fn main() u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var result: u8 = SUCCESS;
    var args = std.process.argsWithAllocator(alloc) catch {result = INIT_FAILED;};

    var program_name: []const u8 = undefined;

    var current_alt_ft: f64 = undefined;
    var target_alt_ft: f64 = undefined;
    var distance_nm: f64 = undefined;
    var groundspeed_kts: f64 = undefined;
    var current_vs_fpm: f64 = undefined;

    var count: u32 = 0;
    while (args.next()) |item| : (count += 1) {
        if (0 == count) {program_name = item;}
        else if (1 == count) {result = parseFloat64(item, &current_alt_ft);}
        else if (2 == count) {result = parseFloat64(item, &target_alt_ft);}
        else if (3 == count) {result = parseFloat64(item, &distance_nm);}
        else if (4 == count) {result = parseFloat64(item, &groundspeed_kts);}
        else if (5 == count) {result = parseFloat64(item, &current_vs_fpm);}
        else {result = INVALID_ARGS;}
    } else {
        if (5 >= count) {result = INVALID_ARGS;}
    }

    if (SUCCESS == result){
        const vnav: VNAVData = calculateVNAV(current_alt_ft, target_alt_ft, distance_nm, groundspeed_kts, current_vs_fpm);
        printJSON(vnav);
    }
    return result;
}