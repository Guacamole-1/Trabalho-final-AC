    .equ    STACK_SIZE, 64
    .equ	INPORT_ADDRESS, 0xFF80       
	.equ	OUTPORT_ADDRESS, 0xFFC0
    .equ    PTC_ADDRESS, 0xFF40
    .equ    PB_MASK, 0x01
    .equ    CONFIG_MASK, 0x10
    .equ    TIME_MASK, 0b00000111

.section startup
    b   _start
    b   .
_start:
    ldr sp, stack_top_addr
    mov r0, pc
    add lr, r0, #4
    ldr pc, main_addr
    b   .

main_addr:
    .word main
    .text

main:
    push lr
    push r0
    bl inport_read
    bl config_check
    pop r0
    pop pc

config_check:
    mov r1, #CONFIG_MASK
    and r2, r0, r1
    beq config_check_return
    mov r1, #TIME_MASK
    and r3, r0, r1
    ldr r1, crossing_time_addr
    lsl r2, r2, #1
    ldr r0, [r1, r2]
    and r2, r2, r2
    bne config_check
config_check_return:
    mov pc, lr

inport_read:
    mov	r1, #INPORT_ADDRESS & 0xFF
    movt r1, #INPORT_ADDRESS >> 8 & 0xFF
    ldrb r0, [r1, #0]
	mov	pc, lr

outport_write:
    mov	r1, #OUTPORT_ADDRESS & 0xFF
    movt r1, #OUTPORT_ADDRESS >> 8 & 0xFF
	strb r0, [r1, #0]
	mov	pc, lr

crossing_time_addr:
    .word crossing_time

stack_top_addr:
    .word stack_top

    .data
crossing_time:
    .word 10, 20, 30, 45, 60

    .stack
    .space STACK_SIZE
stack_top:
