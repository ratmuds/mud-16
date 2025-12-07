#pragma once

#include <cstdint>
#include <cstddef>
#include <vector>

//
// VRAM layout (within the shared RAM of the testbench)
//
// 0x00000–0x00FFF : palettes (8 palettes × 16 colors × 2 bytes = 256 bytes, padded)
// 0x01000–0x04FFF : tiles    (32 bytes per tile; room for 1K tiles = 32 KB)
// 0x05000–0x05FFF : BG map   (64×64 = 4096 bytes)
// 0x06000–0x06FFF : UI map   (40×10 = 400 bytes; padded to 4 KB)
// 0x07000–0x073FF : OAM      (128 × 4-byte entries = 512 bytes; padded to 1 KB)
// 0x08000–...     : game stuff idk
//

namespace vram_init {

struct Layout {
    static constexpr uint32_t palette_base   = 0x00000;
    static constexpr uint32_t palette_bytes  = 0x00100; // padded

    static constexpr uint32_t tile_base      = 0x01000;
    static constexpr uint32_t tile_bytes     = 0x008000; // 32 KB reserved

    static constexpr uint32_t bg_map_base    = 0x05000;
    static constexpr uint32_t bg_map_bytes   = 0x01000; // 4 KB

    static constexpr uint32_t ui_map_base    = 0x06000;
    static constexpr uint32_t ui_map_bytes   = 0x01000; // 4 KB padded

    static constexpr uint32_t oam_base       = 0x07000;
    static constexpr uint32_t oam_bytes      = 0x00400; // 1 KB padded
};

// High-level content descriptors
struct Params {
    static constexpr int palette_count      = 8;
    static constexpr int colors_per_palette = 16;
    static constexpr int bytes_per_color    = 2;   // 12-bit stored in 16-bit slot

    static constexpr int tile_dim_px        = 8;
    static constexpr int tile_bpp           = 4;
    static constexpr int bytes_per_tile     = 32;

    static constexpr int bg_map_w_tiles     = 64;
    static constexpr int bg_map_h_tiles     = 64;

    static constexpr int ui_map_w_tiles     = 40;
    static constexpr int ui_map_h_tiles     = 10;

    static constexpr int oam_entries        = 128;
    static constexpr int bytes_per_oam      = 4;
};

// Writes the demo palettes, tiles, BG map, UI map, and OAM into RAM
void load(std::vector<uint8_t>& ram);
void load(uint8_t* ram, std::size_t ram_size);

} // namespace vram_init
