; NES Game Example - Ball and Player Collision with Score Display
; ---------------------------------------------------------------
; This file implements a simple NES game where balls bounce and
; the player can move a sprite. The score increments each time
; a ball collides with the player, and is displayed on screen.

.include "nes.inc"           ; NES hardware register definitions
.include "macros.inc"        ; Useful macros

; Sprite memory locations for easy access
SPRITE_0_ADDR = oam + 0      ; Player sprite 0
SPRITE_1_ADDR = oam + 4      ; Player sprite 1
SPRITE_2_ADDR = oam + 8      ; Player sprite 2
SPRITE_3_ADDR = oam + 12     ; Player sprite 3
SPRITE_BALL_0_ADDR = oam + 16 ; Ball sprite 0
SPRITE_BALL_1_ADDR = oam + 20 ; Ball sprite 1
SPRITE_BALL_2_ADDR = oam + 24 ; Ball sprite 2
SPRITE_BALL_3_ADDR = oam + 28 ; Ball sprite 3
SPRITE_BALL_4_ADDR = oam + 32 ; Ball sprite 4
SPRITE_BALL_5_ADDR = oam + 36 ; Ball sprite 5
SPRITE_BALL_6_ADDR = oam + 40 ; Ball sprite 6
SPRITE_BALL_7_ADDR = oam + 44 ; Ball sprite 7

SPRITE_OFFSET_ATTR = 2       ; Offset for sprite attribute byte

;================ NES ROM HEADER ================
.segment "HEADER"
.byte 'N', 'E', 'S', $1a      ; NES signature
.byte $02                     ; 2 x 16KB PRG-ROM
.byte $01                     ; 1 x 8KB CHR-ROM
.byte $01, $00                ; Mapper 0, no special features

;================ INTERRUPT VECTORS ================
.segment "VECTORS"
.addr nmi_handler         ; NMI vector
.addr reset_handler       ; Reset vector
.addr irq_handler         ; IRQ vector

;================ ZERO PAGE VARIABLES ================
.segment "ZEROPAGE"
; General purpose and game state variables
 temp_var:               .res 1   ; Temporary variable
 temp_var2:              .res 1   ; Second temp variable
 temp_ptr_low:           .res 1   ; Pointer low byte
 temp_ptr_high:          .res 1   ; Pointer high byte
 random_num:             .res 1   ; Random number seed

 num_balls:              .res 1   ; Number of active balls
 ball_spawn_timer:       .res 1   ; Timer for spawning balls
 max_balls:              .res 1   ; Maximum balls allowed

 ball_x:                 .res 8   ; X positions of balls
 ball_y:                 .res 8   ; Y positions of balls
 ball_dx:                .res 8   ; X velocities of balls
 ball_dy:                .res 8   ; Y velocities of balls
 ball_active:            .res 8   ; Ball active flags

                        .res 11  ; Padding

 controller_1:           .res 1   ; Controller 1 state
 controller_2:           .res 1   ; Controller 2 state
 controller_1_prev:      .res 1   ; Previous controller 1 state
 controller_2_prev:      .res 1   ; Previous controller 2 state
 controller_1_pressed:   .res 1   ; Buttons pressed this frame
 controller_1_released:  .res 1   ; Buttons released this frame

                        .res 10  ; Padding

 game_state:             .res 1   ; Game state (unused)
 player_x:               .res 1   ; Player X position
 player_y:               .res 1   ; Player Y position
 player_vel_x:           .res 1   ; Player X velocity (unused)
 player_vel_y:           .res 1   ; Player Y velocity (unused)
 score:                  .res 1   ; Player score
 scroll:                 .res 1   ; Screen scroll value
 time:                   .res 1   ; Frame counter
 seconds:                .res 1   ; Seconds counter
                        .res 07  ; Padding

;================ OAM (SPRITE RAM) ================
.segment "OAM"
oam: .res 256                ; Sprite attribute memory

;================ MAIN CODE SEGMENT ================
.segment "CODE"

; IRQ handler (not used, but required by NES)
.proc irq_handler
  PHA
  TXA
  PHA
  TYA
  PHA
  INC time                  ; Increment frame counter
  PLA
  TAY
  PLA
  TAX
  PLA
  RTI
.endproc

; NMI handler (increments time and seconds)
.proc nmi_handler
  PHA
  TXA
  PHA
  TYA
  PHA
  INC time
  LDA time
  CMP #60
  BNE skip
    INC seconds
    LDA #0
    STA time
  skip:
  PLA
  TAY
  PLA
  TAX
  PLA
  RTI
.endproc

; Load palette data into PPU
.proc set_palette
    vram_set_address PALETTE_ADDRESS
    LDX #$00
@loop:
    LDA palette_data, X
    STA PPU_VRAM_IO
    INX
    CPX #$20
    BNE @loop
    RTS
.endproc

; Load nametable (background) data into PPU
.proc set_nametable
    wait_for_vblank
    vram_set_address NAME_TABLE_0_ADDRESS
    LDA #<nametable_data
    STA temp_ptr_low
    LDA #>nametable_data
    STA temp_ptr_high
    LDY #$00
    LDX #$03
load_page:
    LDA (temp_ptr_low),Y
    STA PPU_VRAM_IO
    INY
    BNE load_page
    INC temp_ptr_high
    DEX
    BNE load_page
check_remaining:
    LDY #$00
remaining_loop:
    LDA (temp_ptr_low),Y
    STA PPU_VRAM_IO
    INY
    CPY #192
    BNE remaining_loop
    ; No longer draw score here
    LDA #$00
    STA PPU_SCROLL
    STA PPU_SCROLL
    RTS
.endproc

; Initialize player and ball sprites
.proc init_sprites
  LDX #0
  load_sprite:
    LDA sprite_data, x
    STA SPRITE_0_ADDR, x
    INX
    CPX #4
    BNE load_sprite
  ; Set player sprite tiles
  LDA #1
  STA SPRITE_0_ADDR + SPRITE_OFFSET_TILE
  LDA #2
  STA SPRITE_1_ADDR + SPRITE_OFFSET_TILE
  LDA #3
  STA SPRITE_2_ADDR + SPRITE_OFFSET_TILE
  LDA #4
  STA SPRITE_3_ADDR + SPRITE_OFFSET_TILE
  ; Initialize ball system
  LDA #0
  STA num_balls
  STA ball_spawn_timer
  LDA #2
  STA max_balls
  ; Clear all ball slots
  LDX #0
clear_balls:
  LDA #0
  STA ball_active, X
  INX
  CPX #2
  BNE clear_balls
  ; Hide all ball sprites
  LDX #0
init_ball_sprites:
  TXA
  ASL
  ASL
  CLC
  ADC #<SPRITE_BALL_0_ADDR
  STA temp_ptr_low
  LDA #>SPRITE_BALL_0_ADDR
  ADC #0
  STA temp_ptr_high
  LDY #SPRITE_OFFSET_Y
  LDA #$FF
  STA (temp_ptr_low), Y
  LDY #SPRITE_OFFSET_TILE
  LDA #5
  STA (temp_ptr_low), Y
  LDY #SPRITE_OFFSET_ATTR
  LDA #0
  STA (temp_ptr_low), Y
  LDY #SPRITE_OFFSET_X
  LDA #0
  STA (temp_ptr_low), Y
  INX
  CPX #2
  BNE init_ball_sprites
  ; Set initial player position
  LDA #128
  STA player_x
  LDA #170
  STA player_y
  ; Spawn first ball
  JSR spawn_ball
  RTS
.endproc

; Update all sprite positions in OAM
.proc update_sprites
  ; Update player sprite X positions
  LDA player_x
  STA SPRITE_0_ADDR + SPRITE_OFFSET_X
  STA SPRITE_2_ADDR + SPRITE_OFFSET_X
  CLC
  ADC #8
  STA SPRITE_1_ADDR + SPRITE_OFFSET_X
  STA SPRITE_3_ADDR + SPRITE_OFFSET_X
  ; Update player sprite Y positions
  LDA player_y
  STA SPRITE_0_ADDR + SPRITE_OFFSET_Y
  STA SPRITE_1_ADDR + SPRITE_OFFSET_Y
  CLC
  ADC #8
  STA SPRITE_2_ADDR + SPRITE_OFFSET_Y
  STA SPRITE_3_ADDR + SPRITE_OFFSET_Y
  ; Restore player sprite tile indices
  LDA #1
  STA SPRITE_0_ADDR + SPRITE_OFFSET_TILE
  LDA #2
  STA SPRITE_1_ADDR + SPRITE_OFFSET_TILE
  LDA #3
  STA SPRITE_2_ADDR + SPRITE_OFFSET_TILE
  LDA #4
  STA SPRITE_3_ADDR + SPRITE_OFFSET_TILE
  ; Update all ball sprites
  LDX #0
update_ball_sprites:
  LDA ball_active, X
  BEQ hide_ball
  TXA
  ASL
  ASL
  CLC
  ADC #<SPRITE_BALL_0_ADDR
  STA temp_ptr_low
  LDA #>SPRITE_BALL_0_ADDR
  ADC #0
  STA temp_ptr_high
  LDY #SPRITE_OFFSET_Y
  LDA ball_y, X
  STA (temp_ptr_low), Y
  LDY #SPRITE_OFFSET_X
  LDA ball_x, X
  STA (temp_ptr_low), Y
  LDY #SPRITE_OFFSET_TILE
  LDA #5
  STA (temp_ptr_low), Y
  LDY #SPRITE_OFFSET_ATTR
  LDA #0
  STA (temp_ptr_low), Y
  JMP next_sprite
hide_ball:
  TXA
  ASL
  ASL
  CLC
  ADC #<SPRITE_BALL_0_ADDR
  STA temp_ptr_low
  LDA #>SPRITE_BALL_0_ADDR
  ADC #0
  STA temp_ptr_high
  LDY #SPRITE_OFFSET_Y
  LDA #$FF
  STA (temp_ptr_low), Y
next_sprite:
  INX
  CPX #2
  BNE update_ball_sprites
  ; Set player sprite attributes
  LDA #0
  STA SPRITE_0_ADDR + SPRITE_OFFSET_ATTR
  STA SPRITE_1_ADDR + SPRITE_OFFSET_ATTR
  STA SPRITE_2_ADDR + SPRITE_OFFSET_ATTR
  STA SPRITE_3_ADDR + SPRITE_OFFSET_ATTR
  ; Screen scroll
  LDA #$00
  STA PPU_SCROLL
  DEC scroll
  LDA scroll
  STA PPU_SCROLL
  ; OAM DMA
  LDA #$00
  STA PPU_SPRRAM_ADDRESS
  LDA #>oam
  STA SPRITE_DMA
  RTS
.endproc

; Handle player movement based on controller input
.proc update_player
    LDA controller_1
    AND #PAD_L
    BEQ not_left
      LDA player_x
      SEC
      SBC #$01
      STA player_x
not_left:
    LDA controller_1
    AND #PAD_R
    BEQ not_right
      LDA player_x
      CLC
      ADC #$01
      STA player_x
  not_right:
    LDA controller_1
    AND #PAD_U
    BEQ not_up
      LDA player_y
      SEC
      SBC #$01
      STA player_y
  not_up:
    LDA controller_1
    AND #PAD_D
    BEQ not_down
      LDA player_y
      CLC
      ADC #$01
      STA player_y
  not_down:
    RTS
.endproc

; Update all balls: movement, wall bounce, and collisions
.proc update_ball
  INC ball_spawn_timer
  LDA ball_spawn_timer
  CMP #180
  BNE no_spawn
  LDA #0
  STA ball_spawn_timer
  LDA num_balls
  CMP max_balls
  BCS no_spawn
  JSR spawn_ball
no_spawn:
  LDX #0
update_loop:
  LDA ball_active, X
  BEQ next_ball
  ; Move ball vertically
  LDA ball_y, X
  CLC
  ADC ball_dy, X
  STA ball_y, X
  CMP #20
  BCC bounce_top
  CMP #210
  BCS bounce_bottom
  JMP check_x
bounce_top:
  LDA #1
  STA ball_dy, X
  JSR play_random_wall_bounce_sound
  JMP check_x
bounce_bottom:
  LDA #$FF
  STA ball_dy, X
  JSR play_random_wall_bounce_sound
  JMP check_x
check_x:
  ; Move ball horizontally
  LDA ball_x, X
  CLC
  ADC ball_dx, X
  STA ball_x, X
  CMP #8
  BCC bounce_left
  CMP #248
  BCS bounce_right
  JMP next_ball
bounce_left:
  LDA #1
  STA ball_dx, X
  JSR play_random_wall_bounce_sound
  JMP next_ball
bounce_right:
  LDA #$FF
  STA ball_dx, X
  JSR play_random_wall_bounce_sound
  JMP next_ball
next_ball:
  INX
  CPX #2
  BNE update_loop
  ; Ball-to-ball and ball-to-player collision
  JSR check_ball_collisions
  JSR check_ball_player_collision
  RTS
.endproc

; Ball-to-ball collision: reverse dx/dy if two balls overlap (8x8 AABB)
.proc check_ball_collisions
  LDX #0
outer_ball:
  LDA ball_active, X
  BEQ next_outer
  STX temp_var
  LDY temp_var
@inner_loop:
    INY
    CPY #2
    BCS next_outer
    LDA ball_active, Y
    BEQ @next_inner
    ; Compare X overlap
    LDA ball_x, X
    SEC
    SBC ball_x, Y
    CLC
    ADC #8
    CMP #16
    BCS @next_inner
    ; Compare Y overlap
    LDA ball_y, X
    SEC
    SBC ball_y, Y
    CLC
    ADC #8
    CMP #16
    BCS @next_inner
    ; Collision! Reverse both dx/dy
    LDA ball_dx, X
    EOR #$FF
    CLC
    ADC #1
    STA ball_dx, X
    LDA ball_dy, X
    EOR #$FF
    CLC
    ADC #1
    STA ball_dy, X
    LDA ball_dx, Y
    EOR #$FF
    CLC
    ADC #1
    STA ball_dx, Y
    LDA ball_dy, Y
    EOR #$FF
    CLC
    ADC #1
    STA ball_dy, Y
    JSR play_bounce_sound
@next_inner:
    JMP @inner_loop
next_outer:
  INX
  CPX #2
  BNE outer_ball
  RTS
.endproc

; Draws the score label and value to the screen at a fixed position
; Writes 'SCORE: ' followed by the current score digit
.proc draw_score
    LDA PPU_STATUS
    LDA #$20           ; High byte of VRAM address
    STA PPU_ADDRESS
    LDA #$8A           ; Low byte of VRAM address (column/row)
    STA PPU_ADDRESS
    ; Write the label 'SCORE: '
    LDA #'S'
    STA PPU_VRAM_IO
    LDA #'C'
    STA PPU_VRAM_IO
    LDA #'O'
    STA PPU_VRAM_IO
    LDA #'R'
    STA PPU_VRAM_IO
    LDA #'E'
    STA PPU_VRAM_IO
    LDA #':'
    STA PPU_VRAM_IO
    LDA #' '
    STA PPU_VRAM_IO
    ; Write the score digit (convert 0-9 to ASCII)
    LDA #'0'
    CLC
    ADC score
    STA PPU_VRAM_IO
    LDA #$00
    STA PPU_SCROLL
    STA PPU_SCROLL
    RTS
.endproc

; Ball-to-player collision: reverse ball dx/dy if ball overlaps player (16x16 AABB)
.proc check_ball_player_collision
  LDX #0
player_loop:
  LDA ball_active, X
  BEQ next_player
  ; Compare X overlap
  LDA ball_x, X
  SEC
  SBC player_x
  CLC
  ADC #8
  CMP #24
  BCS next_player
  ; Compare Y overlap
  LDA ball_y, X
  SEC
  SBC player_y
  CLC
  ADC #8
  CMP #24
  BCS next_player
  ; Collision! Reverse ball dx/dy
  LDA ball_dx, X
  EOR #$FF
  CLC
  ADC #1
  STA ball_dx, X
  LDA ball_dy, X
  EOR #$FF
  CLC
  ADC #1
  STA ball_dy, X
  ; Increment score when ball hits player
  INC score
  JSR draw_score
  JSR play_bounce_sound
next_player:
  INX
  CPX #2
  BNE player_loop
  RTS
.endproc

; Play a bounce sound (for ball collisions)
.proc play_bounce_sound
    LDA #%10011111      ; Duty cycle, envelope (volume=15, constant)
    STA $4000           ; Pulse 1 control
    LDA #$30            ; Timer low (mid pitch)
    STA $4002
    LDA #%10000001      ; Length counter = 1 (short but audible), trigger
    STA $4003
    RTS
.endproc

; Play a random wall bounce sound (for variety)
.proc play_random_wall_bounce_sound
    JSR get_random
    LDA random_num
    AND #$3F         ; Limit to a reasonable pitch range (0-63)
    ORA #$10         ; Avoid too high/low pitch
    STA temp_var     ; Store for use below
    LDA #%10011111   ; Duty cycle, envelope (max volume)
    STA $4000
    LDA temp_var     ; Random pitch
    STA $4002
    LDA #%10000001   ; Length counter = 1, trigger
    STA $4003
    RTS
.endproc

; Main game loop
.proc main
    LDA #$45
    STA random_num
    LDA #(PPUCTRL_ENABLE_NMI | PPUCTRL_BG_TABLE_1000)
    STA PPU_CONTROL
    LDA #(PPUMASK_SHOW_BG | PPUMASK_SHOW_SPRITES | PPUMASK_SHOW_BG_LEFT | PPUMASK_SHOW_SPRITES_LEFT)
    STA PPU_MASK
forever:
    JSR get_random
    wait_for_vblank
    JSR read_controller
    JSR update_player
    JSR update_ball
    JSR update_sprites
    JMP forever
.endproc

; Read controller 1 state
.proc read_controller
  LDA controller_1
  STA controller_1_prev
  LDA #$01
  STA JOYPAD1
  LDA #$00
  STA JOYPAD1
  LDX #$08
read_loop:
   LDA JOYPAD1
   LSR A
   ROL controller_1
   DEX
   BNE read_loop
    RTS
.endproc

; Generate a pseudo-random number (LFSR)
get_random:
    LDA random_num
    ASL
    BCC no_feedback
    EOR #$39
no_feedback:
    STA random_num
    RTS

; Spawn a new ball in an inactive slot
.proc spawn_ball
  LDX #0
find_slot:
  LDA ball_active, X
  BEQ found_slot
  INX
  CPX #2
  BNE find_slot
  RTS
found_slot:
  LDA #1
  STA ball_active, X
  JSR get_random
  AND #$7F
  CLC
  ADC #64
  STA ball_x, X
  JSR get_random
  AND #$3F
  CLC
  ADC #50
  STA ball_y, X
  JSR get_random
  AND #$01
  BEQ neg_dx
  LDA #2
  JMP store_dx
neg_dx:
  LDA #$FE
store_dx:
  STA ball_dx, X
  JSR get_random
  AND #$01
  BEQ neg_dy
  LDA #2
  JMP store_dy
neg_dy:
  LDA #$FE
store_dy:
  STA ball_dy, X
  LDA num_balls
  CMP #8
  BCS skip_inc
  INC num_balls
skip_inc:
  RTS
.endproc

;================ GRAPHICS DATA (CHR-ROM) ================
.segment "CHARS"
  .incbin "assets/tiles.chr"

;================ GAME DATA (ROM) ================
.segment "RODATA"
palette_data:
  .incbin "assets/palette.pal"
nametable_data:
  .incbin "assets/screen.nam"
sprite_data:
.byte 30, 1, 0, 40
.byte 30, 2, 0, 48
.byte 38, 3, 0, 40
.byte 38, 4, 0, 48

hello_txt:
.byte 'A','F','R','O', ' ', 'M', 'A', 'N', 0

;================ STARTUP CODE ================
.segment "STARTUP"

; Reset handler: NES startup and initialization
.proc reset_handler
  SEI
  CLD
  LDX #$40
  STX $4017
  LDX #$FF
  TXS
  LDA #$00
  STA PPU_CONTROL
  STA PPU_MASK
  STA APU_DM_CONTROL
  ; Enable APU pulse channel 1
  LDA #$01
  STA $4015
: BIT PPU_STATUS
  BPL :-
  clear_oam oam
: BIT PPU_STATUS
  BPL :-
  JSR set_palette
  JSR set_nametable
  JSR init_sprites
  JMP main
.endproc
