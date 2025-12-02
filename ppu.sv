module ppu #(
    parameter DISP_WIDTH  = 320,
    parameter DISP_HEIGHT = 240
) (
    input  logic clk,
    input  logic reset,

    // Pixel outputs
    output logic [7:0] pixel_r,
    output logic [7:0] pixel_g,
    output logic [7:0] pixel_b,

    // Memory interface for external access
    output logic [19:0] mem_addr,    // 20 bits for 1 MB addressing
    input  logic [31:0] mem_rdata,   // 32-bit read data from external RAM
    output logic [31:0] mem_wdata,   // 32-bit write data to external RAM
    output logic        mem_read,    // Read request
    output logic        mem_write    // Write request
);

    // 1 MB RAM = 1024 * 1024 = 1048576 bytes
    localparam RAM_SIZE = 1024 * 1024;
    localparam ADDR_WIDTH = 20;

    // Pixel position counters
    reg [9:0] pixel_x;
    reg [8:0] pixel_y;

    // Cached read data
    reg [31:0] cached_rdata;

    // Main PPU logic
    always_ff @(posedge clk) begin
        if (reset) begin
            pixel_x <= 0;
            pixel_y <= 0;
            mem_addr <= 0;
            mem_read <= 0;
            mem_write <= 0;
            mem_wdata <= 0;
            pixel_r <= 0;
            pixel_g <= 0;
            pixel_b <= 0;
            cached_rdata <= 0;
        end else begin
            // Cache the read data
            cached_rdata <= mem_rdata;

            // Calculate RAM address based on pixel position (RGBA)
            mem_addr <= (20'(pixel_y) * 20'(DISP_WIDTH) + 20'(pixel_x)) * 20'd4;

            // Always reading during active display
            mem_read <= 1;
            mem_write <= 0;

            // Output pixel colors from RAM data
            // Using different bytes of the 32-bit word for RGB
            pixel_r <= cached_rdata[7:0];
            pixel_g <= cached_rdata[15:8];
            pixel_b <= cached_rdata[23:16];

            // Update pixel position
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
