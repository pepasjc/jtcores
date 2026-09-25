/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * RetroAchievements RAM mirror for JTFRAME MiSTer cores.
 *
 * Keeps a shadow copy of a 64 kB work RAM held in SDRAM bank 0 by snooping
 * the bank-0 write bus, and copies it to DDR3 every VBlank so the ARM side
 * (odelot's RetroAchievements fork of Main_MiSTer) can evaluate achievements.
 *
 * DDR layout at byte address 0x3D000000 (the "RACH" Full Mirror header used
 * by the RA fork, see Main_MiSTer ra_ramread.h):
 *   0x00  magic "RACH" (0x52414348 LE), region count 0, flags (bit0 busy),
 *         core version
 *   0x08  frame counter (u32)
 *   0x10  zero (keeps stale mailbox/protocol bytes of other cores clear)
 *   0x100 64 kB of RAM. Each 16-bit word is stored as-is in a little-endian
 *         DDR lane, so byte k is the CPU byte at (k ^ 1) - the layout
 *         FinalBurn Neo exposes for 68000 RAM, which RA arcade sets expect.
 *
 * Copy order: header with busy=1, data, frame counter, header with busy=0.
 * The ARM only accepts a snapshot when busy is clear and the frame counter
 * did not move during its copy.
 *
 * The screen rotation client writes DDR only during active video and does
 * not look at DDRAM_BUSY, so the copy runs right after VBlank starts and
 * takes ~0.1 ms of the ~2.4 ms VBlank (256 bursts of 32 beats).
 */

module jtframe_ra_mirror #(parameter
    SDRAMW    = 23,
    WRAM_BASE = 23'h30_0000,   // SDRAM word address of the RAM in bank 0
    DDR_BASE  = 29'h07A0_0000, // 0x3D000000 / 8
    VERSION   = 16'h0100
)(
    input               rst,
    input               clk,        // clk_rom: SDRAM and DDR client clock
    input               lvbl,
    input               hold,       // ROM download in progress
    // SDRAM bank 0 write snoop
    input  [SDRAMW-1:0] ba0_addr,
    input               ba0_wr,
    input        [15:0] ba0_din,
    input        [ 1:0] ba0_dsn,
    // DDR client
    output reg          active,     // owns the DDR client port
    input               ddr_busy,
    output reg   [ 7:0] ddr_burstcnt,
    output reg   [28:0] ddr_addr,
    output reg          ddr_we,
    output       [ 7:0] ddr_be,
    output reg   [63:0] ddr_din
);

localparam [31:0] MAGIC  = 32'h5241_4348;
localparam  [7:0] BURST  = 8'd32;     // 256 B: aligned, never crosses 4 kB
localparam        QWORDS = 8192;     // 64 kB

localparam [2:0] IDLE=0, HDR_BUSY=1, PRE=2, DATA=3, FRAME=4, HDR_DONE=5, ZERO=6;

// ---------------------------------------------------------------------------
// Shadow RAM: eight byte lanes of 8k x 8, so a whole DDR qword reads at once
wire        hit  = ba0_wr && ba0_addr[SDRAMW-1:15] == WRAM_BASE[SDRAMW-1:15];
wire [12:0] wr_q = ba0_addr[14:2];
wire [ 1:0] lane = ba0_addr[1:0];

reg  [ 2:0] st;
reg  [12:0] ptr;
wire        accept = ddr_we && !ddr_busy && st == DATA;
wire [12:0] rd_q   = accept ? ptr + 13'd1 : ptr;
wire [63:0] q;

genvar b;
generate
    for( b=0; b<8; b=b+1 ) begin : lanes
        // byte 2L = word[7:0] (low byte, odd CPU address), 2L+1 = word[15:8]
        wire we = hit && lane == b/2 && !ba0_dsn[b%2];
        jtframe_dual_ram #(.DW(8),.AW(13)) u_lane(
            .clk0   ( clk       ),
            .data0  ( b%2 ? ba0_din[15:8] : ba0_din[7:0] ),
            .addr0  ( wr_q      ),
            .we0    ( we        ),
            .q0     (           ),
            .clk1   ( clk       ),
            .data1  ( 8'd0      ),
            .addr1  ( rd_q      ),
            .we1    ( 1'b0      ),
            .q1     ( q[b*8+:8] )
        );
    end
endgenerate

// ---------------------------------------------------------------------------
// Copier
reg         lvbl_l;
reg  [31:0] frame;
reg  [ 4:0] beat;
reg         zeroed;

assign ddr_be = 8'hff;

always @(*) begin
    ddr_din = q;
    case( st )
        HDR_BUSY: ddr_din = { VERSION, 8'h01, 8'd0, MAGIC };
        HDR_DONE: ddr_din = { VERSION, 8'h00, 8'd0, MAGIC };
        FRAME:    ddr_din = { 32'd0, frame };
        ZERO:     ddr_din = 64'd0;
        default:;
    endcase
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        st           <= IDLE;
        active       <= 0;
        ddr_we       <= 0;
        ddr_burstcnt <= 8'd1;
        ddr_addr     <= DDR_BASE;
        ptr          <= 0;
        beat         <= 0;
        frame        <= 0;
        lvbl_l       <= 1;
        zeroed       <= 0;
    end else begin
        lvbl_l <= lvbl;
        case( st )
            IDLE: begin
                ddr_we <= 0;
                active <= 0;
                if( lvbl_l && !lvbl && !hold ) begin
                    active       <= 1;
                    ddr_addr     <= DDR_BASE;
                    ddr_burstcnt <= 8'd1;
                    ddr_we       <= 1;
                    st           <= HDR_BUSY;
                end
            end
            HDR_BUSY: if( !ddr_busy ) begin
                ddr_we <= 0;
                ptr    <= 0;
                st     <= PRE;
            end
            PRE: begin // ptr settles into the read port
                ddr_addr     <= DDR_BASE + 29'h20;
                ddr_burstcnt <= BURST;
                beat         <= 0;
                ddr_we       <= 1;
                st           <= DATA;
            end
            DATA: if( accept ) begin
                ptr  <= ptr + 13'd1;
                beat <= beat + 5'd1;
                if( &beat ) begin
                    ddr_addr <= ddr_addr + { 21'd0, BURST };
                    if( ptr == QWORDS-1 ) begin
                        ddr_addr     <= DDR_BASE + 29'h1;
                        ddr_burstcnt <= 8'd1;
                        frame        <= frame + 32'd1;
                        st           <= FRAME;
                    end
                end
            end
            FRAME: if( !ddr_busy ) begin
                ddr_addr <= zeroed ? DDR_BASE : DDR_BASE + 29'h2;
                st       <= zeroed ? HDR_DONE : ZERO;
            end
            ZERO: if( !ddr_busy ) begin
                zeroed   <= 1;
                ddr_addr <= DDR_BASE;
                st       <= HDR_DONE;
            end
            HDR_DONE: if( !ddr_busy ) begin
                ddr_we <= 0;
                active <= 0;
                st     <= IDLE;
            end
            default: st <= IDLE;
        endcase
    end
end

endmodule
