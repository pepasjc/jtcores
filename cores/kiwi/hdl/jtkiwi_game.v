/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 02-05-2020 */

module jtkiwi_game(
    `include "jtframe_game_ports.inc" // see $JTFRAME/hdl/inc/jtframe_game_ports.inc
);

wire        sub_rnw, shr_cs, mshramen, snd_rstn;
wire [ 7:0] shr_din, shr_dout, main_st, gfx_st, snd_st, other_st,
            vram_dout, pal_dout;
wire [ 8:0] hdump;
wire [ 1:0] eff_coin;
wire [12:0] shr_addr, cpu_addr;

wire        bram_cs, vram_cs,  pal_cs, pal2_cs, flip;
wire        cpu_rnw, vctrl_cs, vflag_cs,
            button_aid, // merges 1P, coin and
            colprom_we, mcuprom_we, eff_service;
reg         hb_dly=0, dip_flip_xor=0,
            coin_xor=0, banked_ram=0,
            kageki=0, kabuki=0, kabuki_mod = 0, service_xor=0,
            colprom_en=0, mcu_en=0, aid_en, fast_fm=0, drtoppel=0,
            unlump=0;

assign dip_flip   = ~flip ^ dip_flip_xor;
assign other_st   = { hb_dly, dip_flip_xor, coin_xor,   banked_ram,
                      kageki, kabuki,       colprom_en, mcu_en };
assign debug_view = st_addr[7:6]==0 ? gfx_st  :
                    st_addr[7:6]==1 ? main_st :
                    st_addr[7:6]==2 ? other_st  : snd_st;
assign colprom_we = prom_we && prog_addr[15:10]==0;
assign mcuprom_we = prom_we && prog_addr >= `MCU_START;
assign st_dout    = debug_view;
// Banked RAM
assign bram_we    = bram_cs & ~cpu_rnw;
// assign bram_dsn   = { 1'd1, bram_cs & cpu_rnw };
assign bram_din   = cpu_dout;
// button_aid will make up/down inputs to work as coins too. This helps
// button mapping for spinners in MiSTer
assign eff_coin   = {2{coin_xor}}^( coin[1:0] & ({2{~button_aid}}| {&joystick2[3:2],&joystick1[3:2]}));
assign eff_service= service_xor ^ service;
assign button_aid = `ifdef MISTER status[13]&aid_en `else 0 `endif ;

// RetroAchievements tap (JTFRAME_RA_TAP, mem.yaml ports ra_game_*).
// The mirror holds FBNeo's d_tnzs "All Ram" from offset 0 (TAITO_MISC):
//   ObjCtrl 0x0000, PalRAM 0x0004 (not tapped), SprRAM 0x0404 (main
//   0xC000-0xDFFF), ShareRAM 0x2404 (main/sub 0xE000-0xEFFF)
// The X1-001 object RAM (BRAM dma) is 16 bits wide: CPU byte 0xC000+o sits
// in word o[11:0], lane o[12]. The CPU writes one lane; the X1-001 buffer
// copy writes both, and they are FBNeo bytes o and o+0x1000, so each lane is
// its own source.
wire ra_mwe, ra_swe;
wire [15:0] ra_dma_lo = 16'h0404 + { 4'd0, dma_addr[12:1] };
wire [15:0] ra_dma_hi = 16'h1404 + { 4'd0, dma_addr[12:1] };
wire [15:0] ra_shm    = 16'h2404 + { 4'd0, cpu_addr[11:0] };
wire [15:0] ra_shs    = 16'h2404 + { 4'd0, shr_addr[11:0] };

// Each source is held in a register until the mirror port takes it and the
// registers are served in turn. CPU writes to the object RAM and sub CPU
// writes to the shared RAM last a single clock cycle, so they must not be
// dropped when two sources collide.
wire [63:0] ras_addr = { ra_dma_hi, ra_dma_lo, ra_shs, ra_shm };
wire [63:0] ras_din  = { {2{dma_din[15:8]}}, {2{dma_din[7:0]}}, {2{shr_din}}, {2{cpu_dout}} };
wire [ 7:0] ras_we   = {
        {2{dma_we[1]}} & (ra_dma_hi[0] ? 2'b10 : 2'b01),
        {2{dma_we[0]}} & (ra_dma_lo[0] ? 2'b10 : 2'b01),
        {2{ra_swe   }} & (ra_shs[0]    ? 2'b10 : 2'b01),
        {2{ra_mwe   }} & (ra_shm[0]    ? 2'b10 : 2'b01) };
reg  [63:0] rah_addr, rah_din;
reg  [ 7:0] rah_we;
reg  [ 1:0] ra_ptr, ra_sel, ra_k;
reg         ra_any;
integer     rak;

assign ra_game_addr = rah_addr[ ra_sel*16 +: 16 ];
assign ra_game_din  = rah_din [ ra_sel*16 +: 16 ];
assign ra_game_we   = ra_any ? rah_we[ ra_sel*2 +: 2 ] : 2'd0;

always @* begin
    ra_any = 0;
    ra_sel = ra_ptr;
    for( rak=3; rak>=0; rak=rak-1 ) begin
        ra_k = ra_ptr + rak[1:0];
        if( rah_we[ ra_k*2 +: 2 ]!=0 ) begin
            ra_any = 1;
            ra_sel = ra_k;
        end
    end
end

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        rah_we <= 0;
        ra_ptr <= 0;
    end else begin
        if( ra_any ) ra_ptr <= ra_sel + 2'd1;
        for( rak=0; rak<4; rak=rak+1 ) begin
            if( ras_we[ rak*2 +: 2 ]!=0 ) begin
                rah_addr[ rak*16 +: 16 ] <= ras_addr[ rak*16 +: 16 ];
                rah_din [ rak*16 +: 16 ] <= ras_din [ rak*16 +: 16 ];
                rah_we  [ rak*2  +: 2  ] <= ras_we  [ rak*2  +: 2  ];
            end else if( ra_any && ra_sel==rak ) begin
                rah_we  [ rak*2  +: 2  ] <= 2'd0;
            end
        end
    end
end

always @(posedge clk) begin
    if( prog_we && header ) begin
        if( prog_addr==0 )
            { hb_dly, dip_flip_xor, coin_xor, banked_ram,
              kageki, kabuki, colprom_en, mcu_en } <= prog_data;
        else if( prog_addr==1 )
            { unlump, drtoppel, kabuki_mod, fast_fm, aid_en, service_xor } <= prog_data[5:0];
    end
end

/* verilator tracing_on */
jtkiwi_main u_main(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .cen6           ( cen6          ),

    .LVBL           ( LVBL          ),
    .hcnt           ( hdump         ),
    .colprom_en     ( colprom_en    ),
    // Banked RAM
    .banked_ram     ( banked_ram    ),
    .bram_cs        ( bram_cs       ),
    .bram_ok        ( 1'b1 ), //bram_ok       ),
    .bram_data      ( bram_dout     ),
    .bram_addr      ( bram_addr     ),
    // Main CPU ROM
    .rom_addr       ( main_addr     ),
    .rom_cs         ( main_cs       ),
    .rom_data       ( main_data     ),

    // Sub CPU access to shared RAM
    .shr_addr       ( shr_addr      ),
    .shr_dout       ( shr_dout      ),
    .sub_rnw        ( sub_rnw       ),
    .shr_din        ( shr_din       ),
    .shr_cs         ( shr_cs        ),
    .mshramen       ( mshramen      ),
    .ra_mwe         ( ra_mwe        ),
    .ra_swe         ( ra_swe        ),
    // Sound
    .snd_rstn       ( snd_rstn      ),

    // Video
    .cpu_addr       ( cpu_addr      ),
    .cpu_dout       ( cpu_dout      ),
    .cpu_rnw        ( cpu_rnw       ),

    .vctrl_cs       ( vctrl_cs      ),
    .vram_cs        ( vram_cs       ),
    .vflag_cs       ( vflag_cs      ),
    .vram_dout      ( vram_dout     ),

    .pal_cs         ( pal_cs        ),
    .pal_dout       ( pal_dout      ),
    .dip_pause      ( dip_pause     ),
    .debug_bus      ( debug_bus     ),
    .st_dout        ( main_st       )
);

/* verilator tracing_on */
jtkiwi_video u_video(
    .rst            ( rst           ),
    .clk            ( clk           ),
    .clk_cpu        ( clk           ),

    .pxl2_cen       ( pxl2_cen      ),
    .pxl_cen        ( pxl_cen       ),
    .hb_dly         ( hb_dly        ),
    .LHBL           ( LHBL          ),
    .LVBL           ( LVBL          ),
    .HS             ( HS            ),
    .VS             ( VS            ),
    .flip           ( flip          ),
    .hdump          ( hdump         ),
    .drtoppel       ( drtoppel      ),
    // PROMs
    .prom_we        ( colprom_we    ),
    .prog_addr      ( prog_addr[9:0]),
    .prog_data      ( prog_data     ),
    .colprom_en     ( colprom_en    ),
    // GFX - CPU interface
    .cpu_rnw        ( cpu_rnw       ),
    .cpu_addr       ( cpu_addr      ),
    .cpu_dout       ( cpu_dout      ),

    .vram_cs        ( vram_cs       ),
    .vctrl_cs       ( vctrl_cs      ),
    .vflag_cs       ( vflag_cs      ),
    .vram_dout      ( vram_dout     ),

    .pal_cs         ( pal_cs        ),
    .pal_dout       ( pal_dout      ),

    .pal2_cs        ( pal2_cs       ),
    .cpu2_dout      ( shr_din       ),
    .cpu2_rnw       ( sub_rnw       ),
    .cpu2_addr      ( shr_addr[9:0] ),

    // X1-001 Internal RAM
    .col_addr       ( col_addr      ),
    .col_data       ( col_data      ),
    .yram_dout      ( yram_dout     ),
    .yram_we        ( yram_we       ),
    // X1-001 External VRAM
    .dma_addr       ( dma_addr      ),
    .dma_din        ( dma_din       ),
    .dma_we         ( dma_we        ),
    .dma_dout       ( dma_dout      ),
    .code_dout      ( code_dout     ),
    .code_addr      ( code_addr     ),

    // SDRAM
    .scr_addr       ( scr_addr      ),
    .scr_data       ( scr_data      ),
    .scr_ok         ( scr_ok        ),
    .scr_cs         ( scr_cs        ),

    .obj_addr       ( obj_addr      ),
    .obj_data       ( obj_data      ),
    .obj_ok         ( obj_ok        ),
    .obj_cs         ( obj_cs        ),
    // pixels
    .red            ( red           ),
    .green          ( green         ),
    .blue           ( blue          ),
    // Test
    .gfx_en         ( gfx_en        ),
    .debug_bus      ( debug_bus     ),
    .st_dout        ( gfx_st        )
);

/* verilator tracing_off */
jtkiwi_snd u_sound(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .snd_rstn   ( snd_rstn      ),
    .fast_fm    ( fast_fm       ),
    .unlump     ( unlump        ),
    .cen6       ( cen6          ),
    .cen3       ( cen3          ),
    .cen1p5     ( cen1p5        ),
    .LVBL       ( LVBL          ),
    // Game variations
`ifdef NOKABUKIZ
    .kabuki     ( 1'b0          ),
    .kabuki_mod ( 1'b0          ),
`else
    .kabuki     ( kabuki        ),
    .kabuki_mod ( kabuki_mod    ), // different memory map for TNZS
`endif
    .kageki     ( kageki        ),

    // PCM
    .pcm_addr   ( pcm_addr      ),
    .pcm_data   ( pcm_data      ),
    .pcm_ok     ( pcm_ok        ),
    .pcm_cs     ( pcm_cs        ),

    // cabinet I/O
    .cab_1p     ( cab_1p[1:0]   ),
    .coin       ( eff_coin      ),
    .joystick1  ( joystick1     ),
    .joystick2  ( joystick2     ),
    .service    ( eff_service   ),
    .tilt       ( tilt          ),
    .dial_x     ( dial_x        ),
    .dial_y     ( dial_y        ),
    // DIP switches
    .dipsw      ( dipsw[15:0]   ),
    .dip_pause  ( dip_pause     ),

    // Shared RAM
    .ram_addr   ( shr_addr      ),
    .ram_din    ( shr_din       ),
    .ram_dout   ( shr_dout      ),
    .cpu_rnw    ( sub_rnw       ),
    .ram_cs     ( shr_cs        ),
    .mshramen   ( mshramen      ),
    .pal_cs     ( pal2_cs       ),
    .pal_dout   ( pal_dout      ),
    // MCU
    .mcu_en     ( mcu_en        ),
    .prog_addr  ( prog_addr[10:0]),
    .prog_data  ( prog_data     ),
    .prom_we    ( mcuprom_we    ),

    // ROM
    .rom_addr   ( sub_addr      ),
    .rom_cs     ( sub_cs        ),
    .rom_data   ( sub_data      ),

    .audiocpu_addr ( audiocpu_addr ),
    .audiocpu_cs   ( audiocpu_cs   ),
    .audiocpu_data ( audiocpu_data ),
    .audiocpu_ok   ( audiocpu_ok   ),

    // Sound output
    .fm         ( fm            ),
    .psg        ( psg           ),
    .pcm        ( pcm           ),
    // Debug
    .debug_bus  ( debug_bus     ),
    .st_addr    ( st_addr       ),
    .st_dout    ( snd_st        )
);

endmodule
