# Before the start of Milestone 3, we need to create a board to show the "frozen" gems
# As before we don't record what the old gems look like
#
# Hence we need to consistently upadate the state of gems
# 
# The 2D board [row][col] is in the memory. 
# If the cell is 0, it is empty. If the cell
# is with a color, it it a "frozen" cells
# index = row * GRID_WIDTH + col, each entry is 4 bytes (one word)
# 
# When a column stops moving due to lower gems or grid boundary,
# store the col into the board
# Then the board needs to be updated by match_detection
# and hence unsupport_down. This gonna form a loop called update_board
#
# 
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       8
# - Unit height in pixels:      8
# - Display width in pixels:    256
# - Display height in pixels:   256
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################

    .data
##############################################################################
# Immutable Data
##############################################################################
# The address of the bitmap display. 
ADDR_DSPL:      .word 0x10008000
# The address of the keyboard. 
ADDR_KBRD:      .word 0xffff0000
    
# Logical grid size for the playing field
GRID_WIDTH:     .word 6            # Set it within 32 * 32 is nice 
GRID_HEIGHT:    .word 13            # Also the logical height and width
    
# Physical bitmap layout (units per row)
DISP_UNITS_W:   .word 32            # = display_width / unit_width = 256 / 8

# where the grid (including frame) is placed inside the 32x32 bitmap
GRID_ORIGIN_ROW: .word 2            # vertical offset (top margin)
GRID_ORIGIN_COL: .word 2            # horizontal offset (left margin)

# Background and frame colors
COLOR_BG:       .word 0x00000000      # black interior
COLOR_FRAME:    .word 0x00c0c0c0      # grey frame (one cell border)

# Table of gem colors for random selection
COLOR_TABLE:
        .word 0x00ff0000        # red
        .word 0x00ff8000        # orange
        .word 0x00ffff00        # yellow
        .word 0x0000ff00        # green
        .word 0x000000ff        # blue
        .word 0x008000ff        # purple

##############################################################################
# Mutable Data (related to game states)
##############################################################################
# Current falling column state 
cur_col_x:      .word 0           # logical column index (0..GRID_WIDTH-1)
cur_col_y:      .word 0           # logical row index of TOP gem
cur_gem0:       .word 0           # color of top gem
cur_gem1:       .word 0           # color of middle gem
cur_gem2:       .word 0           # color of bottom gem

# For "Frozen" gem, store past gems in mem
BOARD:          .space 4096              # 32 * 32 (cells) * 4 (bytes)
#
# Board for match_detection
MARK:           .space 4096
##############################################################################
# Code
##############################################################################
	.text
	.globl main
	
main:
    # Initialize the game
    jal  draw_background
    jal  board_clear
    jal  init_first_column
    jal  draw_column

game_loop:
    # 1a. Check if key has been pressed
    # 1b. Check which key has been pressed
    # 2a. Check for collisions
	# 2b. Update locations (capsules)
	# 3. Draw the screen
	# 4. Sleep
    # 5. Go back to Step 1

    # 1) Connect to keyboard.
    #   "If" branches to check if the key is w,a,s,d...
    jal  check_key                      # Connect Keyboard
    move $t0, $v0                       # t0 = key (0 if none)

    beq  $t0, $zero, after_input        # no key this frame
    li   $t1, 'q'
    beq  $t0, $t1, quit_game
    li   $t1, 'a'
    beq  $t0, $t1, handle_x_left
    li   $t1, 'd'
    beq  $t0, $t1, handle_x_right
    li   $t1, 's'
    beq  $t0, $t1, handle_down
    li   $t1, 'w'
    beq  $t0, $t1, handle_shuffel
    j    after_input                    # any other key: ignore

handle_x_left:
    # current x
    la   $t2, cur_col_x
    lw   $t3, 0($t2)          # t3 = x

    # new_x = x - 1
    addi $t4, $t3, -1         # t4 = new_x

    # if new_x < 0, cannot move due to grid boundary
    bltz $t4, keep_x_left

    # GRID_WIDTH 
    la   $t0, GRID_WIDTH
    lw   $t5, 0($t0)          # t5 = W

    # current y (top of column)
    la   $t0, cur_col_y
    lw   $t6, 0($t0)          # t6 = y

    addi $t8, $zero, 0        # i = 0 (measured in row)
hl_row_loop:
    bge  $t8, 3, hl_no_collision     # checked i=0,1,2 → no collision found

    # row = y + i
    add  $t9, $t6, $t8

    # index = row * W + new_x
    mul  $t1, $t9, $t5
    add  $t1, $t1, $t4
    sll  $t1, $t1, 2            # offsetBytes * 4

    la   $t0, BOARD
    add  $t0, $t0, $t1          # find absolute address in mem
    lw   $t1, 0($t0)            # BOARD[row][new_x]

    # if non-zero, collision → cannot move
    bne  $t1, $zero, keep_x_left

hl_next_row:
    addi $t8, $t8, 1          # i++
    j    hl_row_loop

hl_no_collision:
    # we passed all three rows with no collision → accept new_x
    sw   $t4, 0($t2)          # cur_col_x = new_x

keep_x_left:
    j    after_input

handle_x_right:
    # load current x
    la   $t2, cur_col_x
    lw   $t3, 0($t2)          # t3 = x

    # load GRID_WIDTH to compute max_x
    la   $t0, GRID_WIDTH
    lw   $t5, 0($t0)          # t5 = W

    # compute new_x = x + 1
    addi $t4, $t3, 1          # t4 = new_x

    # max_x = W - 1
    addi $t1, $t5, -1

    # if new_x > max_x, cannot move due to grid boundary
    bgt  $t4, $t1, keep_x_right

    # load current y (top of column)
    la   $t0, cur_col_y
    lw   $t6, 0($t0)          # t6 = y

    addi $t8, $zero, 0        # i = 0
hr_row_loop:
    bge  $t8, 3, hr_no_collision     # checked 3 gems of the col and no collision
    # row = y + i
    add  $t9, $t6, $t8

    # index = row * W + new_x
    mul  $t1, $t9, $t5        # row * W
    add  $t1, $t1, $t4        # + new_x
    sll  $t1, $t1, 2          # * 4 for offset

    la   $t0, BOARD
    add  $t0, $t0, $t1
    lw   $t1, 0($t0)          # BOARD[row][new_x]

    # if non-zero, collision → cannot move
    bne  $t1, $zero, keep_x_right

hr_next_row:
    addi $t8, $t8, 1          # i++
    j    hr_row_loop

hr_no_collision:
    # all three rows are empty at new_x → accept move
    sw   $t4, 0($t2)          # cur_col_x = new_x

keep_x_right:
    j    after_input

handle_down:
    # check if the column can move down
    jal  can_move_down
    beq  $v0, $zero, hd_cmd   # if v0 == 0, it has landed

    # case 1: can move down → just increment cur_col_y 
    la   $t2, cur_col_y
    lw   $t3, 0($t2)
    addi $t3, $t3, 1          # y = y + 1
    sw   $t3, 0($t2)
    j    after_input

hd_cmd:
    # case 2: cannot move down → freeze column and spawn a new one 
    jal  freeze_column_into_board     # write the 3 gems into BOARD
    jal  update_board                 # resolve matches + gravity
    jal  init_first_column            # spawn a new falling column at the top
    j    after_input

handle_shuffel:
    la   $t2, cur_gem0
    lw   $t3, 0($t2)        # t3 = gem0

    la   $t4, cur_gem1
    lw   $t5, 0($t4)        # t5 = gem1

    la   $t6, cur_gem2
    lw   $t7, 0($t6)        # t7 = gem2

    # order: gem2 -> gem0, gem0 -> gem1, gem1 -> gem2
    sw   $t7, 0($t2)        # cur_gem0 = old gem2
    sw   $t3, 0($t4)        # cur_gem1 = old gem0
    sw   $t5, 0($t6)        # cur_gem2 = old gem1

    j    after_input

################ after handling input: redraw(continue) or sleep ######################
after_input:
    # 2) redraw whole scene: background + column
    jal  draw_background
    jal  draw_board         # draw the forzen gems
    jal  draw_column        # draw the current falling column

    # 3) sleep 16 ms for 60 FPS (syscall 32)
    li   $v0, 32           # sleep for a given number of milliseconds
    li   $a0, 16           # 16 milliseconds
    syscall

    # 4) loop
    j    game_loop

quit_game:
    li   $v0, 10           # exit
    syscall
      
######################## draw_background #####################################
# interior and frame
##############################################################################
draw_background:
    # save return address because we make jal calls inside, so stack is needed
    addi $sp, $sp, -4            # move stack pointer down 4 bytes
    sw   $ra, 0($sp)             # store $ra on stack

    # 1. Interior fill (logical 0..H-1, 0..W-1, using draw_cell) ####
    la   $t0, GRID_HEIGHT
    lw   $s2, 0($t0)            # H
    la   $t0, GRID_WIDTH
    lw   $s3, 0($t0)            # W

    addi $s0, $zero, 0          # row = 0
int_row_loop:
    bge  $s0, $s2, after_interior

    addi $s1, $zero, 0        # col = 0
int_col_loop:
    bge  $s1, $s3, next_int_row

    la   $t1, COLOR_BG
    lw   $a2, 0($t1)
    move $a0, $s0             # logical row
    move $a1, $s1             # logical col
    jal  draw_cell

    addi $s1, $s1, 1
    j    int_col_loop

next_int_row:
    addi $s0, $s0, 1
    j    int_row_loop

after_interior:
    # 2. Frame around the interior using physical coords ####
    # Load origin and size
    la   $t0, GRID_ORIGIN_ROW
    lw   $t0, 0($t0)          # OR (Origin row)
    la   $t1, GRID_ORIGIN_COL
    lw   $t1, 0($t1)          # OC (Origin col)
    la   $t2, GRID_HEIGHT
    lw   $t2, 0($t2)          # H
    la   $t3, GRID_WIDTH
    lw   $t3, 0($t3)          # W

    # frame positions
    move $t4, $t0             # frame_top    = OR
    add  $t5, $t0, $t2
    addi $t5, $t5, 1          # frame_bottom = OR + H + 1
    move $t6, $t1             # frame_left   = OC
    add  $t7, $t1, $t3
    addi $t7, $t7, 1          # frame_right  = OC + W + 1

    # load frame color
    la   $t8, COLOR_FRAME
    lw   $t8, 0($t8)

    # top row 
    move $t9, $t6             # col = frame_left
top_row_loop:
    bgt  $t9, $t7, after_top
    move $a0, $t4             # row = frame_top
    move $a1, $t9
    move $a2, $t8
    jal  draw_cell_raw
    addi $t9, $t9, 1
    j    top_row_loop
after_top:

    # bottom row
    move $t9, $t6             # col = frame_left
bottom_row_loop:
    bgt  $t9, $t7, after_bottom
    move $a0, $t5             # row = frame_bottom
    move $a1, $t9
    move $a2, $t8
    jal  draw_cell_raw
    addi $t9, $t9, 1
    j    bottom_row_loop
after_bottom:

    # left column
    move $t9, $t4             # row = frame_top
left_col_loop:
    bgt  $t9, $t5, after_left
    move $a0, $t9
    move $a1, $t6             # col = frame_left
    move $a2, $t8
    jal  draw_cell_raw
    addi $t9, $t9, 1
    j    left_col_loop
after_left:

    # right column 
    move $t9, $t4             # row = frame_top
right_col_loop:
    bgt  $t9, $t5, after_right
    move $a0, $t9
    move $a1, $t7             # col = frame_right
    move $a2, $t8
    jal  draw_cell_raw
    addi $t9, $t9, 1
    j    right_col_loop
after_right:

    # restore return address
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

######################## draw_cell_raw(row, col, color) #####################
# a0 = physical row, a1 = physical col, a2 = color
##############################################################################
draw_cell_raw:
    # stride = DISP_UNITS_W
    la   $t0, DISP_UNITS_W
    lw   $t0, 0($t0)          # t0 = 32

    # index = row * stride + col
    mul  $t1, $a0, $t0
    add  $t1, $t1, $a1

    # offsetBytes = index * 4
    sll  $t1, $t1, 2

    # address = ADDR_DSPL + offsetBytes
    la   $t2, ADDR_DSPL
    lw   $t2, 0($t2)
    add  $t2, $t2, $t1

    sw   $a2, 0($t2)
    jr   $ra
    
######################## draw_cell(row, col, color) #########################
# a0 = logical interior row    (0..GRID_HEIGHT-1)
# a1 = logical interior col    (0..GRID_WIDTH-1)
# a2 = color
# Draws at physical (GRID_ORIGIN_ROW+1+row, GRID_ORIGIN_COL+1+col)
##############################################################################
draw_cell:
    # apply origin + 1 cell border
    la   $t3, GRID_ORIGIN_ROW
    lw   $t3, 0($t3)
    addi $t3, $t3, 1          # OR + 1
    add  $a0, $a0, $t3        # physical row

    la   $t4, GRID_ORIGIN_COL
    lw   $t4, 0($t4)
    addi $t4, $t4, 1          # OC + 1
    add  $a1, $a1, $t4        # physical col

    # stride = DISP_UNITS_W
    la   $t0, DISP_UNITS_W
    lw   $t0, 0($t0)          # t0 = 32

    # index = row * stride + col
    mul  $t1, $a0, $t0
    add  $t1, $t1, $a1

    # offsetBytes = index * 4
    sll  $t1, $t1, 2

    # address = ADDR_DSPL + offsetBytes
    la   $t2, ADDR_DSPL
    lw   $t2, 0($t2)
    add  $t2, $t2, $t1

    sw   $a2, 0($t2)
    jr   $ra


######################## init_first_column ###################################
# Set the color of gems randomly, just color
##############################################################################
init_first_column:
    # cur_col_x = GRID_WIDTH / 2 (centre
    la   $t0, GRID_WIDTH
    lw   $t1, 0($t0)
    sra  $t1, $t1, 1            # divide by 2
    la   $t0, cur_col_x
    sw   $t1, 0($t0)            # cur_col_x = grid_width / 2

    la   $t0, cur_col_y         # Find the address
    sw   $zero, 0($t0)          # cur_col_y = 0 

    # cur_gem0 color
    li   $v0, 42                # random int syscall
    li   $a0, 0           
    li   $a1, 6                 # max (exclusive): 0..5
    syscall                     # random index in a0

    move $t2, $a0               # t2 = index
    la   $t3, COLOR_TABLE
    sll  $t4, $t2, 2            # index * 4, convert to byte
    add  $t3, $t3, $t4          # the address of color we select
    lw   $t5, 0($t3)            # t5 = COLOR_TABLE[index]

    la   $t0, cur_gem0
    sw   $t5, 0($t0)

    # cur_gem1 color
    li   $v0, 42
    li   $a0, 0
    li   $a1, 6
    syscall                     # Similar as above

    move $t2, $a0
    la   $t3, COLOR_TABLE
    sll  $t4, $t2, 2
    add  $t3, $t3, $t4
    lw   $t5, 0($t3)

    la   $t0, cur_gem1
    sw   $t5, 0($t0)

    # cur_gem2 color
    li   $v0, 42
    li   $a0, 0
    li   $a1, 6
    syscall                     # Similar as above

    move $t2, $a0
    la   $t3, COLOR_TABLE
    sll  $t4, $t2, 2
    add  $t3, $t3, $t4
    lw   $t5, 0($t3)

    la   $t0, cur_gem2
    sw   $t5, 0($t0)

    jr   $ra


######################## draw_column #########################################
# After getting the color, we draw the col gems at
# (cur_col_x, cur_col_y),(cur_col_x, cur_col_y + 1),(cur_col_x, cur_col_y + 2)
##############################################################################
draw_column:
    # save return address because we will call draw_cell (jal) inside
    addi $sp, $sp, -4
    sw   $ra, 0($sp)

    # load x, y into saved registers so they survive jal
    la   $t0, cur_col_x
    lw   $s2, 0($t0)        # s2 = x
    la   $t0, cur_col_y
    lw   $s3, 0($t0)        # s3 = y

    # top gem
    move $a0, $s3           # row = y
    move $a1, $s2           # col = x
    la   $t2, cur_gem0
    lw   $a2, 0($t2)        # read the color stored when initialization
    jal  draw_cell

    # middle gem
    addi $a0, $s3, 1       # row = y + 1
    move $a1, $s2          # col = x
    la   $t2, cur_gem1
    lw   $a2, 0($t2)
    jal  draw_cell

    # bottom gem
    addi $a0, $s3, 2       # row = y + 2
    move $a1, $s2          # col = x
    la   $t2, cur_gem2
    lw   $a2, 0($t2)
    jal  draw_cell

    # restore ra and return to caller 
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra
    
######################## check_key ###########################################
# Returns:
#   v0 = 0              if no key pressed 
#   v0 = ASCII letter   if a key was pressed (e.g. 'w', 'a', 's', 'd', 'q')
##############################################################################
check_key:
    # load keyboard base address
    la   $t0, ADDR_KBRD
    lw   $t0, 0($t0)          # t0 = 0xffff0000

    # check "key ready" flag at 0xffff0000
    lw   $t1, 0($t0)          # t1 = 1 if key pressed, else 0
    beq  $t1, $zero, no_key   # if 0, nothing new

    # a key was pressed: read key ASCII code in 4 bytes after, refer to handout
    lw   $t2, 4($t0)          # t2 = ASCII code
    move $v0, $t2
    jr   $ra

no_key:
    move $v0, $zero
    jr   $ra
    
######################## board_clear #########################################
# Set all logical cells in BOARD to 0 (empty)
# Uses logical dimensions GRID_HEIGHT x GRID_WIDTH
##############################################################################
board_clear:
    # t0 = GRID_HEIGHT (H)
    la   $t0, GRID_HEIGHT
    lw   $t1, 0($t0)          # t1 = H

    # t2 = GRID_WIDTH (W)
    la   $t0, GRID_WIDTH
    lw   $t2, 0($t0)          # t2 = W

    addi $t3, $zero, 0        # t3 = row = 0
bc_row_loop:
    bge  $t3, $t1, bc_done    # if row >= H, done

    addi $t4, $zero, 0        # t4 = col = 0
bc_col_loop:
    bge  $t4, $t2, bc_next_row    # if col >= W, next row

    # index = row * W + col
    mul  $t5, $t3, $t2        # t5 = row * W
    add  $t5, $t5, $t4        # t5 = row * W + col

    # offsetBytes = index * 4
    sll  $t5, $t5, 2          # t5 = index * 4

    # address = BOARD + offsetBytes
    la   $t6, BOARD
    add  $t6, $t6, $t5

    sw   $zero, 0($t6)        # BOARD[row][col] = 0

    addi $t4, $t4, 1          # col++
    j    bc_col_loop

bc_next_row:
    addi $t3, $t3, 1          # row++
    j    bc_row_loop

bc_done:
    jr   $ra
    
######################## mark_clear ##########################################
# Set all MARK[r][c] = 0 for logical grid H×W
##############################################################################
mark_clear:
    # t1 = H
    la   $t0, GRID_HEIGHT
    lw   $t1, 0($t0)

    # t2 = W
    la   $t0, GRID_WIDTH
    lw   $t2, 0($t0)

    addi $t3, $zero, 0        # row = 0
mc_row_loop:
    bge  $t3, $t1, mc_done    # if row >= H, finish

    addi $t4, $zero, 0        # col = 0
mc_col_loop:
    bge  $t4, $t2, mc_next_row

    # index = row * W + col
    mul  $t5, $t3, $t2
    add  $t5, $t5, $t4
    sll  $t5, $t5, 2          # index * 4

    la   $t6, MARK
    add  $t6, $t6, $t5        # &MARK[row][col]
    sw   $zero, 0($t6)        # MARK[row][col] = 0

    addi $t4, $t4, 1          # col++
    j    mc_col_loop

mc_next_row:
    addi $t3, $t3, 1          # row++
    j    mc_row_loop

mc_done:
    jr   $ra

######################## draw_board ##########################################
# Draw the board (with no matching detecion)
# For each logical cell (r,c) in BOARD:
#   if BOARD[r][c] != 0, draw that gem using draw_cell(r, c, colour).
##############################################################################
draw_board:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)

    # load H and W
    la   $t0, GRID_HEIGHT
    lw   $s2, 0($t0)         # s2 = H
    la   $t0, GRID_WIDTH
    lw   $s3, 0($t0)         # s3 = W

    addi $s0, $zero, 0       # row = 0
db_row_loop:
    bge  $s0, $s2, db_done   # if row >= H, finish

    addi $s1, $zero, 0       # col = 0
db_col_loop:
    bge  $s1, $s3, db_next_row   # if col >= W, next row

    # index = row * W + col
    mul  $t1, $s0, $s3
    add  $t1, $t1, $s1

    sll  $t1, $t1, 2         # offsetBytes = index * 4

    la   $t2, BOARD
    add  $t2, $t2, $t1       # t2 = &BOARD[row][col]
    lw   $t3, 0($t2)         # t3 = BOARD[row][col] (color or 0)

    beq  $t3, $zero, db_skip_draw   # if empty, skip

    # draw this frozen gem
    move $a0, $s0            # logical row
    move $a1, $s1            # logical col
    move $a2, $t3            # colour
    jal  draw_cell

db_skip_draw:
    addi $s1, $s1, 1
    j    db_col_loop

db_next_row:
    addi $s0, $s0, 1
    j    db_row_loop

db_done:
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra
    
######################## can_move_down ####################################
# Returns:
#   v0 = 1  column can move down
#   v0 = 0  otherwise 
###########################################################################
can_move_down:
    la   $t0, cur_col_y         # load current y (top of column)
    lw   $t1, 0($t0)            # t1 = y

    la   $t0, GRID_HEIGHT       # load current y (top of column)
    lw   $t2, 0($t0)            # t2 = H

    addi $t3, $t1, 3            # t3 = y + 3, cell below bottom gem

    # if y_below >= H, cannot move down
    bge  $t3, $t2, cmd_cannot

    # load current x
    la   $t0, cur_col_x
    lw   $t4, 0($t0)            # t4 = x

    # load GRID_WIDTH (for board indexing)
    la   $t0, GRID_WIDTH
    lw   $t5, 0($t0)            # t5 = W

    # index = y_below * W + x
    mul  $t6, $t3, $t5          # t6 = (y+3) * W
    add  $t6, $t6, $t4          # t6 = (y+3) * W + x

    # offsetBytes = index * 4
    sll  $t6, $t6, 2            # the address of gem below the col

    # address = BOARD + offsetBytes
    la   $t0, BOARD
    add  $t0, $t0, $t6

    # read data stored respect with the lower gem from board
    lw   $t7, 0($t0)

    # if non-zero, has color, frozen gem, cannot move
    bne  $t7, $zero, cmd_cannot

    # otherwise, can move down
    li   $v0, 1
    jr   $ra

cmd_cannot:
    li   $v0, 0
    jr   $ra
    
######################## freeze_column_into_board #########################
# Writes the current falling column into BOARD
###########################################################################
freeze_column_into_board:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)

    # load W (GRID_WIDTH)
    la   $t0, GRID_WIDTH
    lw   $t5, 0($t0)          # t5 = W, to calculate index (in cell)

    # load x and y
    la   $t0, cur_col_x
    lw   $t4, 0($t0)          # t4 = x
    la   $t0, cur_col_y
    lw   $t1, 0($t0)          # t1 = y (top row)

    # top gem at (y, x) 
    move $t2, $t1             # row = y
    la   $t0, cur_gem0
    lw   $t3, 0($t0)          # colour = cur_gem0

    # index = row * W + x
    mul  $t6, $t2, $t5
    add  $t6, $t6, $t4
    sll  $t6, $t6, 2          # offsetBytes = index * 4

    la   $t0, BOARD
    add  $t0, $t0, $t6
    sw   $t3, 0($t0)          # BOARD[y][x] = cur_gem0

    # middle gem at (y + 1, x) 
    addi $t2, $t1, 1          # row = y + 1
    la   $t0, cur_gem1
    lw   $t3, 0($t0)          # colour = cur_gem1

    mul  $t6, $t2, $t5
    add  $t6, $t6, $t4
    sll  $t6, $t6, 2

    la   $t0, BOARD
    add  $t0, $t0, $t6
    sw   $t3, 0($t0)          # BOARD[y+1][x] = cur_gem1

    # bottom gem at (y + 2, x) 
    addi $t2, $t1, 2          # row = y + 2
    la   $t0, cur_gem2
    lw   $t3, 0($t0)          # colour = cur_gem2

    mul  $t6, $t2, $t5
    add  $t6, $t6, $t4
    sll  $t6, $t6, 2

    la   $t0, BOARD
    add  $t0, $t0, $t6
    sw   $t3, 0($t0)          # BOARD[y+2][x] = cur_gem2

    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra
    
#################### update_board #######################################
# Include the board loop (refer to Checkpoint)
# Other helpers
#########################################################################
update_board:
    # PROLOGUE: save return address because we call other functions
    addi $sp, $sp, -4
    sw   $ra, 0($sp)

    jal  match_detection
    jal  delete_marked_cells
    jal  unsupport_down

    # EPILOGUE: restore $ra and return to caller (hd_cmd)
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra


################### match_detection #####################################
# mark the matching value in the MARKå
# starting cell for each iteration: start
# the scanned cell along each line: candidate cells
match_detection:
    # PROLOGUE: save $ra because we call mark_clear
    addi $sp, $sp, -4
    sw   $ra, 0($sp)

    # 0) clear MARK for this pass
    jal  mark_clear

    # load H and W
    la   $t0, GRID_HEIGHT
    lw   $t8, 0($t0)            # t8 = H
    la   $t0, GRID_WIDTH
    lw   $t9, 0($t0)            # t9 = W

    # row loop: t0 = row
    addi $t0, $zero, 0
md_row_loop:
    bge  $t0, $t8, md_done      # if row >= H → done

    # col loop: t1 = col
    addi $t1, $zero, 0
md_col_loop:
    bge  $t1, $t9, md_next_row  # if col >= W → next row

    ####################################################################
    # Load BOARD[row][col] as starting colour (t4)
    ####################################################################
    # index0 = row * W + col
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2            # index0 * 4 bytes

    la   $t3, BOARD
    add  $t3, $t3, $t2          # &BOARD[row][col]
    lw   $t4, 0($t3)            # t4 = colour

    beq  $t4, $zero, md_next_cell   # empty cell: nothing to match

    ####################################################################
    # 1) HORIZONTAL: (row,col), (row,col+1), (row,col+2)
    ####################################################################
    # require col+2 < W
    addi $t5, $t1, 2
    bge  $t5, $t9, md_check_vertical

    # candidate 1 at (row, col+1)
    addi $t6, $t1, 1           # c1 = col+1
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t6         # row*W + c1
    sll  $t2, $t2, 2
    la   $t3, BOARD
    add  $t3, $t3, $t2
    lw   $t7, 0($t3)           # BOARD[row][col+1]
    bne  $t7, $t4, md_check_vertical

    # candidate 2 at (row, col+2)
    addi $t6, $t1, 2           # c2 = col+2
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t6
    sll  $t2, $t2, 2
    la   $t3, BOARD
    add  $t3, $t3, $t2
    lw   $t7, 0($t3)           # BOARD[row][col+2]
    bne  $t7, $t4, md_check_vertical

    # mark three horizontally in MARK
    # (row,col)
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t6, 1
    sw   $t6, 0($t3)

    # (row,col+1)
    addi $t6, $t1, 1
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t6
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t7, 1
    sw   $t7, 0($t3)

    # (row,col+2)
    addi $t6, $t1, 2
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t6
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t7, 1
    sw   $t7, 0($t3)

md_check_vertical:
    ####################################################################
    # 2) VERTICAL: (row,col), (row+1,col), (row+2,col)
    ####################################################################
    # require row+2 < H
    addi $t5, $t0, 2
    bge  $t5, $t8, md_check_diag1

    # candidate 1 at (row+1, col)
    addi $t6, $t0, 1           # r1 = row+1
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t1         # r1*W + col
    sll  $t2, $t2, 2
    la   $t3, BOARD
    add  $t3, $t3, $t2
    lw   $t7, 0($t3)           # BOARD[row+1][col]
    bne  $t7, $t4, md_check_diag1

    # candidate 2 at (row+2, col)
    addi $t6, $t0, 2           # r2 = row+2
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t1         # r2*W + col
    sll  $t2, $t2, 2
    la   $t3, BOARD
    add  $t3, $t3, $t2
    lw   $t7, 0($t3)           # BOARD[row+2][col]
    bne  $t7, $t4, md_check_diag1

    # mark three vertically
    # (row,col)
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t6, 1
    sw   $t6, 0($t3)

    # (row+1,col)
    addi $t6, $t0, 1
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t7, 1
    sw   $t7, 0($t3)

    # (row+2,col)
    addi $t6, $t0, 2
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t7, 1
    sw   $t7, 0($t3)

md_check_diag1:
    ####################################################################
    # 3) DIAGONAL down-right: (row,col),(row+1,col+1),(row+2,col+2)
    ####################################################################
    # bounds: row+2 < H, col+2 < W
    addi $t5, $t0, 2
    addi $t6, $t1, 2
    bge  $t5, $t8, md_check_diag2
    bge  $t6, $t9, md_check_diag2

    # (row+1, col+1)
    addi $t6, $t0, 1       # r1
    addi $t7, $t1, 1       # c1
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t7
    sll  $t2, $t2, 2
    la   $t3, BOARD
    add  $t3, $t3, $t2
    lw   $t5, 0($t3)
    bne  $t5, $t4, md_check_diag2

    # (row+2, col+2)
    addi $t6, $t0, 2       # r2
    addi $t7, $t1, 2       # c2
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t7
    sll  $t2, $t2, 2
    la   $t3, BOARD
    add  $t3, $t3, $t2
    lw   $t5, 0($t3)
    bne  $t5, $t4, md_check_diag2

    # mark three diagonal down-right
    # (row,col)
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t6, 1
    sw   $t6, 0($t3)

    # (row+1,col+1)
    addi $t6, $t0, 1
    addi $t7, $t1, 1
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t7
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t6, 1
    sw   $t6, 0($t3)

    # (row+2,col+2)
    addi $t6, $t0, 2
    addi $t7, $t1, 2
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t7
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t6, 1
    sw   $t6, 0($t3)

md_check_diag2:
    ####################################################################
    # 4) DIAGONAL down-left: (row,col),(row+1,col-1),(row+2,col-2)
    ####################################################################
    # bounds: row+2 < H and col-2 >= 0
    addi $t5, $t0, 2           # row+2
    addi $t6, $t1, -2          # col-2
    bge  $t5, $t8, md_next_cell
    bltz $t6, md_next_cell

    # (row+1, col-1)
    addi $t6, $t0, 1
    addi $t7, $t1, -1
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t7
    sll  $t2, $t2, 2
    la   $t3, BOARD
    add  $t3, $t3, $t2
    lw   $t5, 0($t3)
    bne  $t5, $t4, md_next_cell

    # (row+2, col-2)
    addi $t6, $t0, 2
    addi $t7, $t1, -2
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t7
    sll  $t2, $t2, 2
    la   $t3, BOARD
    add  $t3, $t3, $t2
    lw   $t5, 0($t3)
    bne  $t5, $t4, md_next_cell

    # mark three diagonal down-left
    # (row,col)
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t6, 1
    sw   $t6, 0($t3)

    # (row+1,col-1)
    addi $t6, $t0, 1
    addi $t7, $t1, -1
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t7
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t6, 1
    sw   $t6, 0($t3)

    # (row+2,col-2)
    addi $t6, $t0, 2
    addi $t7, $t1, -2
    mul  $t2, $t6, $t9
    add  $t2, $t2, $t7
    sll  $t2, $t2, 2
    la   $t3, MARK
    add  $t3, $t3, $t2
    li   $t6, 1
    sw   $t6, 0($t3)

md_next_cell:
    addi $t1, $t1, 1          # col++
    j    md_col_loop

md_next_row:
    addi $t0, $t0, 1          # row++
    j    md_row_loop

md_done:
    # EPILOGUE: restore $ra and return
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra
    
######################## delete_marked_cells ############################
delete_marked_cells:
    la   $t0, GRID_HEIGHT
    lw   $t8, 0($t0)          # t8 = H
    la   $t0, GRID_WIDTH
    lw   $t9, 0($t0)          # t9 = W

    addi $t7, $zero, 0        # t7 = any_deleted flag = 0

    addi $t0, $zero, 0        # t0 = row = 0
dmc_row_loop:
    bge  $t0, $t8, dmc_done   # if row >= H, finish

    addi $t1, $zero, 0        # t1 = col = 0
dmc_col_loop:
    bge  $t1, $t9, dmc_next_row   # if col >= W, next row

    # index = row * W + col
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2          # index * 4 bytes

    # MARK[row][col]
    la   $t3, MARK
    add  $t4, $t3, $t2        # &MARK[row][col]
    lw   $t5, 0($t4)          # t5 = MARK[row][col]

    beq  $t5, $zero, dmc_next_col   # if not marked, nothing to delete

    # Delete gem from BOARD[row][col]
    la   $t3, BOARD
    add  $t6, $t3, $t2        # &BOARD[row][col]
    sw   $zero, 0($t6)        # BOARD[row][col] = 0

    # Remember that some deletion occurred
    li   $t7, 1

dmc_next_col:
    addi $t1, $t1, 1          # col++
    j    dmc_col_loop

dmc_next_row:
    addi $t0, $t0, 1          # row++
    j    dmc_row_loop

dmc_done:
    move $v0, $t7             # return any_deleted in v0
    jr   $ra
    
######################## unsupport_down ##################################
######################## unsupport_down ##################################
# Apply gravity: in each column, make all gems fall toward the bottom
# (larger row indices). No stack use needed (no jal inside).
##########################################################################
unsupport_down:
    # t8 = H, t9 = W
    la   $t0, GRID_HEIGHT
    lw   $t8, 0($t0)          # H
    la   $t0, GRID_WIDTH
    lw   $t9, 0($t0)          # W

    addi $t1, $zero, 0        # t1 = col = 0
ud_col_loop:
    bge  $t1, $t9, ud_done    # if col >= W, all columns done

    # For this column c = t1:
    # read_row in t0, write_row in t4 (both start at bottom H-1)
    addi $t0, $t8, -1         # t0 = read_row = H-1
    addi $t4, $t8, -1         # t4 = write_row = H-1

ud_read_loop:
    bltz $t0, ud_fill_zeros   # if read_row < 0, stop reading

    # index_read = read_row * W + col
    mul  $t2, $t0, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2

    la   $t3, BOARD
    add  $t5, $t3, $t2        # &BOARD[read_row][col]
    lw   $t6, 0($t5)          # t6 = BOARD[read_row][col]

    beq  $t6, $zero, ud_next_read   # skip empty cells

    # index_write = write_row * W + col
    mul  $t2, $t4, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2
    add  $t7, $t3, $t2        # &BOARD[write_row][col]

    sw   $t6, 0($t7)          # BOARD[write_row][col] = gem

    # If read_row != write_row, clear the old spot
    bne  $t0, $t4, ud_clear_old
    j    ud_dec_both

ud_clear_old:
    sw   $zero, 0($t5)        # BOARD[read_row][col] = 0

ud_dec_both:
    addi $t4, $t4, -1         # write_row-- (move upward for next gem)

ud_next_read:
    addi $t0, $t0, -1         # read_row--
    j    ud_read_loop

# After consuming all rows, ensure rows 0..write_row are 0
ud_fill_zeros:
    move $t0, $t4             # t0 = last write_row
ud_zero_loop:
    bltz $t0, ud_next_col     # if t0 < 0, done zeroing this column

    mul  $t2, $t0, $t9
    add  $t2, $t2, $t1
    sll  $t2, $t2, 2
    la   $t3, BOARD
    add  $t5, $t3, $t2
    sw   $zero, 0($t5)

    addi $t0, $t0, -1         # row--
    j    ud_zero_loop

ud_next_col:
    addi $t1, $t1, 1          # col++
    j    ud_col_loop

ud_done:
    jr   $ra