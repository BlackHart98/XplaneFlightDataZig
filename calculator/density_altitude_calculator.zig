const std = @import("std");

const SUCCESS: u8 = 0;
const INVALID_ARGS: u8 = 1;
const PARSE_FAILED: u8 = 2;
const SIMULATED: u8 = 3;
const INIT_FAILED = 4;


// Number base
const base_10 = 10;

// Physical constants (AV Rule 52: lowercase)
const sea_level_temp_c = 15.0;
const temp_lapse_rate = 0.0019812;    // °C per foot (standard lapse rate)
const kelvin_offset = 273.15;
const density_alt_factor = 120.0;
const pressure_altitude_constant = 6.8756e-6;
const pressure_altitude_exponent = 5.2559;
const min_ias_for_ratio = 10.0;

// Validation ranges
const min_altitude_ft = -2000.0;
const max_altitude_ft = 60000.0;
const min_temperature_c = -60.0;
const max_temperature_c = 60.0;


const DensityAltitudeData = struct {
    density_altitude_ft: f64,      // Density altitude
    pressure_altitude_ft: f64,     // Pressure altitude (from setting)
    air_density_ratio: f64,        // σ (sigma) - ratio to sea level
    temperature_deviation_c: f64,  // Deviation from ISA
    performance_loss_pct: f64,     // % performance loss vs sea level
    eas_kts: f64,                  // Equivalent airspeed
    tas_to_ias_ratio: f64,         // TAS/IAS ratio
    pressure_ratio: f64,           // Pressure ratio vs sea level
};


// JSF-compliant parse function (no exceptions)
fn parseFloat64(str: []const u8, result: *f64) u8 {
    var ret: u8 = SUCCESS;
    const float_num: ?f64 = std.fmt.parseFloat(f64, str) catch null;
    if (float_num) |item|{result.* = item;} 
    else {ret = PARSE_FAILED;}
    return ret;
}



fn parseInt32(str: []const u8, result: *i32) u8{
    var ret: u8 = SUCCESS;
    const int_num: ?i32 = std.fmt.parseInt(i32, str, base_10) catch null;
    if (int_num) |item|{result.* = item;} 
    else {ret = PARSE_FAILED;}
    return ret;
}


// Calculate ISA temperature at given pressure altitude
fn isaTemperatureC(pressure_altitude_ft: f64) f64 {
    return sea_level_temp_c - (temp_lapse_rate * pressure_altitude_ft);
}


// Calculate density altitude using exact formula
// DA = PA + [120 * (OAT - ISA)]
fn calculateDensityAltitude(pressure_altitude_ft: f64, oat_celsius: f64) f64 {
    // ISA temperature at pressure altitude
    const isa_temp = isaTemperatureC(pressure_altitude_ft);
    
    // Temperature deviation from ISA
    const temp_deviation = oat_celsius - isa_temp;
    
    // Density altitude approximation (good to about 1% accuracy)
    const density_altitude = pressure_altitude_ft + (density_alt_factor * temp_deviation);
    
    return density_altitude;
}


// Calculate air density ratio (sigma)
// density_ratio = rho / rho_0
fn calculateDensityRatio(pressure_altitude_ft: f64, oat_celsius: f64) f64 {
    // Convert to absolute temperature
    const temp_k: f64 = oat_celsius + kelvin_offset;
    const sea_level_temp_k = sea_level_temp_c + kelvin_offset;
    
    // Pressure ratio (using standard atmosphere)
    const pressure_ratio = std.math.pow(f64, 1.0 - pressure_altitude_constant * pressure_altitude_ft, pressure_altitude_exponent);
    
    // Temperature ratio
    const temp_ratio = sea_level_temp_k / temp_k;
    
    // Density ratio: σ = (P/P₀) * (T₀/T)
    const sigma = pressure_ratio * temp_ratio;
    
    return sigma;
}


// Calculate Equivalent Airspeed (EAS)
// EAS = TAS * sqrt(σ)
fn calculateEas(tas_kts: f64, sigma: f64) f64 {
    return tas_kts * std.math.sqrt(sigma);
}


// Calculate complete density altitude data
fn calculateDensityAltitudeData(pressure_altitude_ft: f64, oat_celsius: f64, ias_kts: f64, tas_kts: f64) DensityAltitudeData {
    // Air density ratio
    const air_density_ratio = calculateDensityRatio(pressure_altitude_ft, oat_celsius);
    
    return .{
        .pressure_altitude_ft = pressure_altitude_ft,
        .density_altitude_ft = calculateDensityAltitude(pressure_altitude_ft, oat_celsius),
        .temperature_deviation_c = oat_celsius - isaTemperatureC(pressure_altitude_ft),
        .air_density_ratio = calculateDensityRatio(pressure_altitude_ft, oat_celsius),
        .performance_loss_pct = (1.0 - air_density_ratio) * 100.0,
        .eas_kts = calculateEas(tas_kts, air_density_ratio),
        .tas_to_ias_ratio = if (ias_kts > min_ias_for_ratio) tas_kts / ias_kts else 1.0,
        .pressure_ratio = std.math.pow(f64, 1.0 - pressure_altitude_constant * pressure_altitude_ft, pressure_altitude_exponent)
    };
}


// Output results as JSON
fn printJSON(da: DensityAltitudeData) void {
    std.debug.print("{{\n", .{});
    std.debug.print("  \"density_altitude_ft\": {},\n", .{da.density_altitude_ft});
    std.debug.print("  \"pressure_altitude_ft\": {},\n", .{da.pressure_altitude_ft});
    std.debug.print("  \"air_density_ratio\": {},\n", .{da.air_density_ratio});
    std.debug.print("  \"temperature_deviation_c\": {},\n", .{da.temperature_deviation_c});
    std.debug.print("  \"performance_loss_pct\": {},\n", .{da.performance_loss_pct});
    std.debug.print("  \"eas_kts\": {},\n", .{da.eas_kts});
    std.debug.print("  \"tas_to_ias_ratio\": {},\n", .{da.tas_to_ias_ratio});
    std.debug.print("  \"pressure_ratio\": {}\n", .{da.pressure_ratio});
    std.debug.print("}}\n", .{});
}


fn printUsage(program_name: []const u8) void {
    std.debug.print( "Usage: {s} <pressure_alt_ft> <oat_celsius> <ias_kts> <tas_kts> [force_error]\n\n", .{program_name});
    std.debug.print( "Arguments:\n", .{});
    std.debug.print( "  pressure_alt_ft : Pressure altitude (feet)\n", .{});
    std.debug.print( "  oat_celsius     : Outside air temperature (°C)\n", .{});
    std.debug.print( "  ias_kts        : Indicated airspeed (knots)\n", .{});
    std.debug.print( "  tas_kts        : True airspeed (knots)\n", .{});
    std.debug.print( "  force_error    : Optional, 1 to simulate error (default: 0)\n\n", .{});
    std.debug.print( "Example:\n", .{});
    std.debug.print( "  {s} 5000 25 150 170\n", .{program_name});
    std.debug.print( "  (5000 ft PA, 25°C OAT, 150 kts IAS, 170 kts TAS)\n", .{});
}


pub fn main() u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var result: u8 = SUCCESS;
    var args = std.process.argsWithAllocator(alloc) catch {result = INIT_FAILED;};

    var program_name: []const u8 = undefined;

    var pressure_alt_ft: f64 = undefined;
    var oat_celsius: f64 = undefined;
    var ias_kts: f64 = undefined;
    var tas_kts: f64 = undefined;
    var force_error: i32 = 0;

    var count: u32 = 0;
    while (args.next()) |item| : (count += 1) {
        if (0 == count) {program_name = item;}
        else if (1 == count) {result = parseFloat64(item, &pressure_alt_ft);}
        else if (2 == count) {result = parseFloat64(item, &oat_celsius);}
        else if (3 == count) {result = parseFloat64(item, &ias_kts);}
        else if (4 == count) {result = parseFloat64(item, &tas_kts);}
        else if (5 == count) {result = parseInt32(item, &force_error);}
        else {result = INVALID_ARGS;}
    } else {
        if (4 >= count) {result = INVALID_ARGS;}
    }

    if (1 == force_error) {
        std.debug.print( "Error: CRITICAL: Required dataref 'sim/weather/isa_deviation' not found in X-Plane API\n", .{});
        result = SIMULATED;
    }  
    if (SUCCESS == result){
        // Validate inputs
        if (pressure_alt_ft < min_altitude_ft or pressure_alt_ft > max_altitude_ft) {
            std.debug.print( "Warning: Pressure altitude outside typical range\n", .{});
        }

        if (oat_celsius < min_temperature_c or oat_celsius > max_temperature_c) {
            std.debug.print( "Warning: Temperature outside typical range\n", .{});
        }

        // Calculate and output results
        const da = calculateDensityAltitudeData(pressure_alt_ft, oat_celsius, ias_kts, tas_kts);
        printJSON(da);
        result = SUCCESS;
    }

    if ((SUCCESS != result) and (SIMULATED != result)) {
        printUsage(program_name);
    }

    return result;
}