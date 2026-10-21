#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
inline int ScaleRequest(int amount, float multiplier, int available) {
    // Preserve every vanilla return, including sentinel/zero values, at x1.
    if (multiplier == 1 || amount <= 0) return amount;
    const double result = double(amount) * multiplier;
    // Vanilla may request goods which are still being produced. Never enlarge
    // that promise: additional cargo must exist and be unreserved already.
    const double cap = std::max(amount, std::min(available, 10000));
    return static_cast<int>(std::min(result, cap));
}
inline void ScaleExpected(float* expected, int before, int after) {
    if (expected && before > 0 && after != before && std::isfinite(*expected) && *expected > 0)
        *expected += float(after - before);
}
