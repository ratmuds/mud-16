module ppu #(
    parameter DISP_WIDTH  = 320,
    parameter DISP_HEIGHT = 240,


    parameter MAX_OBJECTS = 128,

    parameter MAX_PALETTES = 8,
    parameter PALETTE_MEM_OFFSET = 18'h00000,
    parameter TILE_MEM_OFFSET    = 18'h01000,
    parameter BG_MAP_MEM_OFFSET  = 18'h05000,
    parameter UI_MAP_MEM_OFFSET  = 18'h06000,
    parameter OAM_MEM_OFFSET     = 18'h07000,

    // Memory timing
    parameter BUS_READ_LATENCY = 1

) (
    input  logic clk,
    input  logic reset,

    // Pixel outputs (VGA interface)
    output logic [7:0] pixel_r,
    output logic [7:0] pixel_g,
    output logic [7:0] pixel_b,
    output logic       pixel_sync,

    // 68000 Bus Arbitration Signals
    input  logic       cpu_bg_n,      // Bus Grant (Active Low) from CPU
    input  logic       cpu_as_n,      // Address Strobe (Active Low) from CPU
    output logic       ppu_br_n,      // Bus Request (Active Low) to CPU
    output logic       ppu_bgack_n,   // Bus Grant Acknowledge (Active Low) to CPU

    // Level Shifter Control
    output logic       cpu_bus_oe_n,  // Output Enable for CPU level shifters (Active Low = CPU drives bus)

    // Memory interface (Shared Bus)
    output logic [19:0] mem_addr,
    input  logic [15:0] mem_rdata,
    output logic [15:0] mem_wdata,
    output logic        mem_read,
    output logic        mem_write
);

    // -------------------------------------------------------------------------
    // Bus Arbitration State Machine
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE,
        REQUEST_BUS,
        SEIZE_BUS,
        BUS_MASTER,
        READ_REQ,
        READ_WAIT,
        WRITE_REQ,
        WRITE_WAIT,
        RELEASE_BUS
    } bus_state_t;

    bus_state_t bus_state;
    reg  [7:0]  bus_wait_cnt;
    reg  [15:0] bus_rdata_latched;
    reg  [15:0] bus_wdata_latched;
    reg  [19:0] bus_addr_latched;
    reg         bus_op_done;

    // Internal requests
    logic want_bus;
    logic bus_req_read;
    logic bus_req_write;
    logic need_mem_refresh;
    logic mem_refreshed;

    // Memory arrays
    reg [11:0] palette [0:7][0:15];      // 8 palettes, 16 colors each, 12-bit RGB
    reg [7:0]  tile_memory [0:16383];    // 512 tiles * 32 bytes = 16KB
    reg [31:0] oam [0:MAX_OBJECTS-1];    // Object Attribute Memory

    reg [7:0]  bg_tile_map [0:4095];     // Background tile map (64x64 tiles = 4096 bytes)
    reg [2:0]  bg_palette;               // Background palette index

    reg [7:0]  ui_tile_map [0:399];      // UI tile map (40x10 tiles = 400 bytes; UI only at the top and bottom)
    reg [2:0]  ui_top_palette;           // UI palette index (top)
    reg [2:0]  ui_bottom_palette;        // UI palette index (bottom)

    // Memory Refresh FSM signals
    typedef enum logic [3:0] {
        REFRESH_IDLE,
        REFRESH_PALETTES,
        REFRESH_WAIT_PALETTE,
        REFRESH_TILES,
        REFRESH_WAIT_TILE,
        REFRESH_BG_MAP,
        REFRESH_WAIT_BG_MAP,
        REFRESH_UI_MAP,
        REFRESH_WAIT_UI_MAP,
        REFRESH_OAM,
        REFRESH_WAIT_OAM_LOW,
        REFRESH_WAIT_OAM_HIGH,
        REFRESH_DONE
    } refresh_state_t;

    refresh_state_t refresh_state;
    logic refresh_wait_mem;
    logic [3:0] refresh_palette;

    // MEMORY FSM

    always_ff @(posedge clk) begin
        if (reset) begin
            mem_addr          <= 0;
            mem_wdata         <= 0;
            mem_read          <= 0;
            mem_write         <= 0;
            cpu_bus_oe_n      <= 0; // Default: CPU enabled
            ppu_br_n          <= 1;
            ppu_bgack_n       <= 1;
            bus_state         <= IDLE;
            bus_wait_cnt      <= 0;
            bus_rdata_latched <= 0;
            bus_op_done       <= 0;
        end else begin
            // default strobes low each cycle
            mem_read  <= 0;
            mem_write <= 0;

            case (bus_state)
                IDLE: begin
                    ppu_br_n     <= 1;
                    ppu_bgack_n  <= 1;
                    cpu_bus_oe_n <= 0; // CPU drives bus
                    if (want_bus) begin
                        ppu_br_n  <= 0;
                        bus_state <= REQUEST_BUS;
                    end
                end

                REQUEST_BUS: begin
                    ppu_br_n <= 0; // hold request
                    if (!cpu_bg_n && cpu_as_n) begin
                        bus_state <= SEIZE_BUS;
                    end
                end

                SEIZE_BUS: begin
                    ppu_bgack_n  <= 0; // take bus
                    cpu_bus_oe_n <= 1; // disable CPU drivers
                    bus_wait_cnt <= 0;
                    bus_state    <= BUS_MASTER;
                end

                BUS_MASTER: begin
                    bus_op_done <= 0;
                    if (!want_bus) begin
                        bus_state <= RELEASE_BUS;
                    end else if (bus_req_read) begin
                        bus_state <= READ_REQ;
                    end else if (bus_req_write) begin
                        bus_state <= WRITE_REQ;
                    end
                end

                READ_REQ: begin
                    mem_addr <= bus_addr_latched;
                    mem_read  <= 1;
                    bus_state <= READ_WAIT;
                end

                READ_WAIT: begin
                    if (bus_wait_cnt < BUS_READ_LATENCY - 1) begin
                        bus_wait_cnt <= bus_wait_cnt + 1;
                    end else begin
                        bus_rdata_latched <= mem_rdata;
                        if (!want_bus) begin
                            bus_state <= RELEASE_BUS;
                        end else begin
                            bus_wait_cnt <= 0;
                            bus_state    <= BUS_MASTER;
                            bus_op_done <= 1;
                        end
                    end
                end

                WRITE_REQ: begin
                    mem_addr  <= bus_addr_latched;
                    mem_wdata <= bus_wdata_latched;
                    mem_write <= 1;
                    bus_state <= WRITE_WAIT;
                end

                WRITE_WAIT: begin
                    if (bus_wait_cnt < BUS_READ_LATENCY - 1) begin
                        bus_wait_cnt <= bus_wait_cnt + 1;
                    end else begin
                        if (!want_bus) begin
                            bus_state <= RELEASE_BUS;
                        end else begin
                            bus_wait_cnt <= 0;
                            bus_state    <= BUS_MASTER;
                            bus_op_done <= 1;
                        end
                    end
                end

                RELEASE_BUS: begin
                    cpu_bus_oe_n <= 0;
                    ppu_bgack_n  <= 1;
                    ppu_br_n     <= 1;
                    bus_state    <= IDLE;
                end
            endcase
        end
    end



    // Bus request generator
    reg [3:0] palette_idx;
    reg [3:0] color_idx;
    reg [13:0] refresh_cnt;
    reg [15:0] oam_temp_low;

    always_ff @(posedge clk) begin
        if (reset) begin
            bus_addr_latched  <= 0;
            bus_wdata_latched <= 0;
            want_bus          <= 0;
            bus_req_read      <= 0;
            bus_req_write     <= 0;
            refresh_state     <= REFRESH_IDLE;
            palette_idx       <= 0;
            color_idx         <= 0;
            mem_refreshed     <= 0;
            refresh_cnt       <= 0;
            oam_temp_low      <= 0;
        end else begin
            case (refresh_state)
                REFRESH_IDLE: begin
                    mem_refreshed <= 0;
                    if (need_mem_refresh) begin
                        want_bus <= 1;
                        refresh_state <= REFRESH_PALETTES;
                        palette_idx <= 0;
                        color_idx <= 0;
                    end
                end

                // -------------------------------------------------------------
                // Palettes
                // -------------------------------------------------------------
                REFRESH_PALETTES: begin
                    if (bus_state == BUS_MASTER && !bus_op_done) begin
                        bus_addr_latched <= PALETTE_MEM_OFFSET + 20'((palette_idx * 16 + color_idx) * 2);
                        bus_req_read <= 1;
                        refresh_state <= REFRESH_WAIT_PALETTE;
                    end
                end

                REFRESH_WAIT_PALETTE: begin
                    bus_req_read <= 0;
                    if (bus_op_done) begin
                        palette[palette_idx][color_idx] <= bus_rdata_latched[11:0];

                        if (color_idx == 15) begin
                            color_idx <= 0;
                            if (palette_idx == 7) begin
                                refresh_state <= REFRESH_TILES;
                                refresh_cnt <= 0;
                            end else begin
                                palette_idx <= palette_idx + 1;
                                refresh_state <= REFRESH_PALETTES;
                            end
                        end else begin
                            color_idx <= color_idx + 1;
                            refresh_state <= REFRESH_PALETTES;
                        end
                    end
                end

                // -------------------------------------------------------------
                // Tiles (16KB = 16384 bytes = 8192 words)
                // -------------------------------------------------------------
                REFRESH_TILES: begin
                    if (bus_state == BUS_MASTER && !bus_op_done) begin
                        bus_addr_latched <= TILE_MEM_OFFSET + 20'(refresh_cnt * 2);
                        bus_req_read <= 1;
                        refresh_state <= REFRESH_WAIT_TILE;
                    end
                end

                REFRESH_WAIT_TILE: begin
                    bus_req_read <= 0;
                    if (bus_op_done) begin
                        tile_memory[{refresh_cnt[12:0], 1'b0}] <= bus_rdata_latched[7:0];
                        tile_memory[{refresh_cnt[12:0], 1'b1}] <= bus_rdata_latched[15:8];

                        if (refresh_cnt == 8191) begin
                            refresh_state <= REFRESH_BG_MAP;
                            refresh_cnt <= 0;
                        end else begin
                            refresh_cnt <= refresh_cnt + 1;
                            refresh_state <= REFRESH_TILES;
                        end
                    end
                end

                // -------------------------------------------------------------
                // BG Map (4096 bytes = 2048 words)
                // -------------------------------------------------------------
                REFRESH_BG_MAP: begin
                    if (bus_state == BUS_MASTER && !bus_op_done) begin
                        bus_addr_latched <= BG_MAP_MEM_OFFSET + 20'(refresh_cnt * 2);
                        bus_req_read <= 1;
                        refresh_state <= REFRESH_WAIT_BG_MAP;
                    end
                end

                REFRESH_WAIT_BG_MAP: begin
                    bus_req_read <= 0;
                    if (bus_op_done) begin
                        bg_tile_map[{refresh_cnt[10:0], 1'b0}] <= bus_rdata_latched[7:0];
                        bg_tile_map[{refresh_cnt[10:0], 1'b1}] <= bus_rdata_latched[15:8];

                        if (refresh_cnt == 2047) begin
                            refresh_state <= REFRESH_UI_MAP;
                            refresh_cnt <= 0;
                        end else begin
                            refresh_cnt <= refresh_cnt + 1;
                            refresh_state <= REFRESH_BG_MAP;
                        end
                    end
                end

                // -------------------------------------------------------------
                // UI Map (400 bytes = 200 words)
                // -------------------------------------------------------------
                REFRESH_UI_MAP: begin
                    if (bus_state == BUS_MASTER && !bus_op_done) begin
                        bus_addr_latched <= UI_MAP_MEM_OFFSET + 20'(refresh_cnt * 2);
                        bus_req_read <= 1;
                        refresh_state <= REFRESH_WAIT_UI_MAP;
                    end
                end

                REFRESH_WAIT_UI_MAP: begin
                    bus_req_read <= 0;
                    if (bus_op_done) begin
                        ui_tile_map[{refresh_cnt[7:0], 1'b0}] <= bus_rdata_latched[7:0];
                        ui_tile_map[{refresh_cnt[7:0], 1'b1}] <= bus_rdata_latched[15:8];

                        if (refresh_cnt == 199) begin
                            refresh_state <= REFRESH_OAM;
                            refresh_cnt <= 0;
                        end else begin
                            refresh_cnt <= refresh_cnt + 1;
                            refresh_state <= REFRESH_UI_MAP;
                        end
                    end
                end

                // -------------------------------------------------------------
                // OAM (128 entries * 4 bytes = 512 bytes = 256 words)
                // -------------------------------------------------------------
                REFRESH_OAM: begin
                    if (bus_state == BUS_MASTER && !bus_op_done) begin
                        // Read low word
                        bus_addr_latched <= OAM_MEM_OFFSET + 20'(refresh_cnt * 4);
                        bus_req_read <= 1;
                        refresh_state <= REFRESH_WAIT_OAM_LOW;
                    end
                end

                REFRESH_WAIT_OAM_LOW: begin
                    bus_req_read <= 0;
                    if (bus_op_done) begin
                        oam_temp_low <= bus_rdata_latched;

                        // Read high word
                        bus_addr_latched <= OAM_MEM_OFFSET + 20'(refresh_cnt * 4 + 2);
                        bus_req_read <= 1;
                        refresh_state <= REFRESH_WAIT_OAM_HIGH;
                    end
                end

                REFRESH_WAIT_OAM_HIGH: begin
                    bus_req_read <= 0;
                    if (bus_op_done) begin
                        oam[refresh_cnt[6:0]] <= {bus_rdata_latched, oam_temp_low};

                        if (refresh_cnt == MAX_OBJECTS - 1) begin
                            refresh_state <= REFRESH_DONE;
                        end else begin
                            refresh_cnt <= refresh_cnt + 1;
                            refresh_state <= REFRESH_OAM;
                        end
                    end
                end

                REFRESH_DONE: begin
                    want_bus <= 0;
                    refresh_state <= REFRESH_IDLE;
                    mem_refreshed <= 1;
                end

                default: refresh_state <= REFRESH_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Video Logic
    // -------------------------------------------------------------------------

    reg [12:0] pixel_x;
    reg [11:0] pixel_y;
    reg [8:0]  scroll_x; // TODO: make these writeable by CPU
    reg [8:0]  scroll_y;
    reg [31:0] cached_rdata;

    // Loop and intermediate variables for object rendering
    integer i;
    reg [31:0] object;
    reg [8:0] obj_x;
    reg [7:0] obj_y;
    reg [8:0] tile_idx;
    reg       hflip;
    reg       vflip;
    reg [2:0] local_x;
    reg [2:0] local_y;
    reg [12:0] tile_base;
    reg [12:0] byte_offset;
    reg [3:0] pixel_data;
    reg [7:0] tile_byte;
    reg [11:0] color;

    always_ff @(posedge clk) begin
        if (reset) begin
            scroll_x <= 0;
            scroll_y <= 0;
            pixel_x <= 0;
            pixel_y <= 0;
            pixel_r <= 0;
            pixel_g <= 0;
            pixel_b <= 0;
            pixel_sync <= 0;
            need_mem_refresh <= 0;
        end else begin
            // Background Rendering
            logic [12:0] scrolled_x;
            logic [11:0] scrolled_y;
            logic [5:0] bg_tile_x;
            logic [5:0] bg_tile_y;
            logic [7:0] bg_tile_idx;
            logic [2:0] bg_local_x;
            logic [2:0] bg_local_y;
            logic [13:0] bg_byte_addr;
            logic [7:0] bg_byte;
            logic [3:0] bg_pixel_val;
            logic [11:0] bg_tile_color;

            // UI Rendering
            logic [5:0] ui_tile_x;
            logic [5:0] ui_tile_y;
            logic [7:0] ui_tile_idx;
            logic [2:0] ui_local_x;
            logic [2:0] ui_local_y;
            logic [13:0] ui_byte_addr;
            logic [7:0] ui_byte;
            logic [3:0] ui_pixel_val;
            logic [11:0] ui_tile_color;
            logic       ui_render = 0;

            // Check for start of frame
            if (pixel_x == 0 && pixel_y == 0 && !mem_refreshed) begin
                need_mem_refresh <= 1;
                pixel_sync <= 0;
                pixel_r <= 0;
                pixel_g <= 0;
                pixel_b <= 0;
            end else begin
                need_mem_refresh <= 0;

                // Get background tile data
                scrolled_x = pixel_x + scroll_x;
                scrolled_y = pixel_y + scroll_y;

                bg_tile_x = scrolled_x[8:3];
                bg_tile_y = scrolled_y[8:3];
                bg_tile_idx = bg_tile_map[{bg_tile_y[5:0], bg_tile_x[5:0]}]; // 64x64 map, so mask addresses

                // Local pixel within tile
                bg_local_x = scrolled_x[2:0];
                bg_local_y = scrolled_y[2:0];

                // 32 bytes per tile, 4 bytes per row (8 pixels / 2)
                bg_byte_addr = (14'(bg_tile_idx) << 5) + (14'(bg_local_y) << 2) + (14'(bg_local_x) >> 1);
                bg_byte = tile_memory[bg_byte_addr];
                bg_pixel_val = bg_local_x[0] ? bg_byte[3:0] : bg_byte[7:4];

                // Get color from palette
                bg_tile_color = palette[bg_palette][bg_pixel_val];

                // Set pixel to background color initially
                // TODO: possible optimization if other pixels are going to be rendered on top anyway
                pixel_sync <= 1; // Always output a pixel
                if (bg_pixel_val != 0) begin
                    pixel_r <= {bg_tile_color[11:8], bg_tile_color[11:8]};
                    pixel_g <= {bg_tile_color[7:4], bg_tile_color[7:4]};
                    pixel_b <= {bg_tile_color[3:0], bg_tile_color[3:0]};
                end else begin
                    // sky
                    pixel_r <= 8'h88;
                    pixel_g <= 8'hDD;
                    pixel_b <= 8'hFF;
                end

                // Loop through objects
                // TODO: possible optimization: only check objects that are likely to be on this scanline
                for (i = 0; i < MAX_OBJECTS; i = i + 1) begin
                    object = oam[i];

                    // Check if object is enabled
                    if (object[31]) begin
                        obj_x       <= object[8:0];
                        obj_y       <= object[16:9];
                        tile_idx    <= object[25:17];
                        palette_idx <= object[28:26];
                        hflip       <= object[29];
                        vflip       <= object[30];

                        // Check if current pixel is within this object's bounds
                        if (pixel_x >= 13'(obj_x) && pixel_x < 13'(obj_x) + 13'd8 && pixel_y >= 12'(obj_y) && pixel_y < 12'(obj_y) + 12'd8) begin
                            local_x <= 3'(pixel_x - 13'(obj_x));
                            local_y <= 3'(pixel_y - 12'(obj_y));

                            // Apply flip transformations
                            if (hflip) local_x <= 3'd7 - local_x;
                            if (vflip) local_y <= 3'd7 - local_y;

                            // Get tile
                            tile_base = tile_idx * 13'd32; // 32 bytes per tile
                            byte_offset = tile_base + (13'(local_y) * 13'd4) + (13'(local_x) >> 1);

                            tile_byte = tile_memory[14'(byte_offset)];
                            pixel_data = (local_x[0]) ? tile_byte[3:0] : tile_byte[7:4]; // Use lowest bit of x position to check even or odd for nibble selection

                            if (pixel_data == 4'b1111) begin
                                // Transparent pixel, skip
                                continue;
                            end

                            // Set pixel color
                            color = palette[palette_idx][pixel_data];
                            pixel_r <= {color[11:8], color[11:8]};
                            pixel_g <= {color[7:4], color[7:4]};
                            pixel_b <= {color[3:0], color[3:0]};
                            pixel_sync <= 1; // Indicate pixel drawn
                        end
                    end
                end

                // Render UI

                // Get UI tile data
                ui_tile_x = pixel_x[8:3]; // pixel_x / 8
                ui_tile_y = pixel_y[8:3]; // pixel_y / 8

                if (ui_tile_y < 5) begin
                    ui_render = 1;
                end

                if (ui_tile_y >= 25) begin
                    ui_render = 1;
                    ui_tile_y = ui_tile_y - 5'd20; // Shift to 0-4 range as UI is at bottom
                end

                // Render UI if in UI area (top and bottom bar)
                if (ui_render) begin
                    ui_tile_idx = ui_tile_map[ui_tile_y * 40 + ui_tile_x];

                    // Local pixel within tile
                    ui_local_x = pixel_x[2:0];
                    ui_local_y = pixel_y[2:0];

                    // 32 bytes per tile, 4 bytes per row (8 pixels / 2)
                    ui_byte_addr = (14'(ui_tile_idx) << 5) + (14'(ui_local_y) << 2) + (14'(ui_local_x) >> 1);
                    ui_byte = tile_memory[ui_byte_addr];
                    ui_pixel_val = ui_local_x[0] ? ui_byte[3:0] : ui_byte[7:4]; // Select nibble (2 pixels per byte)

                    // Get color from palette
                    if (ui_tile_y < 5) begin
                        ui_tile_color = palette[ui_top_palette][ui_pixel_val];
                    end else begin
                        ui_tile_color = palette[ui_bottom_palette][ui_pixel_val];
                    end

                    // Set pixel
                    if (ui_pixel_val != 0) begin
                        pixel_r <= {ui_tile_color[11:8], ui_tile_color[11:8]};
                        pixel_g <= {ui_tile_color[7:4], ui_tile_color[7:4]};
                        pixel_b <= {ui_tile_color[3:0], ui_tile_color[3:0]};
                    end
                end
                // Timing counters
                if (pixel_x == DISP_WIDTH - 1) begin
                    pixel_x <= 0;
                    if (pixel_y == DISP_HEIGHT - 1) begin
                        pixel_y <= 0;
                    end else begin
                        pixel_y <= pixel_y + 1;
                    end
                end else begin
                    pixel_x <= pixel_x + 1;
                end
            end
        end
    end

endmodule
