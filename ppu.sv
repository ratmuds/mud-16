module ppu #(
    parameter DISP_WIDTH  = 320,
    parameter DISP_HEIGHT = 240,

    parameter MAX_OBJECTS = 128
) (
    input  logic clk,
    input  logic reset,

    // Pixel outputs (VGA interface)
    output logic [7:0] pixel_r,
    output logic [7:0] pixel_g,
    output logic [7:0] pixel_b,

    // 68000 Bus Arbitration Signals
    input  logic       cpu_bg_n,      // Bus Grant (Active Low) from CPU
    input  logic       cpu_as_n,      // Address Strobe (Active Low) from CPU
    output logic       ppu_br_n,      // Bus Request (Active Low) to CPU
    output logic       ppu_bgack_n,   // Bus Grant Acknowledge (Active Low) to CPU

    // Level Shifter Control
    output logic       cpu_bus_oe_n,  // Output Enable for CPU level shifters (Active Low = CPU drives bus)

    // Memory interface (Shared Bus)
    output logic [19:0] mem_addr,
    input  logic [31:0] mem_rdata,    // In real hardware this would be 16-bit, simplified here
    output logic [31:0] mem_wdata,
    output logic        mem_read,
    output logic        mem_write
);

    // -------------------------------------------------------------------------
    // Bus Arbitration State Machine
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,
        REQUEST_BUS,
        WAIT_FOR_GRANT,
        SEIZE_BUS,
        BUS_MASTER,
        RELEASE_BUS
    } bus_state_t;

    bus_state_t bus_state;

    // Internal requests
    logic want_bus;

    // Memory arrays
    reg [11:0] palette [0:7][0:15];      // 8 palettes, 16 colors each, 12-bit RGB
    reg [7:0]  tile_memory [0:16383];    // 512 tiles * 32 bytes = 16KB
    reg [31:0] oam [0:MAX_OBJECTS-1];    // Object Attribute Memory

    // Palette 0: Grayscale
    initial begin
        palette[0][0]  = 12'h000;  // Black
        palette[0][1]  = 12'h111;
        palette[0][2]  = 12'h222;
        palette[0][3]  = 12'h333;
        palette[0][4]  = 12'h444;
        palette[0][5]  = 12'h555;
        palette[0][6]  = 12'h666;
        palette[0][7]  = 12'h777;
        palette[0][8]  = 12'h888;
        palette[0][9]  = 12'h999;
        palette[0][10] = 12'hAAA;
        palette[0][11] = 12'hBBB;
        palette[0][12] = 12'hCCC;
        palette[0][13] = 12'hDDD;
        palette[0][14] = 12'hEEE;
        palette[0][15] = 12'hFFF;  // White
    end

    // Palette 1: Red character (Mario-style)
    initial begin
        palette[1][0]  = 12'h0BD;  // Transparent/Sky blue
        palette[1][1]  = 12'h000;  // Black (outlines)
        palette[1][2]  = 12'hF00;  // Bright red
        palette[1][3]  = 12'hC00;  // Dark red
        palette[1][4]  = 12'hFA0;  // Skin tone
        palette[1][5]  = 12'hC80;  // Dark skin
        palette[1][6]  = 12'h840;  // Brown (hair)
        palette[1][7]  = 12'h62F;  // Blue (overalls)
        palette[1][8]  = 12'h41D;  // Dark blue
        palette[1][9]  = 12'hFF0;  // Yellow (buttons)
        palette[1][10] = 12'hFFF;  // White (eyes)
        palette[1][11] = 12'h888;  // Gray
        palette[1][12] = 12'h0F0;  // Green
        palette[1][13] = 12'h0A0;  // Dark green
        palette[1][14] = 12'hF8F;  // Pink
        palette[1][15] = 12'hC6F;  // Purple
    end

    // Palette 2: Blue character (Sonic-style)
    initial begin
        palette[2][0]  = 12'h0BD;  // Transparent
        palette[2][1]  = 12'h000;  // Black
        palette[2][2]  = 12'h05F;  // Bright blue
        palette[2][3]  = 12'h03C;  // Dark blue
        palette[2][4]  = 12'hFDA;  // Peach (skin)
        palette[2][5]  = 12'hC96;  // Dark peach
        palette[2][6]  = 12'hF00;  // Red (shoes)
        palette[2][7]  = 12'hA00;  // Dark red
        palette[2][8]  = 12'hFFF;  // White (gloves, eyes)
        palette[2][9]  = 12'hCCC;  // Light gray
        palette[2][10] = 12'h666;  // Dark gray
        palette[2][11] = 12'hFF0;  // Yellow
        palette[2][12] = 12'h0F0;  // Green
        palette[2][13] = 12'h4AF;  // Light blue
        palette[2][14] = 12'hF80;  // Orange
        palette[2][15] = 12'h90F;  // Purple
    end

    // Palette 3: Fire/Enemy palette
    initial begin
        palette[3][0]  = 12'h000;  // Black/Transparent
        palette[3][1]  = 12'h200;  // Very dark red
        palette[3][2]  = 12'h500;  // Dark red
        palette[3][3]  = 12'h900;  // Medium red
        palette[3][4]  = 12'hD00;  // Bright red
        palette[3][5]  = 12'hF10;  // Red-orange
        palette[3][6]  = 12'hF50;  // Orange
        palette[3][7]  = 12'hF90;  // Light orange
        palette[3][8]  = 12'hFD0;  // Yellow-orange
        palette[3][9]  = 12'hFF0;  // Yellow
        palette[3][10] = 12'hFF8;  // Light yellow
        palette[3][11] = 12'hFFC;  // Very light yellow
        palette[3][12] = 12'h630;  // Brown
        palette[3][13] = 12'h840;  // Light brown
        palette[3][14] = 12'h333;  // Dark gray
        palette[3][15] = 12'hFFF;  // White (hottest)
    end

    // Palette 4: Green/Nature palette
    initial begin
        palette[4][0]  = 12'h8DF;  // Sky blue/Transparent
        palette[4][1]  = 12'h020;  // Very dark green
        palette[4][2]  = 12'h040;  // Dark green
        palette[4][3]  = 12'h070;  // Medium dark green
        palette[4][4]  = 12'h0A0;  // Medium green
        palette[4][5]  = 12'h0D0;  // Bright green
        palette[4][6]  = 12'h0F0;  // Very bright green
        palette[4][7]  = 12'h8F8;  // Light green
        palette[4][8]  = 12'h4A0;  // Yellow-green
        palette[4][9]  = 12'h7C0;  // Lime
        palette[4][10] = 12'hFF0;  // Yellow
        palette[4][11] = 12'h963;  // Brown (tree trunk)
        palette[4][12] = 12'hC85;  // Light brown
        palette[4][13] = 12'h642;  // Dark brown
        palette[4][14] = 12'h666;  // Gray (rocks)
        palette[4][15] = 12'h999;  // Light gray
    end

    //============================================================================
    // TILE DATA (4 bits per pixel, 8x8 = 32 bytes per tile)
    // Each byte contains 2 pixels: [high_nibble][low_nibble]
    //============================================================================

    // Tile 0: Solid block (for testing)
    initial begin
        tile_memory[0]  = 8'hFF; tile_memory[1]  = 8'hFF; tile_memory[2]  = 8'hFF; tile_memory[3]  = 8'hFF;
        tile_memory[4]  = 8'hFF; tile_memory[5]  = 8'hFF; tile_memory[6]  = 8'hFF; tile_memory[7]  = 8'hFF;
        tile_memory[8]  = 8'hFF; tile_memory[9]  = 8'hFF; tile_memory[10] = 8'hFF; tile_memory[11] = 8'hFF;
        tile_memory[12] = 8'hFF; tile_memory[13] = 8'hFF; tile_memory[14] = 8'hFF; tile_memory[15] = 8'hFF;
        tile_memory[16] = 8'hFF; tile_memory[17] = 8'hFF; tile_memory[18] = 8'hFF; tile_memory[19] = 8'hFF;
        tile_memory[20] = 8'hFF; tile_memory[21] = 8'hFF; tile_memory[22] = 8'hFF; tile_memory[23] = 8'hFF;
        tile_memory[24] = 8'hFF; tile_memory[25] = 8'hFF; tile_memory[26] = 8'hFF; tile_memory[27] = 8'hFF;
        tile_memory[28] = 8'hFF; tile_memory[29] = 8'hFF; tile_memory[30] = 8'hFF; tile_memory[31] = 8'hFF;
    end

    // Tile 1: Smiley face
    initial begin
        // Each row: 8 pixels = 4 bytes
        // Palette indices: 0=transparent, 1=black, 2=yellow, 3=dark yellow
        tile_memory[32] = 8'h00; tile_memory[33] = 8'h22; tile_memory[34] = 8'h22; tile_memory[35] = 8'h00; // Row 0: __2222__
        tile_memory[36] = 8'h02; tile_memory[37] = 8'h22; tile_memory[38] = 8'h22; tile_memory[39] = 8'h20; // Row 1: _222222_
        tile_memory[40] = 8'h22; tile_memory[41] = 8'h12; tile_memory[42] = 8'h21; tile_memory[43] = 8'h22; // Row 2: 22_22_22
        tile_memory[44] = 8'h22; tile_memory[45] = 8'h22; tile_memory[46] = 8'h22; tile_memory[47] = 8'h22; // Row 3: 22222222
        tile_memory[48] = 8'h22; tile_memory[49] = 8'h22; tile_memory[50] = 8'h22; tile_memory[51] = 8'h22; // Row 4: 22222222
        tile_memory[52] = 8'h21; tile_memory[53] = 8'h22; tile_memory[54] = 8'h22; tile_memory[55] = 8'h12; // Row 5: 2_2222_2
        tile_memory[56] = 8'h02; tile_memory[57] = 8'h11; tile_memory[58] = 8'h11; tile_memory[59] = 8'h20; // Row 6: _2____2_
        tile_memory[60] = 8'h00; tile_memory[61] = 8'h22; tile_memory[62] = 8'h22; tile_memory[63] = 8'h00; // Row 7: __2222__
    end

    // Tile 2: Simple character sprite (8x8 pixel art person)
    initial begin
        // 0=transparent, 1=black, 2=skin, 3=hair, 4=shirt
        tile_memory[64] = 8'h00; tile_memory[65] = 8'h33; tile_memory[66] = 8'h33; tile_memory[67] = 8'h00; // Hair
        tile_memory[68] = 8'h03; tile_memory[69] = 8'h32; tile_memory[70] = 8'h23; tile_memory[71] = 8'h30; // Hair + face
        tile_memory[72] = 8'h02; tile_memory[73] = 8'h21; tile_memory[74] = 8'h12; tile_memory[75] = 8'h20; // Face + eyes
        tile_memory[76] = 8'h02; tile_memory[77] = 8'h22; tile_memory[78] = 8'h22; tile_memory[79] = 8'h20; // Face
        tile_memory[80] = 8'h00; tile_memory[81] = 8'h44; tile_memory[82] = 8'h44; tile_memory[83] = 8'h00; // Shirt
        tile_memory[84] = 8'h04; tile_memory[85] = 8'h44; tile_memory[86] = 8'h44; tile_memory[87] = 8'h40; // Shirt
        tile_memory[88] = 8'h04; tile_memory[89] = 8'h02; tile_memory[90] = 8'h20; tile_memory[91] = 8'h40; // Shirt + arms
        tile_memory[92] = 8'h02; tile_memory[93] = 8'h00; tile_memory[94] = 8'h00; tile_memory[95] = 8'h20; // Legs
    end

    // Tile 3: 8x8 Checkerboard pattern
    initial begin
        tile_memory[96]  = 8'hF0; tile_memory[97]  = 8'hF0; tile_memory[98]  = 8'hF0; tile_memory[99]  = 8'hF0;
        tile_memory[100] = 8'h0F; tile_memory[101] = 8'h0F; tile_memory[102] = 8'h0F; tile_memory[103] = 8'h0F;
        tile_memory[104] = 8'hF0; tile_memory[105] = 8'hF0; tile_memory[106] = 8'hF0; tile_memory[107] = 8'hF0;
        tile_memory[108] = 8'h0F; tile_memory[109] = 8'h0F; tile_memory[110] = 8'h0F; tile_memory[111] = 8'h0F;
        tile_memory[112] = 8'hF0; tile_memory[113] = 8'hF0; tile_memory[114] = 8'hF0; tile_memory[115] = 8'hF0;
        tile_memory[116] = 8'h0F; tile_memory[117] = 8'h0F; tile_memory[118] = 8'h0F; tile_memory[119] = 8'h0F;
        tile_memory[120] = 8'hF0; tile_memory[121] = 8'hF0; tile_memory[122] = 8'hF0; tile_memory[123] = 8'hF0;
        tile_memory[124] = 8'h0F; tile_memory[125] = 8'h0F; tile_memory[126] = 8'h0F; tile_memory[127] = 8'h0F;
    end

    // Tile 4: Heart sprite
    initial begin
        // 0=transparent, C=red bright, B=red medium, A=red dark
        tile_memory[128] = 8'h0C; tile_memory[129] = 8'hC0; tile_memory[130] = 8'h0C; tile_memory[131] = 8'hC0;
        tile_memory[132] = 8'hCC; tile_memory[133] = 8'hCC; tile_memory[134] = 8'hCC; tile_memory[135] = 8'hCC;
        tile_memory[136] = 8'hCB; tile_memory[137] = 8'hBB; tile_memory[138] = 8'hBB; tile_memory[139] = 8'hBC;
        tile_memory[140] = 8'hCB; tile_memory[141] = 8'hBB; tile_memory[142] = 8'hBB; tile_memory[143] = 8'hBC;
        tile_memory[144] = 8'h0B; tile_memory[145] = 8'hBA; tile_memory[146] = 8'hAB; tile_memory[147] = 8'hB0;
        tile_memory[148] = 8'h0B; tile_memory[149] = 8'hBA; tile_memory[150] = 8'hAB; tile_memory[151] = 8'hB0;
        tile_memory[152] = 8'h00; tile_memory[153] = 8'hBA; tile_memory[154] = 8'hAB; tile_memory[155] = 8'h00;
        tile_memory[156] = 8'h00; tile_memory[157] = 8'h0A; tile_memory[158] = 8'hA0; tile_memory[159] = 8'h00;
    end

    //============================================================================
    // OAM DATA (Object Attribute Memory)
    // 32 bits per sprite: [X:9][Y:8][Tile:9][Pal:3][HFlip:1][VFlip:1][Enable:1]
    //============================================================================

    // OAM Entry format breakdown:
    // Bits 0-8:   X Position (9 bits, 0-479)
    // Bits 9-16:  Y Position (8 bits, 0-255)
    // Bits 17-25: Tile Index (9 bits, 0-511)
    // Bits 26-28: Palette (3 bits, 0-7)
    // Bit 29:     H-Flip
    // Bit 30:     V-Flip
    // Bit 31:     Enable

    initial begin
        // Sprite 0: Smiley face at (100, 50), palette 1, tile 1
        oam[0] = {1'b1, 1'b0, 1'b0, 3'd1, 9'd1, 8'd50, 9'd100};

        // Sprite 1: Character at (150, 100), palette 1, tile 2
        oam[1] = {1'b1, 1'b0, 1'b0, 3'd1, 9'd2, 8'd100, 9'd150};

        // Sprite 2: Checkerboard at (200, 150), palette 0, tile 3
        oam[2] = {1'b1, 1'b0, 1'b0, 3'd0, 9'd3, 8'd150, 9'd200};

        // Sprite 3: Heart at (250, 80), palette 3, tile 4
        oam[3] = {1'b1, 1'b0, 1'b0, 3'd3, 9'd4, 8'd80, 9'd250};

        // Sprite 4: Another smiley H-flipped at (300, 50), palette 2
        oam[4] = {1'b1, 1'b0, 1'b1, 3'd2, 9'd1, 8'd50, 9'd300};

        // Sprite 5: Solid block at (50, 200), palette 4
        oam[5] = {1'b1, 1'b0, 1'b0, 3'd4, 9'd0, 8'd200, 9'd50};

        // Test pattern: Row of sprites across top
        oam[6]  = {1'b1, 1'b0, 1'b0, 3'd1, 9'd1, 8'd20, 9'd50};
        oam[7]  = {1'b1, 1'b0, 1'b0, 3'd2, 9'd1, 8'd20, 9'd100};
        oam[8]  = {1'b1, 1'b0, 1'b0, 3'd3, 9'd4, 8'd20, 9'd150};
        oam[9]  = {1'b1, 1'b0, 1'b0, 3'd4, 9'd3, 8'd20, 9'd200};
        oam[10] = {1'b1, 1'b0, 1'b0, 3'd0, 9'd2, 8'd20, 9'd250};

        // Remaining sprites disabled
        for (integer i = 11; i < 128; i = i + 1) begin
            oam[i] = 32'h0; // Enable bit = 0
        end
    end

    /*always_ff @(posedge clk) begin
        if (reset) begin
            bus_state     <= IDLE;
            ppu_br_n      <= 1;
            ppu_bgack_n   <= 1;
            cpu_bus_oe_n  <= 0; // Default: CPU enabled
        end else begin
            case (bus_state)
                IDLE: begin
                    ppu_br_n <= 1;
                    ppu_bgack_n <= 1;
                    cpu_bus_oe_n <= 0; // CPU owns bus

                    if (want_bus) begin
                        bus_state <= REQUEST_BUS;
                    end
                end

                REQUEST_BUS: begin
                    ppu_br_n <= 0; // Assert Bus Request
                    bus_state <= WAIT_FOR_GRANT;
                end

                WAIT_FOR_GRANT: begin
                    // Wait for BG low AND AS high (bus free)
                    if (!cpu_bg_n && cpu_as_n) begin
                        bus_state <= SEIZE_BUS;
                    end
                end

                SEIZE_BUS: begin
                    ppu_bgack_n <= 0;  // Assert BGACK
                    ppu_br_n <= 1;     // Release BR (optional, but good practice)
                    cpu_bus_oe_n <= 1; // Disable CPU level shifters (High-Z CPU)
                    bus_state <= BUS_MASTER;
                end

                BUS_MASTER: begin
                    // We own the bus! Do transfers here.
                    if (!want_bus) begin
                        bus_state <= RELEASE_BUS;
                    end
                end

                RELEASE_BUS: begin
                    mem_read <= 0;
                    mem_write <= 0;
                    cpu_bus_oe_n <= 0; // Re-enable CPU
                    ppu_bgack_n <= 1;  // Release BGACK
                    bus_state <= IDLE;
                end
            endcase
        end
    end*/

    // -------------------------------------------------------------------------
    // Video Logic
    // -------------------------------------------------------------------------

    reg [12:0] pixel_x;
    reg [11:0] pixel_y;
    reg [31:0] cached_rdata;

    // Loop and intermediate variables for object rendering
    integer i;
    reg [31:0] object;
    reg [8:0] obj_x;
    reg [7:0] obj_y;
    reg [8:0] tile_idx;
    reg [2:0] palette_idx;
    reg       hflip;
    reg       vflip;
    reg [2:0] local_x;
    reg [2:0] local_y;
    reg [12:0] tile_base;
    reg [12:0] byte_offset;
    reg [3:0] pixel_data;
    reg [7:0] tile_byte;
    reg [11:0] color;

    // Simple logic: We want the bus whenever we are in the active display area
    // In a real PPU, you'd fetch a scanline ahead into a FIFO.
    assign want_bus = (pixel_y < DISP_HEIGHT);

    always_ff @(posedge clk) begin
        if (reset) begin
            pixel_x <= 0;
            pixel_y <= 0;
            mem_addr <= 0;
            mem_read <= 0;
            mem_write <= 0;
            pixel_r <= 0;
            pixel_g <= 0;
            pixel_b <= 0;
        end else begin

            // Only access memory if we are the Bus Master
            /*if (bus_state == BUS_MASTER) begin
                mem_addr <= (20'(pixel_y) * 20'(DISP_WIDTH) + 20'(pixel_x)) * 20'd4;
                mem_read <= 1;

                // Latch data (simulating 1 cycle latency)
                cached_rdata <= mem_rdata;
            end else begin
                mem_read <= 0;
            end*/

            // Loop through objects
            for (i = 0; i < MAX_OBJECTS; i = i + 1) begin
                object = oam[i];

                // Check if object is enabled
                if (object[31]) begin
                    obj_x       = object[8:0];
                    obj_y       = object[16:9];
                    tile_idx    = object[25:17];
                    palette_idx = object[28:26];
                    hflip       = object[29];
                    vflip       = object[30];

                    // Check if current pixel is within this object's bounds
                    if (pixel_x >= 13'(obj_x) && pixel_x < 13'(obj_x) + 13'd8 && pixel_y >= 12'(obj_y) && pixel_y < 12'(obj_y) + 12'd8) begin
                        local_x = 3'(pixel_x - 13'(obj_x));
                        local_y = 3'(pixel_y - 12'(obj_y));

                        // TODO: apply flip

                        // Get tile
                        tile_base = tile_idx * 13'd32; // 32 bytes per tile
                        byte_offset = tile_base + (13'(local_y) * 13'd4) + (13'(local_x) >> 1);

                        tile_byte = tile_memory[14'(byte_offset)];
                        pixel_data = (local_x[0]) ? tile_byte[3:0] : tile_byte[7:4]; // Use lowest bit of x position to check even or odd for nibble selection

                        // Set pixel color
                        color = palette[palette_idx][pixel_data];
                        pixel_r <= {color[11:8], 4'b0};
                        pixel_g <= {color[7:4], 4'b0};
                        pixel_b <= {color[3:0], 4'b0};
                    end
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

endmodule
