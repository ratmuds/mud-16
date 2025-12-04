#include "Vppu.h"
#include "verilated.h"
#include "raylib.h"
#include <vector>
#include <cstdint>
#include <cstring>

const int WIDTH  = 320;
const int HEIGHT = 240;
const int SCALE  = 2;
const int RAM_SIZE = 1024 * 1024;

// -----------------------------------------------------------------------------
// System Simulation Class
// -----------------------------------------------------------------------------
class Mud16System {
public:
    Vppu* ppu;
    std::vector<uint8_t> ram;
    uint64_t tick_count = 0;

    // CPU Simulation State
    bool cpu_using_bus = true;
    int  cpu_grant_delay_counter = 0;

    Mud16System() {
        ppu = new Vppu;
        ram.resize(RAM_SIZE);
        memset(ram.data(), 0, RAM_SIZE);
        init_ram_pattern();

        // Initial pin states
        ppu->clk = 0;
        ppu->reset = 1;
        ppu->cpu_bg_n = 1; // Not granted
        ppu->cpu_as_n = 1; // Address strobe inactive
        ppu->eval();
    }

    ~Mud16System() {
        delete ppu;
    }

    void init_ram_pattern() {
        for (int y = 0; y < HEIGHT; y++) {
            for (int x = 0; x < WIDTH; x++) {
                int addr = (y * WIDTH + x) * 4;
                if (addr + 3 < RAM_SIZE) {
                    ram[addr]     = (uint8_t)(x & 0xFF);
                    ram[addr + 1] = (uint8_t)(y & 0xFF);
                    ram[addr + 2] = (uint8_t)((x + y) & 0xFF);
                    ram[addr + 3] = 0xFF;
                }
            }
        }
    }

    void reset() {
        ppu->reset = 1;
        tick();
        tick();
        ppu->reset = 0;
    }

    // Run one clock cycle
    void tick() {
        // 1. Rising Edge
        ppu->clk = 1;
        ppu->eval();

        // 2. Simulate External Hardware (CPU & RAM)
        simulate_cpu_arbitration();
        simulate_memory();

        // 3. Falling Edge
        ppu->clk = 0;
        ppu->eval();

        tick_count++;
    }

private:
    void simulate_cpu_arbitration() {
        // --- CPU Logic ---

        // If PPU requests bus (BR low)
        if (ppu->ppu_br_n == 0) {
            // CPU takes some time to finish current instruction and release bus
            if (cpu_grant_delay_counter < 4) {
                cpu_grant_delay_counter++;
            } else {
                // Grant the bus
                ppu->cpu_bg_n = 0;

                // Release AS (Address Strobe) to indicate bus cycle finished
                ppu->cpu_as_n = 1;
            }
        } else {
            // No request, reset logic
            ppu->cpu_bg_n = 1;
            cpu_grant_delay_counter = 0;

            // If PPU is not master, CPU is master, so it might be pulsing AS
            if (ppu->ppu_bgack_n == 1) {
                // Simulate CPU activity (randomly pulsing AS)
                ppu->cpu_as_n = (tick_count % 4 == 0) ? 0 : 1;
            }
        }
    }

    void simulate_memory() {
        // Only respond if PPU is actually driving the bus
        if (ppu->ppu_bgack_n == 0 && ppu->cpu_bus_oe_n == 1) {

            if (ppu->mem_read) {
                uint32_t addr = ppu->mem_addr;
                if (addr + 3 < RAM_SIZE) {
                    ppu->mem_rdata = ram[addr] // 32 bit access
                                   | (ram[addr + 1] << 8)
                                   | (ram[addr + 2] << 16)
                                   | (ram[addr + 3] << 24);
                }
            }

            if (ppu->mem_write) {
                uint32_t addr = ppu->mem_addr;
                uint32_t data = ppu->mem_wdata;
                if (addr + 3 < RAM_SIZE) {
                    ram[addr]     = data & 0xFF; // 32 bit write
                    ram[addr + 1] = (data >> 8) & 0xFF;
                    ram[addr + 2] = (data >> 16) & 0xFF;
                    ram[addr + 3] = (data >> 24) & 0xFF;
                }
            }
        } else {
            // Bus is floating or driven by CPU (we ignore CPU memory access for this sim)
            ppu->mem_rdata = 0;

            // Log warning
            //printf("Warning: uhhh memory access attempted by PPU while CPU is driving the bus or bus is floating at tick %llu\n", tick_count);
        }
    }
};

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------
int main() {
    Verilated::traceEverOn(true);

    Mud16System sys;
    sys.reset();

    InitWindow(WIDTH * SCALE, HEIGHT * SCALE, "mud-16 PPU");
    SetTargetFPS(60);

    // Framebuffer setup
    Image fbImage = GenImageColor(WIDTH, HEIGHT, BLACK);
    Texture2D fbTexture = LoadTextureFromImage(fbImage);
    unsigned char* pixels = (unsigned char*)fbImage.data;

    while (!WindowShouldClose()) {

        // Run some cycles
        int cycles_per_frame = WIDTH * HEIGHT * 5;

        for (int i = 0; i < cycles_per_frame; i++) {
            sys.tick();

            // Capture pixel data
            static int p_idx = 0;
            if (p_idx < WIDTH * HEIGHT * 4) {
                pixels[p_idx++] = sys.ppu->pixel_r;
                pixels[p_idx++] = sys.ppu->pixel_g;
                pixels[p_idx++] = sys.ppu->pixel_b;
                pixels[p_idx++] = 255;
            }
            if (p_idx >= WIDTH * HEIGHT * 4) p_idx = 0;
        }

        UpdateTexture(fbTexture, pixels);

        BeginDrawing();
        ClearBackground(BLACK);
        DrawTextureEx(fbTexture, (Vector2){0, 0}, 0.0f, SCALE, WHITE);

        // Debug Overlay
        DrawFPS(10, 10);

        // Bus Status Indicator
        bool fpga_has_bus = (sys.ppu->ppu_bgack_n == 0);
        DrawRectangle(10, 30, 20, 20, fpga_has_bus ? GREEN : RED);
        DrawText(fpga_has_bus ? "FPGA MASTER" : "CPU MASTER", 35, 32, 20, WHITE);

        EndDrawing();
    }

    UnloadTexture(fbTexture);
    CloseWindow();

    return 0;
}
