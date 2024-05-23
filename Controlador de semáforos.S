    .equ	CPSR_BIT_I, 0b010000          ; Mascara para o bit I do registo CPSR
    .equ    STACK_SIZE, 64
    .equ	INPORT_ADDRESS, 0xFF80       
	.equ	OUTPORT_ADDRESS, 0xFFC0
    .equ    PTC_ADDRESS, 0xFF40
    .equ    PB_MASK, 0x01
    .equ    CONFIG_MASK, 0x10
    .equ    TIME_MASK, 0b111 << 5
    .equ    RED, 1
    .equ    GREEN, 0b10
    .equ    YELLOW, 0b11
    .equ    L1, 0                  ; TRAFFIC LIGHTS OFFSET
    .equ    L2, 2                  ; PEDESTRIAN LIGHTS OFFSET
    .equ    L3, 4                  ; MODE OFFSET
    .equ	PTC_TCR, 0             ; Timer Control Register
	.equ	PTC_TMR, 2             ; Timer Match Register
	.equ	PTC_TC,  4             ; Timer Counter
	.equ	PTC_TIR, 6             ; Timer Interrupt Register

	.equ	PTC_CMD_START, 0       ; Comando para iniciar a contagem no pTC
	.equ	PTC_CMD_STOP, 1        ; Comando para parar a contagem no pTC


	.equ	CLK_FREQ, 0x63;Hz      ; tempo para fazer interrupt 0.1s

    .equ    BLINK_TIME, 5 ; (500 ms)


.section startup
    b   _start
    b   .   ; meter isr com o propósito de aumentar a variavel crossing_time
_start:
    mov sp, #stack_top_addr
    mov r0, pc
    add lr, r0, #4
    ldr pc, main_addr

main_addr:
    .word main

    .text
main:
    mov r0,#CLK_FREQ
    bl ptc_init
	mrs	r0, cpsr
	mov	r1, #CPSR_BIT_I
	orr	r0, r0, r1
	msr	cpsr, r0
main_loop:
    bl inport_read
    bl config_mode

    b main_loop


; Rotina:    config_check
; Descricao: verifica config
; Entradas:  R0 - valor adquirido do porto de entrada
; Saidas:    
; Efeitos:   R1- temp  R2- time
config_mode:
    mov r1, #CONFIG_MASK ; Verificar se Config == 1
    and r2, r0, r1
    bne config_mode_return 
    mov r1, #TIME_MASK ; Verificar qual é o time no inport
    and r2, r0, r1 ; current crossing time
    mov r1, #crossing_time_addr
    lsl r2, r2, #1
    ldr r0, [r1, r2]
    mov r1, #current_crossing_t ; mudar o current time
    str r0, [r1]
config_mode_return:
    mov pc, lr

LED_blink: ; assumindo que começa do 0
    mov r1, #YELLOW << L1 ; meter traffic lights a amarelo
    mov r2, #RED << L2 ; Meter pedestrian lights a vermlho
    and r3, r2, r1 ; L1 a amarelo e L2 a vermelho
    bl blink_get_ticks
    mov r2, #5
    cmp r0,r2
    blo LED_blink_return


LED_blink_return:
    mov pc, lr

; Rotina:    isr
; Descricao: Incrementa o valor da variável global time e blink_tick.
; Entradas:  -
; Saidas:    -
; Efeitos:   incrementa a variável time_addr e blink_tick
isr:
	push lr
	push r0
	push r1
    push r2
    mov r1, #blink_tick_addr
    ldr r2,[r1]
	add r2,r1,#1 ; somar blink_tick
	str r0,[r1]
    mov r1, #time_addr
	ldr r0, [r1]
    mov r1, #0
    cmp r0, r1
    beq isr_jump
    sub r0,r0,#1 ; subtrair 1 a time
isr_jump:    
	bl ptc_clr_irq
    pop r2
	pop r1
	pop r0
	pop lr
	movs pc, lr


; Rotina:    clk_init
; Descricao: Inicia uma nova contagem no periferico pTC com o intervalo de
;            contagem recebido em R0, em ticks, limpando eventuais pedidos de
;            interrupcao pendentes e iniciando com o valor zero a variavel
;            global clk.
; Entradas:  R0 - Valor do novo intervalo de contagem, em ticks.
; Saidas:    -
; Efeitos:   Inicia a contagem no periferico a partir do valor zero, limpando
;            eventuais pedidos de interrupcao pendentes e iniciando com o
;            valor zero a variavel global sysclk
blink_reset:
	push lr
	mov r1, #blink_tick_addr
	mov r2, #0
	str r2, [r1]
	bl ptc_init
	pop pc


; Rotina:    sysclk_get_ticks
; Descricao: Devolve o valor corrente da variável global sysclk.
;            Interface exemplo: uint16_t sysclk_get_ticks ( );
; Entradas:  -
; Saidas:    r0 - CLK
; Efeitos:   -
blink_get_ticks:
	mov r1, #blink_tick_addr
	ldr r0, [r1]
	mov pc, lr

time_get_ticks:
	mov r1, #time_addr
	ldr r0, [r1]
	mov pc, lr


; Rotina:    inport_read
; Descricao: Adquire e devolve o valor corrente do porto de entrada.
; Entradas:  -
; Saidas:    R0 - valor adquirido do porto de entrada
; Efeitos:   -
inport_read:
    mov	r1, #INPORT_ADDRESS & 0xFF
    movt r1, #INPORT_ADDRESS >> 8 
    ldrb r0, [r1, #0]
	mov	pc, lr

; Rotina:    outport_write
; Descricao: Escreve no porto de saida o valor recebido em R0.
; Entradas:  R0 - valor a atribuir ao porto de saida.
; Saidas:    -
; Efeitos:   -
outport_write:
    mov	r1, #OUTPORT_ADDRESS & 0xFF
    movt r1, #OUTPORT_ADDRESS >> 8
	strb r0, [r1, #0]
	mov	pc, lr

; Rotina:    ptc_init
; Descricao: Faz a iniciacao do periférico pTC, habilitando o seu funcionamento
;            em modo continuo e com o intervalo de contagem recebido em R0, em
;            ticks.
; Entradas:  R0 - Valor do novo intervalo de contagem, em ticks.
; Saidas:    -
; Efeitos:   Inicia a contagem no periferico a partir do valor zero, limpando
;            o pedido de interrupcao eventualmente pendente.
ptc_init:
    push    lr
    mov	r1, #PTC_ADDRESS & 0xFF
    movt r1, #PTC_ADDRESS >> 8 
	mov	r2, #PTC_CMD_STOP
	strb	r2, [r1, #PTC_TCR]
	strb	r0, [r1, #PTC_TMR]
    bl  ptc_clr_irq
	mov	r2, #PTC_CMD_START
	strb	r2, [r1, #PTC_TCR]
	pop pc

; Rotina:    ptc_start
; Descricao: Habilita a contagem no periferico pTC.
; Entradas:  -
; Saidas:    -
; Efeitos:   -
ptc_start:
	mov	r0, #PTC_ADDRESS & 0xFF
    movt r0, #PTC_ADDRESS >> 8 
	mov	r1, #PTC_CMD_START
	strb	r1, [r0, #PTC_TCR]
	mov	pc, lr

; Rotina:    ptc_stop
; Descricao: Para a contagem no periferico pTC.
; Entradas:  -
; Saidas:    -
; Efeitos:   O valor do registo TC do periferico e colocado a zero.
ptc_stop:
    mov	r0, #PTC_ADDRESS & 0xFF
    movt r0, #PTC_ADDRESS >> 8 
	mov	r1, #PTC_CMD_STOP
	strb	r1, [r0, #PTC_TCR]
	mov	pc, lr

ptc_restart:
    push lr
    bl ptc_stop
    bl ptc_start
    pop pc

; Rotina:    ptc_get_value
; Descricao: Devolve o valor corrente da contagem do periferico pTC.
; Entradas:  -
; Saidas:    R0 - O valor corrente do registo TC do periferico.
; Efeitos:   -
ptc_get_value:
    mov	r1, #PTC_ADDRESS & 0xFF
    movt r1, #PTC_ADDRESS >> 8 
	ldrb	r0, [r1, #PTC_TC]
	mov	pc, lr

; Rotina:    ptc_clr_irq
; Descricao: Sinaliza o periferico pTC que foi atendido um pedido de
;            interrupção.
; Entradas:  -
; Saidas:    -
; Efeitos:   -
ptc_clr_irq:
    mov	r0, #PTC_ADDRESS & 0xFF
    movt r0, #PTC_ADDRESS >> 8 
	strb	r1, [r0, #PTC_TIR]
	mov	pc, lr

blink_tick_addr:
    .word blink_tick

time_addr:
    .word time

crossing_time_addr:
    .word crossing_time

current_cross_t_addr:
    .word current_crossing_t

stack_top_addr:
    .word stack_top

    .data
blink_tick:
    .word 0
crossing_time:
    .word 10, 20, 30, 45, 60
current_crossing_t:
    .word 10
time:
    .word 0

    .stack
    .space STACK_SIZE
stack_top:
