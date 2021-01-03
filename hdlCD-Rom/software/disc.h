/*

*/

#pragma once

#include <stdint.h>

struct File;

#ifndef MAXTRACK
#define MAXTRACK 100
#endif

#ifndef MAXINDEX
#define MAXINDEX 100
#endif

enum TrackType { TRACK_TYPE_UNKNOWN, TRACK_TYPE_AUDIO, TRACK_TYPE_DATA };

typedef struct u24_ {
	uint8_t d[3];
} u24;

struct TrackEXT {
    struct File* file;
    uint32_t     fileOffset;  // offset in sectors within the disc at which this file begins
};

struct Track {
    u24			size;                        // size of the track in sectors, including pregaps and postgaps
    u24			indices[2];                  // each index is an absolute value in sectors from the beginning
    u24			postgap;                    // size of the postgap in sectors
    int8_t   indexCount;
    int8_t /*enum TrackType*/ trackType; // type
};

struct Disc {
    struct Track tracks[MAXTRACK];  // track 0 isn't valid; technically can be considered the lead-in
    char catalog[14];
    char isrc[13];
    int8_t trackCount;
};

struct DiscEXT {
    struct TrackEXT tracks[MAXTRACK/*100*/]; // 1..99 used, track 0 isn't valid; technically can be considered the lead-in
};

uint8_t parseTOC(const char *filename, struct Disc* pDisc, struct DiscEXT* pDiscEXT);
