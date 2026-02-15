#!/bin/bash
# Test all Zig calculators with example data

echo "===================================="
echo "X-Plane Flight Calculator Test Suite"
echo "===================================="

# Show which version is active
if [ -f .active_version ]; then
    VERSION=$(cat .active_version)
    echo "Testing: $VERSION version"
else
    echo "Testing: Unknown version (run 'make compliant' or 'make non-compliant')"
fi

echo "===================================="
echo ""

echo "1. Turn Performance Calculator"
echo "   Input: 250 kts TAS, 25° bank, 90° turn"
./zig-out/bin/turn_calculator 250 25 90
echo ""

echo "2. VNAV Calculator"
echo "   Input: FL350 to 10000 ft, 100nm away, 450 kts GS"
./zig-out/bin/vnav_calculator 35000 10000 100 450 -1500
echo ""

echo "3. Density Altitude Calculator"
echo "   Input: 5000 ft PA, 25°C OAT, 150 IAS, 170 TAS"
./zig-out/bin/density_altitude_calculator 5000 25 150 170
echo ""

echo "4. Flight Performance Calculator (comprehensive)"
echo "   Input: Full flight envelope parameters"
./zig-out/bin/flight_calculator 250 245 90 95 220 0.65 35000 35000 -500 75000 5 120 250 0.82
echo ""

echo "===================================="
echo "All tests complete!"
echo "===================================="
