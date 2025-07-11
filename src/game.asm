.include "nes.inc"
.include "macros.inc"

SPRITE_0_ADDR = oam + 0
SPRITE_1_ADDR = oam + 4
SPRITE_2_ADDR = oam + 8
SPRITE_3_ADDR = oam + 12
SPRITE_BALL_0_ADDR = oam + 16   ; First ball sprite
SPRITE_BALL_1_ADDR = oam + 20   ; Second ball sprite
SPRITE_BALL_2_ADDR = oam + 24   ; Third ball sprite
SPRITE_BALL_3_ADDR = oam + 28   ; Fourth ball sprite
SPRITE_BALL_4_ADDR = oam + 32   ; Fifth ball sprite
SPRITE_BALL_5_ADDR = oam + 36   ; Sixth ball sprite
SPRITE_BALL_6_ADDR = oam + 40   ; Seventh ball sprite
SPRITE_BALL_7_ADDR = oam + 44   ; Eighth ball sprite

; Sprite offset constants for accessing sprite attributes
SPRITE_OFFSET_ATTR = 2     ; Attributes offset

;*****************************************************************
; Define NES cartridge Header
;*****************************************************************
.segment "HEADER"
.byte 'N', 'E', 'S', $1a      ; "NES" followed by MS-DOS EOF marker
.byte $02                     ; 2 x 16KB PRG-ROM banks
.byte $01                     ; 1 x 8KB CHR-ROM bank
.byte $01, $00                ; Mapper 0, no special features

;*****************************************************************
; Define NES interrupt vectors
;*****************************************************************
.segment "VECTORS"
.addr nmi_handler         ; NMI vector ($FFFA-$FFFB)
.addr reset_handler       ; Reset vector ($FFFC-$FFFD)
.addr irq_handler         ; IRQ vector ($FFFE-$FFFF)

;*****************************************************************
; 6502 Zero Page Memory ($0000–$00FF)
;*****************************************************************
.segment "ZEROPAGE"
temp_var:               .res 1
temp_var2:              .res 1
temp_ptr_low:           .res 1
temp_ptr_high:          .res 1
random_num:             .res 1

num_balls:              .res 1
ball_spawn_timer:       .res 1
max_balls:              .res 1

ball_x:                 .res 8
ball_y:                 .res 8
ball_dx:                .res 8
ball_dy:                .res 8
ball_active:            .res 8

                        .res 11

controller_1:           .res 1
controller_2:           .res 1
controller_1_prev:      .res 1
controller_2_prev:      .res 1
controller_1_pressed:   .res 1
controller_1_released:  .res 1

                        .res 10

game_state:             .res 1
player_x:               .res 1
player_y:               .res 1
player_vel_x:           .res 1
player_vel_y:           .res 1
score:                  .res 1
scroll:                 .res 1
time:                   .res 1
seconds:                .res 1
                        .res 07

;*****************************************************************
; OAM (Object Attribute Memory) ($0200–$02FF)
;*****************************************************************
.segment "OAM"
oam: .res 256

;*****************************************************************
; Code Segment (ROM)
;*****************************************************************
.segment "CODE"

.proc irq_handler
  PHA
  TXA
  PHA
  TYA
  PHA

  INC time

  PLA
  TAY
  PLA
  TAX
  PLA

  RTI
.endproc

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

    LDA PPU_STATUS
    LDA #$20
    STA PPU_ADDRESS
    LDA #$8A
    STA PPU_ADDRESS

    LDX #$0
    textloop:
    LDA hello_txt, X
    STA PPU_VRAM_IO
    INX
    CMP #0
    BEQ :+
    JMP textloop
  :

  LDA #$00
  STA PPU_SCROLL
  STA PPU_SCROLL

  RTS
.endproc

.proc init_sprites
  ; Initialize player sprites
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
  LDA #8
  STA max_balls

  ; Clear all ball slots
  LDX #0
clear_balls:
  LDA #0
  STA ball_active, X
  INX
  CPX #8
  BNE clear_balls

  ; Initialize all ball sprites to be hidden
  LDX #0
init_ball_sprites:
  ; Calculate sprite address for this ball
  TXA
  ASL
  ASL
  CLC
  ADC #<SPRITE_BALL_0_ADDR
  STA temp_ptr_low
  LDA #>SPRITE_BALL_0_ADDR
  ADC #0
  STA temp_ptr_high

  ; Set Y position off-screen
  LDY #SPRITE_OFFSET_Y
  LDA #$FF
  STA (temp_ptr_low), Y

  ; Set tile
  LDY #SPRITE_OFFSET_TILE
  LDA #5
  STA (temp_ptr_low), Y

  ; Set attributes
  LDY #SPRITE_OFFSET_ATTR
  LDA #0
  STA (temp_ptr_low), Y

  ; Set X position
  LDY #SPRITE_OFFSET_X
  LDA #0
  STA (temp_ptr_low), Y

  INX
  CPX #8
  BNE init_ball_sprites

  LDA #128
  STA player_x
  LDA #170
  STA player_y

  ; Spawn first ball
  JSR spawn_ball

  RTS
.endproc

.proc update_sprites
  ; Update player sprites
  LDA player_x
  STA SPRITE_0_ADDR + SPRITE_OFFSET_X
  STA SPRITE_2_ADDR + SPRITE_OFFSET_X
  CLC
  ADC #8
  STA SPRITE_1_ADDR + SPRITE_OFFSET_X
  STA SPRITE_3_ADDR + SPRITE_OFFSET_X

  LDA player_y
  STA SPRITE_0_ADDR + SPRITE_OFFSET_Y
  STA SPRITE_1_ADDR + SPRITE_OFFSET_Y
  CLC
  ADC #8
  STA SPRITE_2_ADDR + SPRITE_OFFSET_Y
  STA SPRITE_3_ADDR + SPRITE_OFFSET_Y

  ; Update all ball sprites
  LDX #0
update_ball_sprites:
  LDA ball_active, X
  BEQ hide_ball

  ; Calculate sprite address for this ball
  TXA
  ASL
  ASL
  CLC
  ADC #<SPRITE_BALL_0_ADDR
  STA temp_ptr_low
  LDA #>SPRITE_BALL_0_ADDR
  ADC #0
  STA temp_ptr_high

  ; Set Y position
  LDY #SPRITE_OFFSET_Y
  LDA ball_y, X
  STA (temp_ptr_low), Y

  ; Set X position
  LDY #SPRITE_OFFSET_X
  LDA ball_x, X
  STA (temp_ptr_low), Y

  ; Set tile
  LDY #SPRITE_OFFSET_TILE
  LDA #5
  STA (temp_ptr_low), Y

  ; Set attributes
  LDY #SPRITE_OFFSET_ATTR
  LDA #0
  STA (temp_ptr_low), Y

  JMP next_sprite

hide_ball:
  ; Hide sprite by moving it off-screen
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
  CPX #8
  BNE update_ball_sprites

  ; Set sprite attributes for player
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

.proc update_ball
  ; Check spawn timer
  INC ball_spawn_timer
  LDA ball_spawn_timer
  CMP #180
  BNE no_spawn

  LDA #0
  STA ball_spawn_timer

  ; Only spawn if we haven't reached max balls
  LDA num_balls
  CMP max_balls
  BCS no_spawn

  JSR spawn_ball

no_spawn:
  ; Update all active balls
  LDX #0
update_loop:
  LDA ball_active, X
  BEQ next_ball

  ; Update Y position
  LDA ball_y, X
  CLC
  ADC ball_dy, X
  STA ball_y, X

  ; Check Y boundaries
  CMP #20
  BCC bounce_top
  CMP #210
  BCS bounce_bottom
  JMP check_x

bounce_top:
  LDA #1
  STA ball_dy, X
  JMP check_x

bounce_bottom:
  LDA #$FF
  STA ball_dy, X

check_x:
  ; Update X position
  LDA ball_x, X
  CLC
  ADC ball_dx, X
  STA ball_x, X

  ; Check X boundaries
  CMP #8
  BCC bounce_left
  CMP #248
  BCS bounce_right
  JMP next_ball

bounce_left:
  LDA #1
  STA ball_dx, X
  JMP next_ball

bounce_right:
  LDA #$FF
  STA ball_dx, X

next_ball:
  INX
  CPX #8
  BNE update_loop

  RTS
.endproc

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

get_random:
    LDA random_num
    ASL
    BCC no_feedback
    EOR #$39
no_feedback:
    STA random_num
    RTS

.proc spawn_ball
  ; Find first inactive ball slot
  LDX #0
find_slot:
  LDA ball_active, X
  BEQ found_slot
  INX
  CPX #8
  BNE find_slot
  RTS

found_slot:
  ; Activate this ball
  LDA #1
  STA ball_active, X

  ; Set random position
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

  ; Set random velocity
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

  INC num_balls
  RTS
.endproc

;*****************************************************************
; Character ROM data (graphics patterns)
;*****************************************************************
.segment "CHARS"
  .incbin "assets/tiles.chr"

;*****************************************************************
; Character ROM data (graphics patterns)
;*****************************************************************
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

.segment "STARTUP"

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

:
  BIT PPU_STATUS
  BPL :-

  clear_oam oam

:
  BIT PPU_STATUS
  BPL :-

  JSR set_palette
  JSR set_nametable
  JSR init_sprites

  JMP main
.endproc
