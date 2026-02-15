const std = @import("std");

const SUCCESS: u8 = 0;
const INVALID_ARGS: u8 = 1;
const PARSE_FAILED: u8 = 2;
const SIMULATED: u8 = 3;
const INIT_FAILED: u8 = 4;
const CALCULATION_FAILED: u8 = 5;
const ILLEGAL_VALUE = 6;


// Mathematical constants (AV Rule 52: lowercase)
const deg_to_rad: f64 = std.math.pi / 180.0;
const rad_to_deg: f64 = 180.0 / std.math.pi;
const gravity: f64 = 9.80665;  // m/s²
const kts_to_ms: f64 = 0.514444;  // knots to m/s
const standard_rate: f64 = 3.0;   // degrees per second

// Magic number constants (AV Rule 151: no magic numbers)
const infinite_radius_nm: f64 = 999.9;
const infinite_radius_ft: f64 = 999900.0;
const zero_turn_rate: f64 = 0.0;
const infinite_time: f64 = 999.9;
const min_tan_threshold: f64 = 0.001;
const min_turn_rate_threshold: f64 = 0.01;
const meters_per_nm: f64 = 1852.0;
const feet_per_meter: f64 = 3.28084;


const TurnData = struct {
    radius_nm: f64,           // Turn radius in nautical miles
    radius_ft: f64,           // Turn radius in feet
    turn_rate_dps: f64,       // Turn rate in degrees per second
    lead_distance_nm: f64,    // Lead distance to roll out
    lead_distance_ft: f64,    // Lead distance in feet
    time_to_turn_sec: f64,    // Time to complete the turn
    load_factor: f64,         // G-loading in the turn
    standard_rate_bank: f64,  // Bank angle for standard rate turn
};


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


// Calculate comprehensive turn performance
fn calculateTurnPerformance(tas_kts: f64, bank_deg: f64, course_change_deg: f64) TurnData {
    // Convert inputs
    const v_ms: f64 = tas_kts * kts_to_ms;  // TAS in m/s
    const phi_rad: f64 = bank_deg * deg_to_rad;  // Bank angle in radians
    const delta_psi_rad: f64 = course_change_deg * deg_to_rad;  // Course change in radians
    
    // Calculate load factor
    const load_factor: f64 = 1.0 / std.math.cos(phi_rad);
    var radius_nm: f64 = undefined;
    var radius_ft: f64 = undefined;
    var turn_rate_dps: f64 = undefined;
    var lead_distance_nm: f64 = undefined;
    var lead_distance_ft: f64 = undefined;
    var time_to_turn_sec: f64 = undefined;
    
    // Turn radius: R = V² / (g * tan φ)
    const tan_phi: f64 = std.math.tan(phi_rad);
    if (absFloat(tan_phi) < min_tan_threshold) {
        // Essentially wings level - infinite radius
        radius_nm = infinite_radius_nm;
        radius_ft = infinite_radius_ft;
        turn_rate_dps = zero_turn_rate;
        lead_distance_nm = zero_turn_rate;
        lead_distance_ft = zero_turn_rate;
        time_to_turn_sec = infinite_time;
    } else {
        const radius_m: f64 = (v_ms * v_ms) / (gravity * tan_phi);
        
        // Convert radius to NM and feet
        radius_nm = radius_m / meters_per_nm;
        radius_ft = radius_m * feet_per_meter;
        
        // Turn rate: ω = (g * tan φ) / V (rad/s) -> convert to deg/s
        const omega_rad_s: f64 = (gravity * tan_phi) / v_ms;
        turn_rate_dps = omega_rad_s * rad_to_deg;
        
        // Lead distance: L = R * tan(Δψ/2)
        const lead_m: f64 = radius_m * std.math.tan(delta_psi_rad / 2.0);
        lead_distance_nm = lead_m / meters_per_nm;
        lead_distance_ft = lead_m * feet_per_meter;
        
        // Time to turn
        if (absFloat(turn_rate_dps) > min_turn_rate_threshold) {
            time_to_turn_sec = course_change_deg / turn_rate_dps;
        } else {
            time_to_turn_sec = infinite_time;
        }
    }
    
    // Standard rate bank angle: φ = atan(ω * V / g) where ω = 3°/s
    const std_rate_rad_s: f64 = standard_rate * deg_to_rad;
    const std_bank_rad: f64 = std.math.atan((std_rate_rad_s * v_ms) / gravity);
    const standard_rate_bank: f64 = std_bank_rad * rad_to_deg;
    
    return TurnData{
        .radius_nm = radius_nm,
        .radius_ft = radius_ft,
        .turn_rate_dps = turn_rate_dps,
        .lead_distance_nm = lead_distance_nm,
        .lead_distance_ft = lead_distance_ft,
        .time_to_turn_sec = time_to_turn_sec,
        .load_factor = load_factor,
        .standard_rate_bank = standard_rate_bank,
    };
}


// Output results as JSON
fn printJSON(turn: TurnData) void {
    std.debug.print( "{{\n", .{});
    std.debug.print( "  \"radius_nm\": {},\n", .{turn.radius_nm});
    std.debug.print( "  \"radius_ft\": {},\n", .{turn.radius_ft});
    std.debug.print( "  \"turn_rate_dps\": {},\n", .{turn.turn_rate_dps});
    std.debug.print( "  \"lead_distance_nm\": {},\n", .{turn.lead_distance_nm});
    std.debug.print( "  \"lead_distance_ft\": {},\n", .{turn.lead_distance_ft});
    std.debug.print( "  \"time_to_turn_sec\": {},\n", .{turn.time_to_turn_sec});
    std.debug.print( "  \"load_factor\": {},\n", .{turn.load_factor});
    std.debug.print( "  \"standard_rate_bank\": {}\n", .{turn.standard_rate_bank});
    std.debug.print( "}}\n", .{});
}


fn printUsage(program_name: []const u8) void {
    std.debug.print( "Usage: {s} <tas_kts> <bank_deg> <course_change_deg>\n\n", .{program_name});
    std.debug.print( "Arguments:\n", .{});
    std.debug.print( "  tas_kts          : True airspeed (knots)\n", .{});
    std.debug.print( "  bank_deg         : Bank angle (degrees)\n", .{});
    std.debug.print( "  course_change_deg: Course change (degrees)\n\n", .{});
    std.debug.print( "Example:\n", .{});
    std.debug.print( "  {s} 250 25 90\n", .{program_name});
    std.debug.print( "  (250 kts TAS, 25° bank, 90° turn)\n", .{});
}


pub fn main() u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var result: u8 = SUCCESS;
    var args = std.process.argsWithAllocator(alloc) catch {result = INIT_FAILED;};

    var program_name: []const u8 = undefined;

    var tas_kts: f64 = undefined;
    var bank_deg: f64 = undefined;
    var course_change_deg: f64 = undefined;

    var count: u32 = 0;
    while (args.next()) |item| : (count += 1) {
        if (0 == count) {program_name = item;}
        else if (1 == count) {result = parseFloat64(item, &tas_kts);}
        else if (2 == count) {result = parseFloat64(item, &bank_deg);}
        else if (3 == count) {result = parseFloat64(item, &course_change_deg);}
        else {result = INVALID_ARGS;}
    } else {
        if (3 >= count) {result = INVALID_ARGS;}
    }

    if (0.0 >= tas_kts) {
        std.debug.print( "Error: TAS must be positive\n", .{});
        result = ILLEGAL_VALUE;
    } else if (0.0 > bank_deg and 90.0 < bank_deg) {
        std.debug.print( "Error: Bank angle must be between 0 and 90 degrees\n", .{});
        result = ILLEGAL_VALUE;
    } else {
        // All inputs valid - calculate and output
        const turn = calculateTurnPerformance(tas_kts, bank_deg, course_change_deg);
        printJSON(turn);
        result = SUCCESS;
    }
    return result;
}