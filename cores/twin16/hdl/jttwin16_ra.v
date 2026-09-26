/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * RetroAchievements write-tap arbiter (RA mirror fork of jtcores).
 *
 * Merges N RAM write ports into the single ra_game_* tap that feeds
 * jtframe_ra_mirror. Each source is a mirror byte address, 16-bit data and
 * active-high byte enables (bit 1 = bits 15:8). A source's latest write is
 * captured every cycle its enables are high and stays pending until it is
 * granted; grants rotate round-robin, one per clock. Two CPUs on the same
 * clock enable can hold identical write strobes, which a fixed-priority mux
 * would drop entirely; here every write reaches the mirror, a few cycles late
 * at most. Re-sending a write whose strobe is still active is harmless.
 */

module jttwin16_ra #(parameter N=3)(
    input                 rst,
    input                 clk,
    input      [N*16-1:0] addr,
    input      [N*16-1:0] din,
    input      [N*2 -1:0] we,
    output reg     [15:0] ra_addr,
    output reg     [15:0] ra_din,
    output reg     [ 1:0] ra_we
);

reg  [N   -1:0] pv;
reg  [N*16-1:0] pa, pd;
reg  [N*2 -1:0] pb;
reg  [     3:0] last, sel;
reg             found;
integer         i, k;

always @* begin
    found = 0;
    sel   = last;
    for( i=1; i<=N; i=i+1 ) begin
        k = last + i;
        if( k >= N ) k = k - N;
        if( !found && pv[k] ) begin
            found = 1;
            sel   = k[3:0];
        end
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        pv      <= 0;
        pa      <= 0;
        pd      <= 0;
        pb      <= 0;
        last    <= 0;
        ra_addr <= 0;
        ra_din  <= 0;
        ra_we   <= 0;
    end else begin
        ra_we <= 0;
        if( found ) begin
            ra_addr <= pa[sel*16+:16];
            ra_din  <= pd[sel*16+:16];
            ra_we   <= pb[sel*2+:2];
            last    <= sel;
        end
        for( i=0; i<N; i=i+1 ) begin
            if( |we[i*2+:2] ) begin
                pv[i]        <= 1;
                pa[i*16+:16] <= addr[i*16+:16];
                pd[i*16+:16] <= din [i*16+:16];
                pb[i*2+:2]   <= we  [i*2+:2];
            end else if( found && sel==i ) begin
                pv[i] <= 0;
            end
        end
    end
end

endmodule
