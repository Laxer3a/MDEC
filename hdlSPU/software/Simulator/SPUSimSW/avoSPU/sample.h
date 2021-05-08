#pragma once
#include <cstdint>
#include <cstddef>

template <typename T>
T clamp(T number, size_t range) {
    if (number > range) number = range;
    return number;
}

template <typename T>
T clamp(T v, T min, T max) {
    if (v > max) {
        return max;
    } else if (v < min) {
        return min;
    } else {
        return v;
    }
}

template <typename T>
T clamp_top(T v, T top) {
    return v > top ? top : v;
}

template <typename T>
T clamp_bottom(T v, T bottom) {
    return v < bottom ? bottom : v;
}

// Basically an overflow safe int16_t
struct Sample {
    int16_t value;

    Sample operator*(const int16_t& b) const {  //
        return (value * b) >> 15;
    }
    Sample& operator*=(const int16_t& b) {
        value = (value * b) >> 15;
        return *this;
    }
    Sample operator+(const int16_t& b) const {  //
        return clamp<int32_t>(value + b, INT16_MIN, INT16_MAX);
    }
    Sample& operator+=(const int16_t& b) {
        value = clamp<int32_t>(value + b, INT16_MIN, INT16_MAX);
        return *this;
    }
    Sample operator-(const int16_t& b) const {  //
        return clamp<int32_t>(value - b, INT16_MIN, INT16_MAX);
    }
    Sample& operator-=(const int16_t& b) {
        value = clamp<int32_t>(value - b, INT16_MIN, INT16_MAX);
        return *this;
    }
    operator int16_t() const {  //
        return value;
    }
    Sample(int16_t v) : value(v) {}
    Sample() : value(0) {}
};