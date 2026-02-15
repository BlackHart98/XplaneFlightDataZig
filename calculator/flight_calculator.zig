const std = @import("std");

const SUCCESS: u8 = 0;
const INVALID_ARGS: u8 = 1;
const PARSE_FAILED: u8 = 2;
const SIMULATED: u8 = 3;
const INIT_FAILED: u8 = 4;
const CALCULATION_FAILED: u8 = 5;


// Fixed-size array limit (AV Rule 206: no dynamic allocation)
const max_ias_history: usize = 20;

// Mathematical constants (AV Rule 52: lowercase)
const deg_to_rad: f64 = std.math.pi / 180.0;
const rad_to_deg: f64 = 180.0 / std.math.pi;
const gravity: f64 = 9.80665;  // m/s²
const kts_to_ms: f64 = 0.514444;
const ft_to_m: f64 = 0.3048;
const m_to_ft: f64 = 3.28084;
const nm_to_ft: f64 = 6076.12;

// Calculation constants (AV Rule 151: no magic numbers)
const angle_wrap: f64 = 360.0;
const half_circle: f64 = 180.0;
const sqrt_two: f64 = 1.414;
const typical_glide_ratio: f64 = 12.0;
const best_glide_multiplier: f64 = 1.3;
const typical_vs: f64 = 60.0;
const energy_rate_divisor: f64 = 101.27;
const energy_trend_threshold: f64 = 50.0;
const energy_stable: i32 = 0;
const energy_increasing: i32 = 1;
const energy_decreasing: i32 = -1;
const two_point_zero: f64 = 2.0;
const hundred_percent: f64 = 100.0;
const min_history_for_stats: f64 = 2.0;

// JSF-compliant parse function (no exceptions)
fn parseFloat64(str: []const u8, result: *f64) u8 {
    var ret: u8 = SUCCESS;
    const float_num: ?f64 = std.fmt.parseFloat(f64, str) catch null;
    if (float_num) |item|{result.* = item;} 
    else {ret = PARSE_FAILED;}
    return ret;
}


const Vector2D = struct {
    x_pos: f64,
    y_pos: f64,
};

// Only used operators
fn subtractVector2D(v1: Vector2D, v2: Vector2D) Vector2D {
    return Vector2D{
        .x_pos = v1.x_pos - v2.x_pos,
        .y_pos = v1.y_pos - v2.y_pos,
    };
}
fn magnitude(vec: Vector2D) f64 {
    return std.math.sqrt(vec.x_pos * vec.x_pos + vec.y_pos * vec.y_pos);
}


// JSF-COMPLIANT: Iterative binomial coefficient calculation (n choose k)
// AV Rule 119: No recursion allowed
// AV Rule 113: Single exit point
// Uses iterative formula to avoid overflow: C(n,k) = ∏(i=1 to k) (n-k+i)/i
fn binomialCoefficient(n: u32, k: u32) u64 {
    var result: u64 = 0;  // Single exit point variable
    var temp_k = k;
    if (temp_k > n) {
        result = 0;
    } else if (temp_k == 0 and temp_k == n) {
        result = 1;
    } else if (temp_k == 1) {
        result = n;
    } else {
        // Optimize: C(n,k) = C(n, n-k), use smaller k
        if (temp_k > n - temp_k) temp_k = n - temp_k;
        
        // Iterative calculation to avoid stack overflow
        result = 1;
        for (1..(temp_k + 1)) |i|{
            result = result * (n - temp_k + i) / i;
        }
    }
    
    return result;  // Single exit point
}


// Normalize angle to 0-360 range
// Uses std.math.mod() for deterministic execution time (no variable-iteration loops)
// This is important for real-time and safety-critical systems where
// predictable worst-case execution time (WCET) is required
fn normalizeAngle(angle: f64, result_angle: *f64) u8 {
    var ret: u8 = SUCCESS;
    const float_num: ?f64 = std.math.mod(f64, angle, angle_wrap) catch null;
    if (float_num) |item|{result_angle.* = item;} 
    else {ret = CALCULATION_FAILED;}
    if (0.0 > result_angle.*) {
        result_angle.* += angle_wrap;
    }
    return ret;
}


// 1. Wind vector calculation
const WindData = struct {
    speed_kts: f64,
    direction_from: f64,  // deg, where wind comes FROM
    headwind: f64,
    crosswind: f64,
    gust_factor: f64,
};


// AV Rule 58: Long parameter lists formatted one per line
fn calculateWindVector(
    tas_kts: f64,
    gs_kts: f64,
    heading_deg: f64,
    track_deg: f64,
    ias_history: []const f64,
    history_size: usize,
    result_wind_data: *WindData
) u8 {
    var ret: u8 = SUCCESS;
    const heading_rad: f64 = heading_deg * deg_to_rad;
    const track_rad: f64 = track_deg * deg_to_rad;

    const air_vec = Vector2D{
        .x_pos = tas_kts * std.math.sin(heading_rad),
        .y_pos = tas_kts * std.math.cos(heading_rad),
    };

    const ground_vec = Vector2D{
        .x_pos = gs_kts * std.math.sin(track_rad),
        .y_pos = gs_kts * std.math.cos(track_rad),
    };

    const wind_vec = subtractVector2D(air_vec, ground_vec);

    const speed_kts = magnitude(wind_vec);

    // Wind direction (where FROM)
    const wind_dir_rad: f64 = std.math.atan2(wind_vec.x_pos, wind_vec.y_pos);
    var direction_from: f64 = undefined;
    var wind_from_rel: f64 = undefined;
    ret = normalizeAngle(wind_dir_rad * rad_to_deg, &direction_from);

    if (SUCCESS == ret){
        ret = normalizeAngle(direction_from - track_deg, &wind_from_rel);
        if (SUCCESS == ret){
            if (wind_from_rel > half_circle) wind_from_rel -= angle_wrap;
            const wind_from_rad: f64 = wind_from_rel * deg_to_rad;

            var gust_factor: f64 = undefined;
            if (history_size >= min_history_for_stats){
                var sum: f64 = 0.0;
                var sum_sq: f64 = 0.0;
                for (ias_history) |item| {
                    sum += item;
                    sum_sq += item * item;
                }
                const history_size_as_f: f64 = @floatFromInt(history_size);
                const mean: f64 = sum / history_size_as_f;
                const variance: f64 = (sum_sq / history_size_as_f) - (mean * mean);
                const std_dev: f64 = std.math.sqrt(variance);
                gust_factor = std_dev / mean;
            } else {
                gust_factor = 0.0;
            }

            result_wind_data.* = WindData{
                .speed_kts = speed_kts,
                .direction_from = direction_from,
                .headwind = -speed_kts * std.math.cos(wind_from_rad),
                .crosswind = speed_kts * std.math.sin(wind_from_rad),
                .gust_factor = gust_factor,
            };
        }
    }
    return ret;

}


// 3. Energy management
const EnergyData = struct {
    specific_energy_ft: f64,
    energy_rate_kts: f64,
    trend: i32,  // 1=increasing, 0=stable, -1=decreasing
};


fn calculateEnergy(tas_kts: f64, altitude_ft: f64, vs_fpm: f64) EnergyData {
    // Specific energy: Es = h + V²/(2g)
    const v_ms: f64 = tas_kts * kts_to_ms;
    const h_m: f64 = altitude_ft * ft_to_m;
    const kinetic_energy_m: f64 = (v_ms * v_ms) / (two_point_zero * gravity);
    const total_energy_m: f64 = h_m + kinetic_energy_m;
    const specific_energy_ft: f64 = total_energy_m * m_to_ft;
    
    // Energy rate (convert VS to equivalent airspeed change)
    const energy_rate_kts: f64 = vs_fpm / energy_rate_divisor;  // Simplified

    // Trend
    var trend: i32 = undefined;
    if (vs_fpm > energy_trend_threshold) {
        trend = energy_increasing;
    } else if (vs_fpm < -energy_trend_threshold) {
        trend = energy_decreasing;
    } else {
        trend = energy_stable;
    }
    return EnergyData{
        .specific_energy_ft = specific_energy_ft,
        .energy_rate_kts = energy_rate_kts,
        .trend = trend,
    };
}


// 2. Envelope margins
const EnvelopeMargins = struct{
    stall_margin_pct: f64,
    vmo_margin_pct: f64,
    mmo_margin_pct: f64,
    min_margin_pct: f64,
    load_factor: f64,
    corner_speed_kts: f64,
};


// AV Rule 58: Long parameter lists formatted one per line
fn calculateEnvelope(
    bank_deg: f64,
    ias_kts: f64,
    mach: f64,
    vso_kts: f64,
    vne_kts: f64,
    mmo: f64,
) EnvelopeMargins {
    // Load factor
    const bank_rad: f64 = bank_deg * deg_to_rad;
    const load_factor: f64 = 1.0 / std.math.cos(bank_rad);

    // Stall speed increases with load factor
    const vs_actual: f64 = vso_kts * std.math.sqrt(load_factor);
    const stall_margin_pct: f64 = ((ias_kts - vs_actual) / vs_actual) * hundred_percent;
    
    // VMO margin
    const vmo_margin_pct: f64 = ((vne_kts - ias_kts) / vne_kts) * hundred_percent;
    
    // MMO margin
    const mmo_margin_pct: f64 = ((mmo - mach) / mmo) * hundred_percent;
    
    // Minimum margin
    const min_margin_pct: f64 = std.sort.min(f64, &[_]f64{stall_margin_pct, vmo_margin_pct, mmo_margin_pct}, {}, std.sort.asc(f64)).?;
    
    // Corner speed estimate
    const corner_speed_kts: f64 = vs_actual * std.math.sqrt2;  // Vc ≈ Vs * sqrt(2)

    return EnvelopeMargins{
        .stall_margin_pct = stall_margin_pct,
        .vmo_margin_pct = vmo_margin_pct,
        .mmo_margin_pct = mmo_margin_pct,
        .min_margin_pct = min_margin_pct,
        .load_factor = load_factor,
        .corner_speed_kts = corner_speed_kts
    };
}


// 4. Glide reach
const GlideData = struct {
    still_air_range_nm: f64,
    wind_adjusted_range_nm: f64,
    glide_ratio: f64,
    best_glide_speed_kts: f64,
};


fn calculateGlideReach(agl_ft: f64, tas_kts: f64, headwind_kts: f64) GlideData { 
    // Assume typical L/D ratio of 12:1 for general aviation
    const glide_ratio: f64 = typical_glide_ratio;
    
    // Still air range
    const range_ft: f64 = agl_ft * glide_ratio;
    const still_air_range_nm: f64 = range_ft / nm_to_ft;
    
    // Wind adjustment (simplified)
    const wind_effect = headwind_kts / tas_kts;
    const wind_adjusted_range_nm = still_air_range_nm * (1.0 - wind_effect);
    
    return GlideData{
        .still_air_range_nm = still_air_range_nm,
        .glide_ratio = typical_glide_ratio,
        .wind_adjusted_range_nm = wind_adjusted_range_nm,
        .best_glide_speed_kts = best_glide_multiplier * typical_vs,
    };
}


// Output comprehensive JSON results
fn printJSONResults(wind: WindData, envelope: EnvelopeMargins, energy: EnergyData, glide: GlideData) void {
    std.debug.print( "{{\n", .{});
    
    // Wind
    std.debug.print( "  \"wind\": {{\n", .{});
    std.debug.print( "    \"speed_kts\": {},\n", .{wind.speed_kts});
    std.debug.print( "    \"direction_from\": {},\n", .{wind.direction_from});
    std.debug.print( "    \"headwind\": {},\n", .{wind.headwind});
    std.debug.print( "    \"crosswind\": {},\n", .{wind.crosswind});
    std.debug.print( "    \"gust_factor\": {}\n", .{wind.gust_factor});
    std.debug.print( "  }},\n", .{});
    
    // Envelope
    std.debug.print( "  \"envelope\": {{\n", .{});
    std.debug.print( "    \"stall_margin_pct\": {},\n", .{envelope.stall_margin_pct});
    std.debug.print( "    \"vmo_margin_pct\": {},\n", .{envelope.vmo_margin_pct});
    std.debug.print( "    \"mmo_margin_pct\": {},\n", .{envelope.mmo_margin_pct});
    std.debug.print( "    \"min_margin_pct\": {},\n", .{envelope.min_margin_pct});
    std.debug.print( "    \"load_factor\": {},\n", .{envelope.load_factor});
    std.debug.print( "    \"corner_speed_kts\": {}\n", .{envelope.corner_speed_kts});
    std.debug.print( "  }},\n", .{});
    
    // Energy
    std.debug.print( "  \"energy\": {{\n", .{});
    std.debug.print( "    \"specific_energy_ft\": {},\n", .{energy.specific_energy_ft});
    std.debug.print( "    \"energy_rate_kts\": {},\n", .{energy.energy_rate_kts});
    std.debug.print( "    \"trend\": {}\n", .{energy.trend});
    std.debug.print( "  }},\n", .{});
    
    // Glide
    std.debug.print( "  \"glide\": {{\n", .{});
    std.debug.print( "    \"still_air_range_nm\": {},\n", .{glide.still_air_range_nm});
    std.debug.print( "    \"wind_adjusted_range_nm\": {},\n", .{glide.wind_adjusted_range_nm});
    std.debug.print( "    \"glide_ratio\": {},\n", .{glide.glide_ratio});
    std.debug.print( "    \"best_glide_speed_kts\": {}\n", .{glide.best_glide_speed_kts});
    std.debug.print( "  }},\n", .{});
    
    // Alternate airport combinations (JSF-compliant iterative binomial)
    std.debug.print( "  \"alternate_airports\": {{\n", .{});
    std.debug.print( "    \"combinations_5_choose_2\": {},\n", .{binomialCoefficient(5, 2)});
    std.debug.print( "    \"combinations_10_choose_3\": {},\n", .{binomialCoefficient(10, 3)});
    std.debug.print( "    \"note\": \"Iterative binomial calculation (JSF-compliant, no recursion)\"\n", .{});
    std.debug.print( "  }}\n", .{});
    
    std.debug.print( "}}\n", .{});
}


const SensorHistoryBuffer = struct {
    //  The pre-allocated, fixed-size buffer.
    data: []f64 = undefined,
    head_index: usize = 0, 
    current_size: usize = 0,

    const Self = @This();
    fn init(buf: []f64) SensorHistoryBuffer{
        @memset(buf, 0.0);
        return SensorHistoryBuffer {
            .data = buf,
            .head_index = 0, 
            .current_size = 0,
        };
    }

    fn addReading(self: *Self, new_ias: f64) void {
        self.data[self.head_index] = new_ias;
        
        // Move the head to the next position, wrapping around if necessary.
        self.head_index = (self.head_index + 1) % max_ias_history;
        
        // The buffer size grows until it's full.
        if (self.current_size < max_ias_history) {
            self.current_size += 1;
        }
    }

    fn getDataSlice(self: *Self) []f64 {
        return self.data;
    }
    
    fn getSize(self: *Self) usize {
        return self.current_size;
    }
};


pub fn main() u8{
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var ret: u8 = SUCCESS;
    var args = std.process.argsWithAllocator(alloc) catch {ret = INIT_FAILED;};

    var buffer: [max_ias_history]f64 = undefined;

    var program_name: []const u8 = undefined;

    var tas_kts: f64 = undefined;
    var gs_kts: f64 = undefined; 
    var heading: f64 = undefined;
    var track: f64 = undefined;
    var ias_kts: f64 = undefined;
    var mach: f64 = undefined;
    var altitude_ft: f64 = undefined;
    var agl_ft: f64 = undefined;
    var vs_fpm: f64 = undefined; 
    var weight_kg: f64 = undefined; 
    var bank_deg: f64 = undefined; 
    var vso_kts: f64 = undefined; 
    var vne_kts: f64 = undefined;
    var mmo: f64 = undefined;

    var count: u32 = 0;
    while (args.next()) |item| : (count += 1) {
        if (0 == count) {program_name = item;}
        else if (1 == count) {ret = parseFloat64(item, &tas_kts);}
        else if (2 == count) {ret = parseFloat64(item, &gs_kts);}
        else if (3 == count) {ret = parseFloat64(item, &heading);}
        else if (4 == count) {ret = parseFloat64(item, &track);}
        else if (5 == count) {ret = parseFloat64(item, &ias_kts);}
        else if (6 == count) {ret = parseFloat64(item, &mach);}
        else if (7 == count) {ret = parseFloat64(item, &altitude_ft);}
        else if (8 == count) {ret = parseFloat64(item, &agl_ft);}
        else if (9 == count) {ret = parseFloat64(item, &vs_fpm);}
        else if (10 == count) {ret = parseFloat64(item, &weight_kg);}
        else if (11 == count) {ret = parseFloat64(item, &bank_deg);}
        else if (12 == count) {ret = parseFloat64(item, &vso_kts);}
        else if (13 == count) {ret = parseFloat64(item, &vne_kts);}
        else if (14 == count) {ret = parseFloat64(item, &mmo);}
        else {ret = INVALID_ARGS;}
    } else {
        if (4 >= count) {ret = INVALID_ARGS;}
    }

    if (SUCCESS == ret){
        var ias_buffer = SensorHistoryBuffer.init(&buffer);
        var result_wind_data: WindData = undefined;
        for (0..30) |i| {
            const temp_: f64 = @floatFromInt(i % 7);
            const new_reading = 150.0 + temp_ - 3.0;
            ias_buffer.addReading(new_reading);
        }
        ret = calculateWindVector(
            tas_kts, gs_kts, heading, track,
            ias_buffer.getDataSlice(), ias_buffer.getSize(), 
            &result_wind_data
        );
        if (SUCCESS == ret){
            // 2. Calculate envelope margins
            const envelope = calculateEnvelope(
                bank_deg, ias_kts, mach,
                vso_kts, vne_kts, mmo
            );

            // 3. Calculate energy state
            const energy = calculateEnergy(tas_kts, altitude_ft, vs_fpm);
            // 4. Calculate glide reach
            const glide = calculateGlideReach(agl_ft, tas_kts, result_wind_data.headwind);

            // Output JSON
            printJSONResults(result_wind_data, envelope, energy, glide);
        }
    }
    return ret;
}