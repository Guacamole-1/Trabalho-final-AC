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


	.equ	CLK_FREQ, 9 ; 0x63Hz quando clock é 1kHz      ; tempo para fazer interrupt 0.1s
                        ;9 quando clock é 100 Hz
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
    mov     r0,#0
    bl      outport_write
    mov     r0,#CLK_FREQ
    bl      ptc_init
	mrs     r0, cpsr
	mov     r1, #CPSR_BIT_I
	orr     r0, r0, r1
	msr     cpsr, r0
main_led_init:
    mov     r0, #YELLOW << L1 ; Meter traffic lights a amarelo
    mov     r1, #(RED << L2 | GREEN << L3)     ; Meter pedestrian lights a vermelho e mode a verde
    bl      store_LED_states    
main_loop: ;*** EM CONSTRUÇÃO ***
    bl      inport_read
    bl      check_inport        ;atualizar variaveis
    bl      check_config        ;verificar se estamos em config
    bzc     config_init         
    bl      check_rising_edge
    and     r0,r0,r0
    bzc     ped_button_init
    bl      LED_output           ;loop para quando não se pressiona no pedestrian button
    b       main_loop

ped_button_init: ;inicialização dos LEDs
    mov     r0, #0 ;em estado quando o botão de peões está ativo nenhum led pisca
    mov     r1, #(GREEN << L2 | RED << L1 | GREEN << L3);Leds estáticos
    bl      store_LED_states    
ped_button_loop:
    bl      inport_read
    bl      check_inport        ;atualizar variaveis
    bl      check_config        ;verificar se estamos em config
    bzc     config_init         
    bl      check_rising_edge
    bl      get_time
    bl      outport_write
    b       ped_button_loop
    
      
config_init:
    mov     r0, #(YELLOW << L1 | GREEN << L2); leds para piscar 
    mov     r1, #YELLOW << L3;Leds estáticos
    bl      store_LED_states
config_loop:
    bl      get_config
    bl      outport_write
    b       main_loop

check_config:
    push lr
    bl      get_config      
    and     r0,r0,r0
    pop pc      

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

increment_time:
    push    lr
    bl      get_time
    ldr     r2, current_cross_t_addr
    ldrb    r2, [r2]
    add     r0,r2,r0
	str     r0, [r1]    ; r1 é time_addr de "bl get_time"
    pop     pc

crossing_time_addr:
    .word crossing_time
current_cross_t_addr:
    .word current_crossing_t

;função para atualizar estado "atual" para estado antigo e carregar novo valor para atual
;função para melhor leitura de código no check inport
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
    


;verifica se o pedestrian button deu rising edge (0 -> 1)
;e depois aumenta o valor do time (tempo de passar para os peões)
;output: 1 -> rising edge == true, 0 -> rising edge == false
check_rising_edge: 
    push    lr
    mov     r0, #0                  ; rising edge == false
	ldr		r1, pedestrian_button_addr
    ldrb    r1, [r1]
    ldr		r3, past_pedestrian_button_addr
    ldrb    r3, [r3]
	and 	r3,r3,r3
	bzc		check_rising_edge_r		; continua se pedestrian button anterior == 0
	and		r1,r1,r1					
	bzs		check_rising_edge_r		; continua se pedestrian button agora == 1		
	bl      increment_time			; rising edge == true
    mov     r0, #1
check_rising_edge_r:					
	pop     pc						

pedestrian_button_addr:
    .word pedestrian_button
past_pedestrian_button_addr:
    .word past_pedestrian_button

;Acende os leds 
;r1 - LEDs para piscar r2 - LEDs para estarem permanentemente ativos
LED_output:
    push    lr
    bl      get_LED_states
    mov     r1,r0
    mov     r2,r1
    bl      blink_get_ticks
    mov     r3, #BLINK_TIME
    cmp     r0,r3          ; ver se o clk está a 0.5s >
    blo     LED_output_return
    mov     r0,r1
    bl      LED_flashing_toggle ; dar toggle ao flashing led
    bl      get_LED_states
    orr     r0,r0,r1
    bl      outport_write
    bl      blink_reset
LED_output_return:
    pop     pc



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
	push    lr
	push    r0
	push    r1
    push    r2
    ldr     r1, blink_tick_addr
    ldr     r0,[r1]
	add     r0,r0,#1 ; somar blink_tick
	str     r0,[r1]
    bl      get_time
    and     r0,r0,r0
    bzs     isr_jump
    sub     r0,r0,#1 ; subtrair 1 a time
    str     r0,[r1]  ; r1 de get_time
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



LED_state_reset:
    push r1
    push r3
    ldr	r1, LED_flashing_addr
    mov r3, #0
    strb r3,[r1]
    pop r3
    pop r1
    mov pc, lr

;output:r0- LEDs que piscam r1-LEDs estáticos 
get_LED_states:
    push    r2
    ldr     r0, LED_flashing_addr
    ldr     r1, LED_static_addr
    ldrb    r0,[r0]
    ldrb    r1,[r1]
    pop     r2
    mov     pc, lr

;input:r0- LEDs que piscam r1-LEDs estáticos 
store_LED_states:
    ldr     r2, LED_flashing_addr
    ldr     r3, LED_static_addr
    strb    r0,[r2]
    ldr     r2, LED_flashing_mask_addr
    strb    r0,[r2]
    strb    r1,[r3]
    mov     pc, lr

;r0- bits to toggle(mask) r2- LED_flashing
;Output: r0 - toggled led_flashing
LED_flashing_toggle:
    push    r1
    push    r2
    push    r3
    ldr     r0, LED_flashing_mask_addr
    ldrb    r0,[r0]
    ldr	    r3, LED_flashing_addr
    ldrb    r2, [r3]
    eor     r1, r2, r0
    and     r0, r1,r0
    strb    r0, [r3]
    pop     r3
    pop     r2
    pop     r1
    mov     pc, lr


LED_flashing_addr:
    .word LED_flashing    ;LEDs que vao piscar
LED_static_addr:
    .word LED_static    ;LEDs que estão sempre ON
LED_flashing_mask_addr:
    .word LED_flashing_mask


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
time:                              ;tempo para os pedestrians
    .word 0
LED_flashing:
    .byte 0
LED_flashing_mask:
    .byte 0
pedestrian_button:
    .byte 0
past_pedestrian_button:
    .byte 0
config:
    .byte 0
crossing_time:
    .byte 10, 20, 30, 45, 60
current_crossing_t:                 ;tempo usado para aumentar o time
    .byte 10
LED_static:
    .byte 0

    .stack
    .space STACK_SIZE
stack_top:
