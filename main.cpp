#include "Vppu.h"
#include "verilated.h"
#include "raylib.h"
#include <cstring>

const int WIDTH  = 320;
const int HEIGHT = 240;
const int SCALE  = 2;  // Window scale factor
const int RAM_SIZE = 1024 * 1024;  // 1 MB

int main() {
    Verilated::traceEverOn(true);
    Vppu *top = new Vppu;

    // Allocate 1 MB of RAM
    static unsigned char ram[RAM_SIZE];
    memset(ram, 0, RAM_SIZE);

    // Initialize RAM with a super cool pattern frfr
    for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
            int addr = (y * WIDTH + x) * 4;  // 4 bytes per pixel location
            if (addr + 3 < RAM_SIZE) {
                // Create a colorful pattern
                ram[addr]     = (unsigned char)(x & 0xFF);         // R: horizontal gradient
                ram[addr + 1] = (unsigned char)(y & 0xFF);         // G: vertical gradient
                ram[addr + 2] = (unsigned char)((x + y) & 0xFF);   // B: diagonal gradient
                ram[addr + 3] = 0xFF;                               // Alpha (unused)
            }
        }
    }

    // Initialize Raylib window
    InitWindow(WIDTH * SCALE, HEIGHT * SCALE, "mud-16 PPU");
    SetTargetFPS(60);

    // Create a texture to display the framebuffer
    Image framebufferImage = {
        .data = nullptr,
        .width = WIDTH,
        .height = HEIGHT,
        .mipmaps = 1,
        .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8
    };
    framebufferImage.data = MemAlloc(WIDTH * HEIGHT * 3);
    Texture2D framebufferTexture = LoadTextureFromImage(framebufferImage);

    unsigned char* framePixels = (unsigned char*)framebufferImage.data;

    // Reset sequence
    top->clk = 0;
    top->reset = 1;
    top->mem_rdata = 0;
    top->eval();
    top->clk = 1;
    top->eval();
    top->clk = 0;
    top->reset = 0;
    top->eval();

    while (!WindowShouldClose()) {
        // Simulate one full frame
        int idx = 0;
        for (int y = 0; y < HEIGHT; y++) {
            for (int x = 0; x < WIDTH; x++) {
                // Clock low phase
                top->clk = 0;
                top->eval();

                // Handle memory read requests from PPU
                if (top->mem_read) {
                    uint32_t addr = top->mem_addr;
                    if (addr + 3 < RAM_SIZE) {
                        // Read 32-bit word (little-endian)
                        top->mem_rdata = ram[addr]
                                       | (ram[addr + 1] << 8)
                                       | (ram[addr + 2] << 16)
                                       | (ram[addr + 3] << 24);
                    } else {
                        top->mem_rdata = 0;
                    }
                }

                // Handle memory write requests from PPU
                if (top->mem_write) {
                    uint32_t addr = top->mem_addr;
                    uint32_t data = top->mem_wdata;
                    if (addr + 3 < RAM_SIZE) {
                        // Write 32-bit word (little-endian)
                        ram[addr]     = data & 0xFF;
                        ram[addr + 1] = (data >> 8) & 0xFF;
                        ram[addr + 2] = (data >> 16) & 0xFF;
                        ram[addr + 3] = (data >> 24) & 0xFF;
                    }
                }

                // Clock high phase
                top->clk = 1;
                top->eval();

                // Store pixel in framebuffer
                framePixels[idx++] = top->pixel_r;
                framePixels[idx++] = top->pixel_g;
                framePixels[idx++] = top->pixel_b;
            }
        }

        // Update texture with new frame data
        UpdateTexture(framebufferTexture, framePixels);

        // Draw
        BeginDrawing();
        ClearBackground(BLACK);
        DrawTextureEx(framebufferTexture, (Vector2){0, 0}, 0.0f, SCALE, WHITE);
        DrawFPS(10, 10);
        EndDrawing();
    }

    // Cleanup
    UnloadTexture(framebufferTexture);
    MemFree(framebufferImage.data);
    CloseWindow();

    delete top;
    return 0;
}
