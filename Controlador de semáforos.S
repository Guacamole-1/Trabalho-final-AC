    .equ	CPSR_BIT_I, 0b010000          ; Mascara para o bit I do registo CPSR
    .equ    STACK_SIZE, 128
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


	.equ	CLK_FREQ, 0x1; 0x63Hz quando clock é 1kHz      ; tempo para fazer interrupt 0.1s
                        ;1 quando clock é 10 Hz
    .equ    BLINK_TIME, 5 ; (500 ms)


.section startup
    b   _start
    ldr pc,isr_addr   ; isr com o propósito de aumentar a variavel crossing_time
_start:
    ldr sp, stack_top_addr
    mov r0, pc
    add lr, r0, #4
    ldr pc, main_addr

main_addr:
    .word main
isr_addr:
    .word isr
    
    .text
stack_top_addr:
    .word stack_top


main:
    bl      blink_reset
    bl      LED_state_reset
    mov     r0,#0
    bl      outport_write
    mov     r0,#CLK_FREQ
    bl      ptc_init
	mrs     r0, cpsr
	mov     r1, #CPSR_BIT_I
	orr     r0, r0, r1
	msr     cpsr, r0
main_loop: ;*** EM CONSTRUÇÃO ***
    bl      inport_read
    bl      check_inport        ;atualizar variaveis
    bl      get_config      
    and     r0,r0,r0        
    bzc     config_loop         ;verificar se estamos em config
    bl      check_rising_edge
    bl      LED_blink
    b       main_loop
config_loop:
    bl      get
    bl      outport_write
    b       main_loop

;Função para ver o inport e atualizar as variaveis:
;(past_)pedestrian_button, Config, current_cross_t
;input: r0 - inport
check_inport:
    push    lr
    mov     r1, #PB_MASK
    and     r1, r1, r0
    bl      ped_button_update   ;atualizar estado "atual" para estado antigo e carregar novo valor para atual
    mov     r2, #CONFIG_MASK
    and     r2, r2, r0
    lsr     r2, r2, #4
    ldr     r1, config_addr
    strb    r2, [r1]
    bzs     check_inport_return
;if config == 1
    mov     r3, #TIME_MASK
    and     r3, r3, r0
    lsr     r3, r3, #5
    ldr     r0, crossing_time_addr
    ldrb    r3, [r0,r3]
    ldr     r0, current_cross_t_addr
    strb    r3, [r0]

check_inport_return:
    pop     pc

;função para atualizar estado "atual" para estado antigo e carregar novo valor para atual
;input: r1 - pedestrian button (mask)
ped_button_update:
    push    r4
    ldr     r2, pedestrian_button_addr
    ldrb    r4, [r2]                            ;estado do botao atual passa a ser passado
    ldr     r3, past_pedestrian_button_addr 
    strb    r4, [r3]                            ;atualizar estado do botão anterior
    strb    r1, [r2]                            ;atualizar estado do botão atual
    pop     r4
    mov     pc, lr
    


;output -> rising edge (0 - false, 1 - true) 
check_rising_edge: ; **em vez de sair r0 atualizr time**
	ldr		r1, pedestrian_button_addr
    ldrb    r1, [r1]
    ldr		r3, past_pedestrian_button_addr
    ldrb    r3, [r3]
	mov		r0, #0	
	ldrb	r3, [r2]
	and 	r3,r3,r3
	bzc		check_rising_edge_r		; continua se pedestrian button anterior == 0
	and		r1,r1,r1					
	bzs		check_rising_edge_r		; continua se pedestrian button agora == 1		
	mov		r0, #1						; rising edge == true
check_rising_edge_r:
	strb	r1, [r2]					; atualizar estado do pedestrian button
	mov		pc, lr						; return rising_edge

pedestrian_button_addr:
    .word pedestrian_button
past_pedestrian_button_addr:
    .word past_pedestrian_button


;r1 - LED L1 para piscar r2/r3 - LED L2/L3 para estar permanentemente ativo
LED_blink:
    push lr
    mov r1, #YELLOW << L1 ; Meter traffic lights a amarelo
    mov r2, #RED << L2 ; Meter pedestrian lights a vermlho (é melhor meter isto quando entra no config!!!)
    mov r3, #GREEN << L3
    bl blink_get_ticks
    mov r4, #BLINK_TIME
    cmp r0,r4           ; ver se o clk está a 0.5s >
    blo LED_blink_return
    mov r0,r1
    bl LED_state_toggle ; dar toggle ao led L1
    orr r0,r0,r2 ; L2  constante
    orr r0,r0,r3 ; L3  constante
    bl outport_write
    bl blink_reset
LED_blink_return:
    pop pc

crossing_time_addr:
    .word crossing_time
current_cross_t_addr:
    .word current_crossing_t

get_config:
    ldr r1, config_addr
    ldrb r0, [r1]
    mov pc, lr


config_addr:
    .word config


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
    ldr r1, blink_tick_addr
    ldr r0,[r1]
	add r0,r0,#1 ; somar blink_tick
	str r0,[r1]
    ;mov r1, #time_addr
	;ldr r0, [r1]
    ;mov r1, #0
    ;cmp r0, r1
    ;beq isr_jump
    ;sub r0,r0,#1 ; subtrair 1 a time
isr_jump:    
	bl ptc_clr_irq
    pop r2
	pop r1
	pop r0
	pop lr
	movs pc, lr

get_time:
	ldr r1, time_addr
	ldr r0, [r1]
	mov pc, lr

time_addr:
    .word time
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
    push r1
    push r0
	ldr r1, blink_tick_addr
	mov r2, #0
	str r2, [r1]
	;bl ptc_init
    pop r0
    pop r1
	mov pc, lr

blink_get_ticks:
    push r1
	ldr r1, blink_tick_addr
	ldr r0, [r1]
    pop r1
	mov pc, lr

blink_tick_addr:
    .word blink_tick

;r0- bits to toggle(mask) r2- LED_state
LED_state_toggle: 
    push r1
    push r2
    push r3
    ldr	r3, LED_state_addr
    ldrb r2, [r3]
    eor r1, r2, r0
    and r0, r1,r0
    strb r0, [r3]
    pop r3
    pop r2
    pop r1
    mov pc, lr

LED_state_reset:
    push r1
    push r3
    ldr	r1, LED_state_addr
    mov r3, #0
    strb r3,[r1]
    pop r3
    pop r1
    mov pc, lr

LED_state_addr:
    .word LED_state

; Rotina:    sysclk_get_ticks
; Descricao: Devolve o valor corrente da variável global sysclk.
;            Interface exemplo: uint16_t sysclk_get_ticks ( );
; Entradas:  -
; Saidas:    r0 - CLK
; Efeitos:   -






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
    push r1
    bl  ptc_clr_irq
    pop r1
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
    mov r1,#0
	strb	r1, [r0, #PTC_TIR]
	mov	pc, lr

    .data

blink_tick:
    .word 0
time:
    .word 0
LED_state:
    .byte 0
pedestrian_button:
    .byte 0
past_pedestrian_button:
    .byte 0
config:
    .byte 0
crossing_time:
    .byte 10, 20, 30, 45, 60
current_crossing_t:
    .byte 10
    .stack
    .space STACK_SIZE
stack_top:
