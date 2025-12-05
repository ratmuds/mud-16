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

    reg [7:0]  bg_tile_map [0:4095];     // Background tile map (64x64 tiles = 4096 bytes)
    reg [2:0]  bg_palette;               // Background palette index

    reg [7:0]  ui_tile_map [0:399];      // UI tile map (40x10 tiles = 400 bytes; UI only at the top and bottom)
    reg [2:0]  ui_top_palette;           // UI palette index (top)
    reg [2:0]  ui_bottom_palette;        // UI palette index (bottom)

    // Palette 0: Background/World (for BG tiles - index 0 is transparent/sky)
    initial begin
        palette[0][0]  = 12'h6CF;  // Sky blue (transparent for BG)
        palette[0][1]  = 12'h0A0;  // Grass green
        palette[0][2]  = 12'h070;  // Dark grass
        palette[0][3]  = 12'h840;  // Dirt brown
        palette[0][4]  = 12'h630;  // Dark dirt
        palette[0][5]  = 12'hC63;  // Brick orange
        palette[0][6]  = 12'h842;  // Brick dark
        palette[0][7]  = 12'hFC6;  // Question block yellow
        palette[0][8]  = 12'hDA4;  // Question block dark
        palette[0][9]  = 12'hFFF;  // White (clouds)
        palette[0][10] = 12'hDDF;  // Cloud shadow
        palette[0][11] = 12'h4A4;  // Pipe green
        palette[0][12] = 12'h282;  // Pipe dark green
        palette[0][13] = 12'h6C6;  // Pipe highlight
        palette[0][14] = 12'h000;  // Black outline
        palette[0][15] = 12'h6CF;  // Also sky (F=transparent for sprites)
    end

    // Palette 1: Player (Simple Human)
    initial begin
        palette[1][0]  = 12'h000;  // Black
        palette[1][1]  = 12'h000;  // Black (Outline/Shoes)
        palette[1][2]  = 12'hFB8;  // Skin
        palette[1][3]  = 12'hD96;  // Skin Dark
        palette[1][4]  = 12'hF00;  // Shirt (Red)
        palette[1][5]  = 12'hA00;  // Shirt Dark
        palette[1][6]  = 12'h00F;  // Pants (Blue)
        palette[1][7]  = 12'h00A;  // Pants Dark
        palette[1][8]  = 12'h630;  // Hair (Brown)
        palette[1][9]  = 12'h420;  // Hair Dark
        palette[1][10] = 12'hFF0;  // Unused
        palette[1][11] = 12'hFB0;  // Unused
        palette[1][12] = 12'h0FF;  // Unused
        palette[1][13] = 12'h48F;  // Unused
        palette[1][14] = 12'hAAA;  // Unused
        palette[1][15] = 12'hF0F;  // Transparent
    end

    // Palette 2: Enemy (Simple Blob)
    initial begin
        palette[2][0]  = 12'h000;  // Black
        palette[2][1]  = 12'h000;  // Outline
        palette[2][2]  = 12'hA0A;  // Body (Purple)
        palette[2][3]  = 12'h606;  // Body Dark
        palette[2][4]  = 12'hFFF;  // Eyes
        palette[2][5]  = 12'h000;  // Pupils
        palette[2][6]  = 12'hFFF;  // Unused
        palette[2][7]  = 12'h000;  // Unused
        palette[2][8]  = 12'h181;  // Unused
        palette[2][9]  = 12'h3C3;  // Unused
        palette[2][10] = 12'hF44;  // Unused
        palette[2][11] = 12'hFF0;  // Unused
        palette[2][12] = 12'h5F5;  // Unused
        palette[2][13] = 12'h9F9;  // Unused
        palette[2][14] = 12'h070;  // Unused
        palette[2][15] = 12'hF0F;  // Transparent
    end

    // Palette 3: Collectibles (Coins, powerups - index F is transparent)
    initial begin
        palette[3][0]  = 12'h000;  // Black
        palette[3][1]  = 12'h111;  // Outline
        palette[3][2]  = 12'hFE0;  // Bright gold
        palette[3][3]  = 12'hDA0;  // Gold
        palette[3][4]  = 12'hA70;  // Dark gold
        palette[3][5]  = 12'h740;  // Bronze
        palette[3][6]  = 12'hFFF;  // White shine
        palette[3][7]  = 12'hF00;  // Red (mushroom)
        palette[3][8]  = 12'hFFF;  // White spots
        palette[3][9]  = 12'hFDA;  // Mushroom stem
        palette[3][10] = 12'h0F0;  // Green (1up)
        palette[3][11] = 12'h0A0;  // Dark green
        palette[3][12] = 12'hF80;  // Orange star
        palette[3][13] = 12'hFF0;  // Yellow star
        palette[3][14] = 12'h888;  // Gray
        palette[3][15] = 12'hF0F;  // Transparent
    end

    //============================================================================
    // TILE DATA (4 bits per pixel, 8x8 = 32 bytes per tile)
    // Each byte contains 2 pixels: [high_nibble][low_nibble]
    // For BG: index 0 = transparent (shows sky)
    // For Sprites: index F (15) = transparent
    //============================================================================

    // Tile 0: Empty/Sky (all zeros - transparent for BG)
    initial begin
        tile_memory[0]  = 8'h00; tile_memory[1]  = 8'h00; tile_memory[2]  = 8'h00; tile_memory[3]  = 8'h00;
        tile_memory[4]  = 8'h00; tile_memory[5]  = 8'h00; tile_memory[6]  = 8'h00; tile_memory[7]  = 8'h00;
        tile_memory[8]  = 8'h00; tile_memory[9]  = 8'h00; tile_memory[10] = 8'h00; tile_memory[11] = 8'h00;
        tile_memory[12] = 8'h00; tile_memory[13] = 8'h00; tile_memory[14] = 8'h00; tile_memory[15] = 8'h00;
        tile_memory[16] = 8'h00; tile_memory[17] = 8'h00; tile_memory[18] = 8'h00; tile_memory[19] = 8'h00;
        tile_memory[20] = 8'h00; tile_memory[21] = 8'h00; tile_memory[22] = 8'h00; tile_memory[23] = 8'h00;
        tile_memory[24] = 8'h00; tile_memory[25] = 8'h00; tile_memory[26] = 8'h00; tile_memory[27] = 8'h00;
        tile_memory[28] = 8'h00; tile_memory[29] = 8'h00; tile_memory[30] = 8'h00; tile_memory[31] = 8'h00;
    end

    // Tile 1: Grass top (green grass with dirt showing)
    // Palette 0: 1=grass, 2=dark grass, 3=dirt, 4=dark dirt
    initial begin
        tile_memory[32] = 8'h11; tile_memory[33] = 8'h21; tile_memory[34] = 8'h11; tile_memory[35] = 8'h12; // Row 0: grass top
        tile_memory[36] = 8'h21; tile_memory[37] = 8'h11; tile_memory[38] = 8'h21; tile_memory[39] = 8'h11; // Row 1: grass
        tile_memory[40] = 8'h11; tile_memory[41] = 8'h11; tile_memory[42] = 8'h11; tile_memory[43] = 8'h11; // Row 2: grass
        tile_memory[44] = 8'h33; tile_memory[45] = 8'h33; tile_memory[46] = 8'h33; tile_memory[47] = 8'h33; // Row 3: dirt
        tile_memory[48] = 8'h33; tile_memory[49] = 8'h43; tile_memory[50] = 8'h33; tile_memory[51] = 8'h34; // Row 4: dirt
        tile_memory[52] = 8'h43; tile_memory[53] = 8'h33; tile_memory[54] = 8'h43; tile_memory[55] = 8'h33; // Row 5: dirt
        tile_memory[56] = 8'h33; tile_memory[57] = 8'h33; tile_memory[58] = 8'h33; tile_memory[59] = 8'h33; // Row 6: dirt
        tile_memory[60] = 8'h33; tile_memory[61] = 8'h43; tile_memory[62] = 8'h34; tile_memory[63] = 8'h33; // Row 7: dirt
    end

    // Tile 2: Dirt block (solid dirt underground)
    initial begin
        tile_memory[64] = 8'h33; tile_memory[65] = 8'h43; tile_memory[66] = 8'h33; tile_memory[67] = 8'h34;
        tile_memory[68] = 8'h43; tile_memory[69] = 8'h33; tile_memory[70] = 8'h43; tile_memory[71] = 8'h33;
        tile_memory[72] = 8'h33; tile_memory[73] = 8'h33; tile_memory[74] = 8'h33; tile_memory[75] = 8'h33;
        tile_memory[76] = 8'h34; tile_memory[77] = 8'h43; tile_memory[78] = 8'h33; tile_memory[79] = 8'h43;
        tile_memory[80] = 8'h33; tile_memory[81] = 8'h33; tile_memory[82] = 8'h43; tile_memory[83] = 8'h33;
        tile_memory[84] = 8'h43; tile_memory[85] = 8'h34; tile_memory[86] = 8'h33; tile_memory[87] = 8'h34;
        tile_memory[88] = 8'h33; tile_memory[89] = 8'h33; tile_memory[90] = 8'h33; tile_memory[91] = 8'h33;
        tile_memory[92] = 8'h34; tile_memory[93] = 8'h33; tile_memory[94] = 8'h43; tile_memory[95] = 8'h33;
    end

    // Tile 3: Brick block (for platforms)
    // Palette 0: 5=brick orange, 6=brick dark, E=black outline
    initial begin
        tile_memory[96]  = 8'hE5; tile_memory[97]  = 8'h55; tile_memory[98]  = 8'h5E; tile_memory[99]  = 8'h55;  // |brick |brick
        tile_memory[100] = 8'h55; tile_memory[101] = 8'h55; tile_memory[102] = 8'h55; tile_memory[103] = 8'h55;  // brick  brick
        tile_memory[104] = 8'h55; tile_memory[105] = 8'h56; tile_memory[106] = 8'h65; tile_memory[107] = 8'h56;  // brick  brick
        tile_memory[108] = 8'hEE; tile_memory[109] = 8'hEE; tile_memory[110] = 8'hEE; tile_memory[111] = 8'hEE;  // --------
        tile_memory[112] = 8'h55; tile_memory[113] = 8'hE5; tile_memory[114] = 8'h55; tile_memory[115] = 8'h5E;  // bric|bric
        tile_memory[116] = 8'h55; tile_memory[117] = 8'h55; tile_memory[118] = 8'h55; tile_memory[119] = 8'h55;  // brick  brick
        tile_memory[120] = 8'h56; tile_memory[121] = 8'h55; tile_memory[122] = 8'h65; tile_memory[123] = 8'h55;  // brick  brick
        tile_memory[124] = 8'hEE; tile_memory[125] = 8'hEE; tile_memory[126] = 8'hEE; tile_memory[127] = 8'hEE;  // --------
    end

    // Tile 4: Question block (? block)
    // Palette 0: 7=yellow, 8=dark yellow, E=black
    initial begin
        tile_memory[128] = 8'hEE; tile_memory[129] = 8'hEE; tile_memory[130] = 8'hEE; tile_memory[131] = 8'hEE;  // outline
        tile_memory[132] = 8'hE7; tile_memory[133] = 8'h77; tile_memory[134] = 8'h77; tile_memory[135] = 8'h7E;  // |yellow|
        tile_memory[136] = 8'hE7; tile_memory[137] = 8'hE7; tile_memory[138] = 8'h7E; tile_memory[139] = 8'h7E;  // | ?    |
        tile_memory[140] = 8'hE7; tile_memory[141] = 8'h7E; tile_memory[142] = 8'hE7; tile_memory[143] = 8'h7E;  // |  ?   |
        tile_memory[144] = 8'hE7; tile_memory[145] = 8'h77; tile_memory[146] = 8'hE7; tile_memory[147] = 8'h7E;  // |   ?  |
        tile_memory[148] = 8'hE7; tile_memory[149] = 8'h77; tile_memory[150] = 8'h77; tile_memory[151] = 8'h7E;  // |      |
        tile_memory[152] = 8'hE7; tile_memory[153] = 8'h77; tile_memory[154] = 8'hE7; tile_memory[155] = 8'h7E;  // |   .  |
        tile_memory[156] = 8'hE8; tile_memory[157] = 8'h88; tile_memory[158] = 8'h88; tile_memory[159] = 8'h8E;  // shadow
    end

    // Tile 5: Cloud left
    // Palette 0: 9=white, A=cloud shadow
    initial begin
        tile_memory[160] = 8'h00; tile_memory[161] = 8'h00; tile_memory[162] = 8'h09; tile_memory[163] = 8'h90;
        tile_memory[164] = 8'h00; tile_memory[165] = 8'h09; tile_memory[166] = 8'h99; tile_memory[167] = 8'h99;
        tile_memory[168] = 8'h09; tile_memory[169] = 8'h99; tile_memory[170] = 8'h99; tile_memory[171] = 8'h99;
        tile_memory[172] = 8'h99; tile_memory[173] = 8'h99; tile_memory[174] = 8'h99; tile_memory[175] = 8'h99;
        tile_memory[176] = 8'h99; tile_memory[177] = 8'h99; tile_memory[178] = 8'h99; tile_memory[179] = 8'h99;
        tile_memory[180] = 8'h0A; tile_memory[181] = 8'h99; tile_memory[182] = 8'h99; tile_memory[183] = 8'h99;
        tile_memory[184] = 8'h00; tile_memory[185] = 8'h0A; tile_memory[186] = 8'hAA; tile_memory[187] = 8'h99;
        tile_memory[188] = 8'h00; tile_memory[189] = 8'h00; tile_memory[190] = 8'h00; tile_memory[191] = 8'h0A;
    end

    // Tile 6: Cloud right
    initial begin
        tile_memory[192] = 8'h09; tile_memory[193] = 8'h90; tile_memory[194] = 8'h00; tile_memory[195] = 8'h00;
        tile_memory[196] = 8'h99; tile_memory[197] = 8'h99; tile_memory[198] = 8'h90; tile_memory[199] = 8'h00;
        tile_memory[200] = 8'h99; tile_memory[201] = 8'h99; tile_memory[202] = 8'h99; tile_memory[203] = 8'h90;
        tile_memory[204] = 8'h99; tile_memory[205] = 8'h99; tile_memory[206] = 8'h99; tile_memory[207] = 8'h99;
        tile_memory[208] = 8'h99; tile_memory[209] = 8'h99; tile_memory[210] = 8'h99; tile_memory[211] = 8'h99;
        tile_memory[212] = 8'h99; tile_memory[213] = 8'h99; tile_memory[214] = 8'h9A; tile_memory[215] = 8'h00;
        tile_memory[216] = 8'h9A; tile_memory[217] = 8'hAA; tile_memory[218] = 8'hA0; tile_memory[219] = 8'h00;
        tile_memory[220] = 8'hA0; tile_memory[221] = 8'h00; tile_memory[222] = 8'h00; tile_memory[223] = 8'h00;
    end

    // Tile 7: Pipe top left
    // Palette 0: B=pipe green, C=pipe dark, D=pipe highlight
    initial begin
        tile_memory[224] = 8'hEC; tile_memory[225] = 8'hDD; tile_memory[226] = 8'hBB; tile_memory[227] = 8'hBB;
        tile_memory[228] = 8'hEB; tile_memory[229] = 8'hDB; tile_memory[230] = 8'hBB; tile_memory[231] = 8'hBB;
        tile_memory[232] = 8'hEB; tile_memory[233] = 8'hDB; tile_memory[234] = 8'hBB; tile_memory[235] = 8'hBB;
        tile_memory[236] = 8'hEC; tile_memory[237] = 8'hCC; tile_memory[238] = 8'hCC; tile_memory[239] = 8'hCC;
        tile_memory[240] = 8'h0E; tile_memory[241] = 8'hDB; tile_memory[242] = 8'hBB; tile_memory[243] = 8'hBB;
        tile_memory[244] = 8'h0E; tile_memory[245] = 8'hDB; tile_memory[246] = 8'hBB; tile_memory[247] = 8'hBB;
        tile_memory[248] = 8'h0E; tile_memory[249] = 8'hDB; tile_memory[250] = 8'hBB; tile_memory[251] = 8'hBB;
        tile_memory[252] = 8'h0E; tile_memory[253] = 8'hDB; tile_memory[254] = 8'hBB; tile_memory[255] = 8'hBB;
    end

    // Tile 8: Pipe top right
    initial begin
        tile_memory[256] = 8'hBB; tile_memory[257] = 8'hBB; tile_memory[258] = 8'hCC; tile_memory[259] = 8'hCE;
        tile_memory[260] = 8'hBB; tile_memory[261] = 8'hBB; tile_memory[262] = 8'hBC; tile_memory[263] = 8'hBE;
        tile_memory[264] = 8'hBB; tile_memory[265] = 8'hBB; tile_memory[266] = 8'hBC; tile_memory[267] = 8'hBE;
        tile_memory[268] = 8'hCC; tile_memory[269] = 8'hCC; tile_memory[270] = 8'hCC; tile_memory[271] = 8'hCE;
        tile_memory[272] = 8'hBB; tile_memory[273] = 8'hBB; tile_memory[274] = 8'hCE; tile_memory[275] = 8'h0E;
        tile_memory[276] = 8'hBB; tile_memory[277] = 8'hBB; tile_memory[278] = 8'hCE; tile_memory[279] = 8'h0E;
        tile_memory[280] = 8'hBB; tile_memory[281] = 8'hBB; tile_memory[282] = 8'hCE; tile_memory[283] = 8'h0E;
        tile_memory[284] = 8'hBB; tile_memory[285] = 8'hBB; tile_memory[286] = 8'hCE; tile_memory[287] = 8'h0E;
    end

    // Tile 9: Pipe body left
    initial begin
        tile_memory[288] = 8'h0E; tile_memory[289] = 8'hDB; tile_memory[290] = 8'hBB; tile_memory[291] = 8'hBB;
        tile_memory[292] = 8'h0E; tile_memory[293] = 8'hDB; tile_memory[294] = 8'hBB; tile_memory[295] = 8'hBB;
        tile_memory[296] = 8'h0E; tile_memory[297] = 8'hDB; tile_memory[298] = 8'hBB; tile_memory[299] = 8'hBB;
        tile_memory[300] = 8'h0E; tile_memory[301] = 8'hDB; tile_memory[302] = 8'hBB; tile_memory[303] = 8'hBB;
        tile_memory[304] = 8'h0E; tile_memory[305] = 8'hDB; tile_memory[306] = 8'hBB; tile_memory[307] = 8'hBB;
        tile_memory[308] = 8'h0E; tile_memory[309] = 8'hDB; tile_memory[310] = 8'hBB; tile_memory[311] = 8'hBB;
        tile_memory[312] = 8'h0E; tile_memory[313] = 8'hDB; tile_memory[314] = 8'hBB; tile_memory[315] = 8'hBB;
        tile_memory[316] = 8'h0E; tile_memory[317] = 8'hDB; tile_memory[318] = 8'hBB; tile_memory[319] = 8'hBB;
    end

    // Tile 10: Pipe body right
    initial begin
        tile_memory[320] = 8'hBB; tile_memory[321] = 8'hBB; tile_memory[322] = 8'hCE; tile_memory[323] = 8'h0E;
        tile_memory[324] = 8'hBB; tile_memory[325] = 8'hBB; tile_memory[326] = 8'hCE; tile_memory[327] = 8'h0E;
        tile_memory[328] = 8'hBB; tile_memory[329] = 8'hBB; tile_memory[330] = 8'hCE; tile_memory[331] = 8'h0E;
        tile_memory[332] = 8'hBB; tile_memory[333] = 8'hBB; tile_memory[334] = 8'hCE; tile_memory[335] = 8'h0E;
        tile_memory[336] = 8'hBB; tile_memory[337] = 8'hBB; tile_memory[338] = 8'hCE; tile_memory[339] = 8'h0E;
        tile_memory[340] = 8'hBB; tile_memory[341] = 8'hBB; tile_memory[342] = 8'hCE; tile_memory[343] = 8'h0E;
        tile_memory[344] = 8'hBB; tile_memory[345] = 8'hBB; tile_memory[346] = 8'hCE; tile_memory[347] = 8'h0E;
        tile_memory[348] = 8'hBB; tile_memory[349] = 8'hBB; tile_memory[350] = 8'hCE; tile_memory[351] = 8'h0E;
    end

    // Tile 11: Bush left (uses same colors as grass)
    initial begin
        tile_memory[352] = 8'h00; tile_memory[353] = 8'h00; tile_memory[354] = 8'h01; tile_memory[355] = 8'h10;
        tile_memory[356] = 8'h00; tile_memory[357] = 8'h01; tile_memory[358] = 8'h11; tile_memory[359] = 8'h11;
        tile_memory[360] = 8'h01; tile_memory[361] = 8'h11; tile_memory[362] = 8'h21; tile_memory[363] = 8'h11;
        tile_memory[364] = 8'h11; tile_memory[365] = 8'h12; tile_memory[366] = 8'h11; tile_memory[367] = 8'h21;
        tile_memory[368] = 8'h11; tile_memory[369] = 8'h11; tile_memory[370] = 8'h11; tile_memory[371] = 8'h11;
        tile_memory[372] = 8'h12; tile_memory[373] = 8'h11; tile_memory[374] = 8'h21; tile_memory[375] = 8'h11;
        tile_memory[376] = 8'h02; tile_memory[377] = 8'h22; tile_memory[378] = 8'h12; tile_memory[379] = 8'h21;
        tile_memory[380] = 8'h00; tile_memory[381] = 8'h02; tile_memory[382] = 8'h22; tile_memory[383] = 8'h22;
    end

    // Tile 12: Bush right
    initial begin
        tile_memory[384] = 8'h01; tile_memory[385] = 8'h10; tile_memory[386] = 8'h00; tile_memory[387] = 8'h00;
        tile_memory[388] = 8'h11; tile_memory[389] = 8'h11; tile_memory[390] = 8'h10; tile_memory[391] = 8'h00;
        tile_memory[392] = 8'h11; tile_memory[393] = 8'h12; tile_memory[394] = 8'h11; tile_memory[395] = 8'h10;
        tile_memory[396] = 8'h12; tile_memory[397] = 8'h11; tile_memory[398] = 8'h21; tile_memory[399] = 8'h11;
        tile_memory[400] = 8'h11; tile_memory[401] = 8'h11; tile_memory[402] = 8'h11; tile_memory[403] = 8'h11;
        tile_memory[404] = 8'h11; tile_memory[405] = 8'h12; tile_memory[406] = 8'h11; tile_memory[407] = 8'h21;
        tile_memory[408] = 8'h12; tile_memory[409] = 8'h21; tile_memory[410] = 8'h22; tile_memory[411] = 8'h20;
        tile_memory[412] = 8'h22; tile_memory[413] = 8'h22; tile_memory[414] = 8'h20; tile_memory[415] = 8'h00;
    end

    // Tile 13: Human (Head/Torso) - uses Palette 1
    // 8=Hair, 2=Skin, 4=Shirt, 1=Outline/Arms
    initial begin
        tile_memory[416] = 8'hFF; tile_memory[417] = 8'h88; tile_memory[418] = 8'h88; tile_memory[419] = 8'hFF;  // Hair
        tile_memory[420] = 8'hFF; tile_memory[421] = 8'h88; tile_memory[422] = 8'h88; tile_memory[423] = 8'hFF;  // Hair
        tile_memory[424] = 8'hFF; tile_memory[425] = 8'h22; tile_memory[426] = 8'h22; tile_memory[427] = 8'hFF;  // Face
        tile_memory[428] = 8'hFF; tile_memory[429] = 8'h22; tile_memory[430] = 8'h22; tile_memory[431] = 8'hFF;  // Face
        tile_memory[432] = 8'hFF; tile_memory[433] = 8'h44; tile_memory[434] = 8'h44; tile_memory[435] = 8'hFF;  // Shirt
        tile_memory[436] = 8'hFF; tile_memory[437] = 8'h44; tile_memory[438] = 8'h44; tile_memory[439] = 8'hFF;  // Shirt + Arms
        tile_memory[440] = 8'hFF; tile_memory[441] = 8'h44; tile_memory[442] = 8'h44; tile_memory[443] = 8'hFF;  // Shirt + Arms
        tile_memory[444] = 8'hFF; tile_memory[445] = 8'h44; tile_memory[446] = 8'h44; tile_memory[447] = 8'hFF;  // Shirt
    end

    // Tile 14: Human (Legs)
    // 6=Pants, 1=Shoes
    initial begin
        tile_memory[448] = 8'hFF; tile_memory[449] = 8'h66; tile_memory[450] = 8'h66; tile_memory[451] = 8'hFF;  // Pants
        tile_memory[452] = 8'hFF; tile_memory[453] = 8'h66; tile_memory[454] = 8'h66; tile_memory[455] = 8'hFF;  // Pants
        tile_memory[456] = 8'hFF; tile_memory[457] = 8'h66; tile_memory[458] = 8'h66; tile_memory[459] = 8'hFF;  // Pants
        tile_memory[460] = 8'hFF; tile_memory[461] = 8'h66; tile_memory[462] = 8'h66; tile_memory[463] = 8'hFF;  // Pants
        tile_memory[464] = 8'hFF; tile_memory[465] = 8'h66; tile_memory[466] = 8'h66; tile_memory[467] = 8'hFF;  // Pants
        tile_memory[468] = 8'hFF; tile_memory[469] = 8'h66; tile_memory[470] = 8'h66; tile_memory[471] = 8'hFF;  // Pants
        tile_memory[472] = 8'hFF; tile_memory[473] = 8'h11; tile_memory[474] = 8'h11; tile_memory[475] = 8'hFF;  // Shoes
        tile_memory[476] = 8'hFF; tile_memory[477] = 8'h11; tile_memory[478] = 8'h11; tile_memory[479] = 8'hFF;  // Shoes
    end

    // Tile 15: Blob Enemy (upper) - uses Palette 2
    // 2=Body, 4=Eyes
    initial begin
        tile_memory[480] = 8'hFF; tile_memory[481] = 8'hFF; tile_memory[482] = 8'hFF; tile_memory[483] = 8'hFF;  // Empty
        tile_memory[484] = 8'hFF; tile_memory[485] = 8'h22; tile_memory[486] = 8'h22; tile_memory[487] = 8'hFF;  // Top
        tile_memory[488] = 8'hF2; tile_memory[489] = 8'h22; tile_memory[490] = 8'h22; tile_memory[491] = 8'h2F;  // Top
        tile_memory[492] = 8'h22; tile_memory[493] = 8'h22; tile_memory[494] = 8'h22; tile_memory[495] = 8'h22;  // Body
        tile_memory[496] = 8'h22; tile_memory[497] = 8'h42; tile_memory[498] = 8'h24; tile_memory[499] = 8'h22;  // Eyes
        tile_memory[500] = 8'h22; tile_memory[501] = 8'h42; tile_memory[502] = 8'h24; tile_memory[503] = 8'h22;  // Eyes
        tile_memory[504] = 8'h22; tile_memory[505] = 8'h22; tile_memory[506] = 8'h22; tile_memory[507] = 8'h22;  // Body
        tile_memory[508] = 8'h22; tile_memory[509] = 8'h22; tile_memory[510] = 8'h22; tile_memory[511] = 8'h22;  // Body
    end

    // Tile 16: Blob Enemy (lower)
    initial begin
        tile_memory[512] = 8'h22; tile_memory[513] = 8'h22; tile_memory[514] = 8'h22; tile_memory[515] = 8'h22;  // Body
        tile_memory[516] = 8'h22; tile_memory[517] = 8'h22; tile_memory[518] = 8'h22; tile_memory[519] = 8'h22;  // Body
        tile_memory[520] = 8'h22; tile_memory[521] = 8'h22; tile_memory[522] = 8'h22; tile_memory[523] = 8'h22;  // Body
        tile_memory[524] = 8'hF2; tile_memory[525] = 8'h22; tile_memory[526] = 8'h22; tile_memory[527] = 8'h2F;  // Bottom
        tile_memory[528] = 8'hFF; tile_memory[529] = 8'h22; tile_memory[530] = 8'h22; tile_memory[531] = 8'hFF;  // Bottom
        tile_memory[532] = 8'hFF; tile_memory[533] = 8'hFF; tile_memory[534] = 8'hFF; tile_memory[535] = 8'hFF;  // Empty
        tile_memory[536] = 8'hFF; tile_memory[537] = 8'hFF; tile_memory[538] = 8'hFF; tile_memory[539] = 8'hFF;  // Empty
        tile_memory[540] = 8'hFF; tile_memory[541] = 8'hFF; tile_memory[542] = 8'hFF; tile_memory[543] = 8'hFF;  // Empty
    end

    // Tile 17: Coin sprite - uses Palette 3
    // F=transparent, 2=bright gold, 3=gold, 4=dark gold, 6=white shine
    initial begin
        tile_memory[544] = 8'hFF; tile_memory[545] = 8'h23; tile_memory[546] = 8'h32; tile_memory[547] = 8'hFF;  // __23__
        tile_memory[548] = 8'hF2; tile_memory[549] = 8'h62; tile_memory[550] = 8'h24; tile_memory[551] = 8'h3F;  // _2*224_
        tile_memory[552] = 8'h26; tile_memory[553] = 8'h22; tile_memory[554] = 8'h22; tile_memory[555] = 8'h43;  // 2*22224
        tile_memory[556] = 8'h22; tile_memory[557] = 8'h22; tile_memory[558] = 8'h22; tile_memory[559] = 8'h44;  // 22222244
        tile_memory[560] = 8'h22; tile_memory[561] = 8'h22; tile_memory[562] = 8'h22; tile_memory[563] = 8'h44;  // 22222244
        tile_memory[564] = 8'h32; tile_memory[565] = 8'h22; tile_memory[566] = 8'h24; tile_memory[567] = 8'h43;  // 322244
        tile_memory[568] = 8'hF3; tile_memory[569] = 8'h22; tile_memory[570] = 8'h44; tile_memory[571] = 8'h4F;  // _32244_
        tile_memory[572] = 8'hFF; tile_memory[573] = 8'h34; tile_memory[574] = 8'h43; tile_memory[575] = 8'hFF;  // __34__
    end


    //============================================================================
    // OAM DATA (Object Attribute Memory)
    // 32 bits per sprite: {Enable, VFlip, HFlip, Palette[2:0], Tile[8:0], Y[7:0], X[8:0]}
    //============================================================================

    initial begin
        // Robot hero - 2 tiles stacked vertically
        // Tile 13 = upper body, Tile 14 = lower body, Palette 1
        oam[0] = {1'b1, 1'b0, 1'b0, 3'd1, 9'd13, 8'd176, 9'd80};   // Robot upper at (80, 176)
        oam[1] = {1'b1, 1'b0, 1'b0, 3'd1, 9'd14, 8'd184, 9'd80};   // Robot lower at (80, 184)

        // Slime enemy #1 - 2 tiles stacked
        // Tile 15 = upper, Tile 16 = lower, Palette 2
        oam[2] = {1'b1, 1'b0, 1'b0, 3'd2, 9'd15, 8'd176, 9'd160};  // Slime upper at (160, 176)

        // Coins floating in the air - Tile 17, Palette 3
        oam[6]  = {1'b1, 1'b0, 1'b0, 3'd3, 9'd17, 8'd120, 9'd100}; // Coin at (100, 120)
        oam[7]  = {1'b1, 1'b0, 1'b0, 3'd3, 9'd17, 8'd120, 9'd116}; // Coin at (116, 120)
        oam[8]  = {1'b1, 1'b0, 1'b0, 3'd3, 9'd17, 8'd120, 9'd132}; // Coin at (132, 120)
        oam[9]  = {1'b1, 1'b0, 1'b0, 3'd3, 9'd17, 8'd80, 9'd200};  // Coin at (200, 80)
        oam[10] = {1'b1, 1'b0, 1'b0, 3'd3, 9'd17, 8'd80, 9'd216};  // Coin at (216, 80)

        // Remaining sprites disabled
        for (integer i = 11; i < 128; i = i + 1) begin
            oam[i] = 32'h0;
        end

        //========================================================================
        // Background Tile Map (64x64 tiles, 8x8 pixels each = 512x512 virtual map)
        // Screen is 320x240 = 40x30 tiles visible
        //========================================================================

        // Fill everything with sky (tile 0 = transparent)
        for (integer y = 0; y < 64; y = y + 1) begin
            for (integer x = 0; x < 64; x = x + 1) begin
                bg_tile_map[y * 64 + x] = 8'd0;
            end
        end

        // Ground layer: grass on top (tile 1), dirt below (tile 2)
        // Ground starts at tile row 24 (y=192 pixels) - bottom of 240 screen
        for (integer x = 0; x < 40; x = x + 1) begin
            bg_tile_map[24 * 64 + x] = 8'd1;  // Grass top
            bg_tile_map[25 * 64 + x] = 8'd2;  // Dirt
            bg_tile_map[26 * 64 + x] = 8'd2;  // Dirt
            bg_tile_map[27 * 64 + x] = 8'd2;  // Dirt
            bg_tile_map[28 * 64 + x] = 8'd2;  // Dirt
            bg_tile_map[29 * 64 + x] = 8'd2;  // Dirt
        end

        // Floating brick platform (tile row 17, y=136)
        bg_tile_map[17 * 64 + 12] = 8'd3;  // Brick
        bg_tile_map[17 * 64 + 13] = 8'd4;  // Question block
        bg_tile_map[17 * 64 + 14] = 8'd3;  // Brick
        bg_tile_map[17 * 64 + 15] = 8'd4;  // Question block
        bg_tile_map[17 * 64 + 16] = 8'd3;  // Brick

        // Another platform higher up (tile row 11, y=88)
        bg_tile_map[11 * 64 + 24] = 8'd3;  // Brick
        bg_tile_map[11 * 64 + 25] = 8'd3;  // Brick
        bg_tile_map[11 * 64 + 26] = 8'd4;  // Question block
        bg_tile_map[11 * 64 + 27] = 8'd3;  // Brick

        // Clouds in the sky (tile row 3-4)
        // Cloud 1
        bg_tile_map[3 * 64 + 5] = 8'd5;   // Cloud left
        bg_tile_map[3 * 64 + 6] = 8'd6;   // Cloud right
        // Cloud 2
        bg_tile_map[4 * 64 + 20] = 8'd5;  // Cloud left
        bg_tile_map[4 * 64 + 21] = 8'd6;  // Cloud right
        // Cloud 3
        bg_tile_map[2 * 64 + 32] = 8'd5;  // Cloud left
        bg_tile_map[2 * 64 + 33] = 8'd6;  // Cloud right

        // Green pipe (2 tiles wide, 3 tiles tall) at x=35
        // Pipe top (tile row 21-22)
        bg_tile_map[21 * 64 + 35] = 8'd7;  // Pipe top left
        bg_tile_map[21 * 64 + 36] = 8'd8;  // Pipe top right
        bg_tile_map[22 * 64 + 35] = 8'd9;  // Pipe body left
        bg_tile_map[22 * 64 + 36] = 8'd10; // Pipe body right
        bg_tile_map[23 * 64 + 35] = 8'd9;  // Pipe body left
        bg_tile_map[23 * 64 + 36] = 8'd10; // Pipe body right

        // Bushes on the ground (tile row 23, on top of grass)
        bg_tile_map[23 * 64 + 3]  = 8'd11; // Bush left
        bg_tile_map[23 * 64 + 4]  = 8'd12; // Bush right
        bg_tile_map[23 * 64 + 15] = 8'd11; // Bush left
        bg_tile_map[23 * 64 + 16] = 8'd12; // Bush right
        bg_tile_map[23 * 64 + 28] = 8'd11; // Bush left
        bg_tile_map[23 * 64 + 29] = 8'd12; // Bush right

        bg_palette = 3'd0; // Use palette 0 (background/world palette)

        //========================================================================
        // UI Tile Map (40x10 tiles, 8x8 pixels each)
        // UI is shown on the top and bottom 5 rows of the screen
        //========================================================================

        for (integer x = 0; x < 40; x = x + 1) begin
            for (integer y = 0; y < 10; y = y + 1) begin
                ui_tile_map[y * 40 + x] = 8'h11;
            end
        end

        ui_top_palette = 3'd2;    // Use palette 1 for top UI
        ui_bottom_palette = 3'd2; // Use palette 1 for bottom UI
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
            pixel_sync <= 0;
        end else begin
            // Background Rendering
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

            // Get background tile data
            // TODO: add scrolling offsets
            bg_tile_x = pixel_x[8:3]; // pixel_x / 8
            bg_tile_y = pixel_y[8:3]; // pixel_y / 8
            bg_tile_idx = bg_tile_map[{bg_tile_y, bg_tile_x}]; // 64x64 map

            // Local pixel within tile
            bg_local_x = pixel_x[2:0];
            bg_local_y = pixel_y[2:0];

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
            // TODO: possible optimization: only check objects that are likely to be on this scanline
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

                        // Apply flip transformations
                        if (hflip) local_x = 3'd7 - local_x;
                        if (vflip) local_y = 3'd7 - local_y;

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

endmodule
