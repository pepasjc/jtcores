/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * RetroAchievements page map for the CPS3 RAM mirror (JTFRAME_RA_MIRROR).
 * Added for the RA mirror built on jotego's jtframe (jtcores fork, branch
 * ra-mirror); not part of upstream jtcps3.
 *
 * FinalBurn Neo exposes CPS3 "Main RAM" (512 kB, SH-2 0x02000000-0x0207FFFF)
 * to RetroAchievements. Its span is far larger than the mirror, but the RA sets
 * only read a few bytes here and there, so the mirror keeps 1 kB pages of it.
 * The list is the union of the pages the five RA sets read (achievements,
 * leaderboards and rich presence display), fetched 2026-09-25:
 * sfiii (New Generation), sfiii2 (2nd Impact), jojo (JoJo's Venture),
 * redearth (Red Earth), sfiii3nr1 (3rd Strike). 31 pages, slot 31 is free.
 *
 * RA page P (RA byte offset P*0x400) lives at mirror byte offset slot*0x400.
 * The ARM side maps RA addresses with the same table.
 */

module jtcps3_ra_map(
    input      [8:0] page,  // RA byte offset [18:10] = SH-2 address [18:10]
    output reg       hit,
    output reg [4:0] slot
);

always @* begin
    hit  = 1;
    slot = 5'd0;
    case( page )
        9'h021: slot = 5'd0 ; // RA 0x08400-0x087FF  sfiii2
        9'h024: slot = 5'd1 ; // RA 0x09000-0x093FF  sfiii
        9'h028: slot = 5'd2 ; // RA 0x0A000-0x0A3FF  sfiii2
        9'h034: slot = 5'd3 ; // RA 0x0D000-0x0D3FF  sfiii
        9'h035: slot = 5'd4 ; // RA 0x0D400-0x0D7FF  sfiii
        9'h036: slot = 5'd5 ; // RA 0x0D800-0x0DBFF  sfiii
        9'h039: slot = 5'd6 ; // RA 0x0E400-0x0E7FF  sfiii2
        9'h03A: slot = 5'd7 ; // RA 0x0E800-0x0EBFF  sfiii sfiii2
        9'h03C: slot = 5'd8 ; // RA 0x0F000-0x0F3FF  redearth
        9'h040: slot = 5'd9 ; // RA 0x10000-0x103FF  sfiii2
        9'h043: slot = 5'd10; // RA 0x10C00-0x10FFF  sfiii3nr1
        9'h044: slot = 5'd11; // RA 0x11000-0x113FF  sfiii3nr1
        9'h04B: slot = 5'd12; // RA 0x12C00-0x12FFF  sfiii
        9'h050: slot = 5'd13; // RA 0x14000-0x143FF  sfiii2
        9'h055: slot = 5'd14; // RA 0x15400-0x157FF  sfiii2 sfiii3nr1
        9'h05A: slot = 5'd15; // RA 0x16800-0x16BFF  sfiii3nr1
        9'h05E: slot = 5'd16; // RA 0x17800-0x17BFF  redearth
        9'h0A0: slot = 5'd17; // RA 0x28000-0x283FF  sfiii3nr1
        9'h0A1: slot = 5'd18; // RA 0x28400-0x287FF  sfiii3nr1
        9'h0B4: slot = 5'd19; // RA 0x2D000-0x2D3FF  jojo
        9'h0BA: slot = 5'd20; // RA 0x2E800-0x2EBFF  jojo
        9'h0C1: slot = 5'd21; // RA 0x30400-0x307FF  jojo
        9'h0C2: slot = 5'd22; // RA 0x30800-0x30BFF  jojo
        9'h17B: slot = 5'd23; // RA 0x5EC00-0x5EFFF  sfiii
        9'h181: slot = 5'd24; // RA 0x60400-0x607FF  redearth
        9'h194: slot = 5'd25; // RA 0x65000-0x653FF  sfiii2
        9'h1A3: slot = 5'd26; // RA 0x68C00-0x68FFF  sfiii3nr1
        9'h1A4: slot = 5'd27; // RA 0x69000-0x693FF  sfiii3nr1
        9'h1A9: slot = 5'd28; // RA 0x6A400-0x6A7FF  redearth
        9'h1AA: slot = 5'd29; // RA 0x6A800-0x6ABFF  redearth
        9'h1AB: slot = 5'd30; // RA 0x6AC00-0x6AFFF  sfiii3nr1
        default: hit = 0;
    endcase
end

endmodule
