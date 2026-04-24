// Módulo de topo: computação SHA-1 em FPGA com iteração dinâmica de nonce
// Implementa mineração proof-of-work: recebe mensagem + hash esperado via UART,
// itera nonce de 0 até DIFFICULTY, calculando SHA-1(mensagem) até encontrar correspondência MATCH
`default_nettype none

module top(
    input wire clk,            // Relógio do sistema (27 MHz)
	input wire rst,            // Reset ativo em nível alto
    input wire uart_rx,        // Pino de recepção UART
    output wire uart_tx,       // Pino de transmissão UART
    output wire led,           // LED: status de correspondência SHA-1 (ativo-baixo)
    output wire led_sha1_work, // LED: processamento SHA-1 ativo (ativo-baixo)
    output wire led_sha1_finish, // LED: computação SHA-1 finalizada (ativo-baixo)
    output wire led_uart_work, // LED: transmissão UART ativa (ativo-baixo)
    output wire led_uart_finish  // LED: transmissão UART finalizada (ativo-baixo)
);

parameter CLK_FRE  = 27;    // Frequência do relógio em MHz
parameter UART_FRE = 115200; // Taxa de bauds UART 115200

parameter DIFFICULTY = 320000000; // Valor máximo de nonce para proof-of-work (320.000.000 iterações)

// ========================================
// ESTRATÉGIA QUAD SHA-1 CORE
// ========================================
// Implementação: 4 cores SHA-1 em paralelo para quadriplicar velocidade de mineração
// - sha1_core_0: processa nonce_0 (nonce par: 0, 2, 4, 6, ...)
// - sha1_core_1: processa nonce_1 (nonce ímpar: nonce_0 + 1)
// - sha1_core_2: processa nonce_2 (nonce ímpar: nonce_0 + 2)
// - sha1_core_3: processa nonce_3 (nonce ímpar: nonce_0 + 3)
// - Ambos cores executam SHA-1 simultaneamente
// - Incremento: nonce_0 += 4 a cada iteração
// - Resultado: até 4x velocidade vs. implementação com 1 core

// Mensagem de entrada (dinâmica): 40 bytes recebidos via UART, armazenados em buffer[0..39]
// Hash SHA-1 esperado: 40 caracteres ASCII hexadecimais recebidos via UART, armazenados em buffer[40..79]
// Hash representa 20 bytes binários (160 bits) para comparação SHA-1
reg [159:0] SHA1_EXPECTED;  // Hash SHA-1 esperado (160 bits = 20 bytes, decodificado de buffer[40..79])

// Variável nonce QUAD-core: 
// - nonce_0: valor atual (nonce par) - SEQUENCIAL
// - nonce_1: nonce_0 + 1 (nonce ímpar) - DERIVADO COMBINACIONALMENTE
// Nota: 32 bits suportam até 4.294.967.295, mais que suficiente para 320.000.000 dificuldade
reg [31:0] nonce_0;  // Nonce para sha1_core_0  (incrementado +4)
wire [31:0] nonce_1;  // Nonce para sha1_core_1 (nonce_0 + 1) - wire combinacional
wire [31:0] nonce_2;  // Nonce para sha1_core_2 (nonce_0 + 2) - wire combinacional
wire [31:0] nonce_3;  // Nonce para sha1_core_3 (nonce_0 + 3) - wire combinacional

assign nonce_1 = nonce_0 + 32'd1;  // Sempre 1 a mais que nonce_0
assign nonce_2 = nonce_0 + 32'd2;  // Sempre 2 a mais que nonce_0
assign nonce_3 = nonce_0 + 32'd3;  // Sempre 3 a mais que nonce_0

// Conversão ASCII do nonce: comprimento variável (sem zeros à esquerda)
// Máximo 9 bytes para valores até 999.999.999 (menos que 120.000.000)
// Exemplo: nonce=1        -> nonce_ascii="1"         (1 byte)
//          nonce=12345    -> nonce_ascii="12345"     (5 bytes)
//          nonce=120000000 -> nonce_ascii="120000000" (9 bytes)

// ASCII conversion para nonce_0 (registrador - atualizado a cada ciclo)
reg [71:0] nonce_ascii_0;  // Expandido para 72 bits (9 bytes = até 9 dígitos)
reg [3:0] nonce_ascii_len_0;  // Aumentado para 4 bits (suporta até 15 dígitos, usamos até 9)

// ASCII conversion para nonce_1 (registrador - atualizado a cada ciclo, derivado de nonce_0 + 1)
// Nota: Mudado de wire para reg porque recebe atribuições em always @(*)
reg [71:0] nonce_ascii_1;  // Expandido para 72 bits (9 bytes = até 9 dígitos)
reg [3:0] nonce_ascii_len_1;  // Aumentado para 4 bits (suporta até 15 dígitos, usamos até 9)

reg [71:0] nonce_ascii_2;  
reg [3:0] nonce_ascii_len_2;  

reg [71:0] nonce_ascii_3;  
reg [3:0] nonce_ascii_len_3;  

reg [71:0] nonce_ascii_4;  
reg [3:0] nonce_ascii_len_4;  

// Lógica combinacional de extração de dígitos: dígitos decimais derivados do valor do nonce

// ========== DÍGITOS PARA NONCE_0 ==========
// Suporta até 999.999.999 (9 dígitos, 10^8)
wire [31:0] digit9_0 = (nonce_0 / 32'd100000000) % 32'd10;  // 10^8
wire [31:0] digit8_0 = (nonce_0 / 32'd10000000) % 32'd10;   // 10^7
wire [31:0] digit7_0 = (nonce_0 / 32'd1000000) % 32'd10;    // 10^6
wire [31:0] digit6_0 = (nonce_0 / 32'd100000) % 32'd10;     // 10^5
wire [31:0] digit5_0 = (nonce_0 / 32'd10000) % 32'd10;      // 10^4
wire [31:0] digit4_0 = (nonce_0 / 32'd1000) % 32'd10;       // 10^3
wire [31:0] digit3_0 = (nonce_0 / 32'd100) % 32'd10;        // 10^2
wire [31:0] digit2_0 = (nonce_0 / 32'd10) % 32'd10;         // 10^1
wire [31:0] digit1_0 = nonce_0 % 32'd10;                    // 10^0

// ========== DÍGITOS PARA NONCE_1 ==========
// Suporta até 999.999.999 (9 dígitos, 10^8)
wire [31:0] digit9_1 = (nonce_1 / 32'd100000000) % 32'd10;  // 10^8
wire [31:0] digit8_1 = (nonce_1 / 32'd10000000) % 32'd10;   // 10^7
wire [31:0] digit7_1 = (nonce_1 / 32'd1000000) % 32'd10;    // 10^6
wire [31:0] digit6_1 = (nonce_1 / 32'd100000) % 32'd10;     // 10^5
wire [31:0] digit5_1 = (nonce_1 / 32'd10000) % 32'd10;      // 10^4
wire [31:0] digit4_1 = (nonce_1 / 32'd1000) % 32'd10;       // 10^3
wire [31:0] digit3_1 = (nonce_1 / 32'd100) % 32'd10;        // 10^2
wire [31:0] digit2_1 = (nonce_1 / 32'd10) % 32'd10;         // 10^1
wire [31:0] digit1_1 = nonce_1 % 32'd10;                    // 10^0

// ========== DÍGITOS PARA NONCE_2 ==========
// Suporta até 999.999.999 (9 dígitos, 10^8)
wire [31:0] digit9_2 = (nonce_2 / 32'd100000000) % 32'd10;  // 10^8
wire [31:0] digit8_2 = (nonce_2 / 32'd10000000) % 32'd10;   // 10^7
wire [31:0] digit7_2 = (nonce_2 / 32'd1000000) % 32'd10;    // 10^6
wire [31:0] digit6_2 = (nonce_2 / 32'd100000) % 32'd10;     // 10^5
wire [31:0] digit5_2 = (nonce_2 / 32'd10000) % 32'd10;      // 10^4
wire [31:0] digit4_2 = (nonce_2 / 32'd1000) % 32'd10;       // 10^3
wire [31:0] digit3_2 = (nonce_2 / 32'd100) % 32'd10;        // 10^2
wire [31:0] digit2_2 = (nonce_2 / 32'd10) % 32'd10;         // 10^1
wire [31:0] digit1_2 = nonce_2 % 32'd10;                    // 10^0

// ========== DÍGITOS PARA NONCE_3 ==========
// Suporta até 999.999.999 (9 dígitos, 10^8)
wire [31:0] digit9_3 = (nonce_3 / 32'd100000000) % 32'd10;  // 10^8
wire [31:0] digit8_3 = (nonce_3 / 32'd10000000) % 32'd10;   // 10^7
wire [31:0] digit7_3 = (nonce_3 / 32'd1000000) % 32'd10;    // 10^6
wire [31:0] digit6_3 = (nonce_3 / 32'd100000) % 32'd10;     // 10^5
wire [31:0] digit5_3 = (nonce_3 / 32'd10000) % 32'd10;      // 10^4
wire [31:0] digit4_3 = (nonce_3 / 32'd1000) % 32'd10;       // 10^3
wire [31:0] digit3_3 = (nonce_3 / 32'd100) % 32'd10;        // 10^2
wire [31:0] digit2_3 = (nonce_3 / 32'd10) % 32'd10;         // 10^1
wire [31:0] digit1_3 = nonce_3 % 32'd10;                    // 10^0

// Bloco de mensagem: bloco de entrada de 512 bits com preenchimento (padrão RFC 3174 SHA-1)
// Estrutura dinâmica:
//   Bytes 0-39:  Mensagem (40 bytes) do buffer UART
//   Bytes 40+:   Nonce ASCII (1-9 bytes, comprimento variável, sem zeros à esquerda, até 120M)
//   Byte 47+:    0x80 (marcador de preenchimento) + bytes zero + comprimento_mensagem_bits (64-bit big-endian)

// ========== MESSAGE_BLOCK_0 para sha1_core_0 com nonce_0 (par) ==========
reg [511:0] MESSAGE_BLOCK_0;

// ========== MESSAGE_BLOCK_1 para sha1_core_1 com nonce_1 (ímpar) ==========
reg [511:0] MESSAGE_BLOCK_1;

// ========== MESSAGE_BLOCK_2 para sha1_core_2 com nonce_2 ==========
reg [511:0] MESSAGE_BLOCK_2;

// ========== MESSAGE_BLOCK_3 para sha1_core_3 com nonce_3 ==========
reg [511:0] MESSAGE_BLOCK_3;

// Lógica combinacional: constrói dinamicamente MESSAGE_BLOCK_0 e MESSAGE_BLOCK_1
// MESSAGE_BLOCK_0: usa nonce_0 (par) e nonce_ascii_0
// MESSAGE_BLOCK_1: usa nonce_1 (ímpar) e nonce_ascii_1
always @(*) begin
    // ========================================
    // PASSO 1: Computar ASCII para nonce_0 (par)
    // ========================================
    if (nonce_0 == 0) begin
        nonce_ascii_len_0 = 4'd1;
        nonce_ascii_0 = {64'd0, 8'h30};  // "0"
    end else if (nonce_0 < 10) begin
        nonce_ascii_len_0 = 4'd1;
        nonce_ascii_0 = {64'd0, 8'h30 + digit1_0[7:0]};  // "1" até "9"
    end else if (nonce_0 < 100) begin
        nonce_ascii_len_0 = 4'd2;
        nonce_ascii_0 = {56'd0, 8'h30 + digit2_0[7:0], 8'h30 + digit1_0[7:0]};  // "10" até "99"
    end else if (nonce_0 < 1000) begin
        nonce_ascii_len_0 = 4'd3;
        nonce_ascii_0 = {48'd0, 8'h30 + digit3_0[7:0], 8'h30 + digit2_0[7:0], 8'h30 + digit1_0[7:0]};  // "100" até "999"
    end else if (nonce_0 < 10000) begin
        nonce_ascii_len_0 = 4'd4;
        nonce_ascii_0 = {40'd0, 8'h30 + digit4_0[7:0], 8'h30 + digit3_0[7:0], 8'h30 + digit2_0[7:0], 8'h30 + digit1_0[7:0]};  // "1000" até "9999"
    end else if (nonce_0 < 100000) begin
        nonce_ascii_len_0 = 4'd5;
        nonce_ascii_0 = {32'd0, 8'h30 + digit5_0[7:0], 8'h30 + digit4_0[7:0], 8'h30 + digit3_0[7:0], 8'h30 + digit2_0[7:0], 8'h30 + digit1_0[7:0]};   // "10000" até "99999"
    end else if (nonce_0 < 1000000) begin
        nonce_ascii_len_0 = 4'd6;
        nonce_ascii_0 = {24'd0, 8'h30 + digit6_0[7:0], 8'h30 + digit5_0[7:0], 8'h30 + digit4_0[7:0], 8'h30 + digit3_0[7:0], 8'h30 + digit2_0[7:0], 8'h30 + digit1_0[7:0]};    // "100000" até "999999"
    end else if (nonce_0 < 10000000) begin
        nonce_ascii_len_0 = 4'd7;
        nonce_ascii_0 = {16'd0, 8'h30 + digit7_0[7:0], 8'h30 + digit6_0[7:0], 8'h30 + digit5_0[7:0], 8'h30 + digit4_0[7:0], 8'h30 + digit3_0[7:0], 8'h30 + digit2_0[7:0], 8'h30 + digit1_0[7:0]};   // "1000000" até "9999999"
    end else if (nonce_0 < 100000000) begin
        nonce_ascii_len_0 = 4'd8;
        nonce_ascii_0 = {8'd0, 8'h30 + digit8_0[7:0], 8'h30 + digit7_0[7:0], 8'h30 + digit6_0[7:0], 8'h30 + digit5_0[7:0], 8'h30 + digit4_0[7:0], 8'h30 + digit3_0[7:0], 8'h30 + digit2_0[7:0], 8'h30 + digit1_0[7:0]};   // "10000000" até "99999999"
    end else begin
        nonce_ascii_len_0 = 4'd9;
        nonce_ascii_0 = {8'h30 + digit9_0[7:0], 8'h30 + digit8_0[7:0], 8'h30 + digit7_0[7:0], 8'h30 + digit6_0[7:0], 8'h30 + digit5_0[7:0], 8'h30 + digit4_0[7:0], 8'h30 + digit3_0[7:0], 8'h30 + digit2_0[7:0], 8'h30 + digit1_0[7:0]};   // "100000000" até "999999999"
    end
    
    // ========================================
    // PASSO 2: Construir MESSAGE_BLOCK_0 com nonce_0
    // Total de dados: 40 (mensagem) + nonce_ascii_len_0 bytes
    // ========================================
    case (nonce_ascii_len_0)
        3'd1: begin
            // 40 + 1 = 41 bytes de dados
            // Comprimento da mensagem: 41 * 8 = 328 bits = 0x0148
            MESSAGE_BLOCK_0 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_0[7:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h48
            };
        end
        3'd2: begin
            // 40 + 2 = 42 bytes de dados
            // Comprimento da mensagem: 42 * 8 = 336 bits = 0x0150
            MESSAGE_BLOCK_0 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_0[15:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00,
                8'h01, 8'h50
            };
        end
        3'd3: begin
            // 40 + 3 = 43 bytes de dados
            // Comprimento da mensagem: 43 * 8 = 344 bits = 0x0158
            MESSAGE_BLOCK_0 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_0[23:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00,
                8'h01, 8'h58
            };
        end
        3'd4: begin
            // 40 + 4 = 44 bytes de dados
            // Comprimento da mensagem: 44 * 8 = 352 bits = 0x0160
            MESSAGE_BLOCK_0 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_0[31:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00,
                8'h01, 8'h60
            };
        end
        3'd5: begin
            // 40 + 5 = 45 bytes de dados
            // Comprimento da mensagem: 45 * 8 = 360 bits = 0x0168
            MESSAGE_BLOCK_0 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_0[39:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h68
            };
        end
        3'd6: begin
            // 40 + 6 = 46 bytes de dados
            // Comprimento da mensagem: 46 * 8 = 368 bits = 0x0170
            MESSAGE_BLOCK_0 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_0[47:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h70
            };
        end
        3'd7: begin
            // 40 + 7 = 47 bytes de dados
            // Comprimento da mensagem: 47 * 8 = 376 bits = 0x0178
            MESSAGE_BLOCK_0 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_0[55:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h78
            };
        end
        4'd8: begin  // 3'd8
            // 40 + 8 = 48 bytes de dados
            // Comprimento da mensagem: 48 * 8 = 384 bits = 0x0180
            MESSAGE_BLOCK_0 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_0[63:0],  // Todos os 8 bytes
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h80
            };
        end
        4'd9: begin  // 3'd9
            // 40 + 9 = 49 bytes de dados
            // Comprimento da mensagem: 49 * 8 = 392 bits = 0x0188
            MESSAGE_BLOCK_0 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_0[71:0],  // Todos os 9 bytes (72 bits = 9 bytes)
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00,
                8'h01, 8'h88
            };
        end
        default: begin
            // Fallback para valores não cobertos (segurança: evita latch)
            MESSAGE_BLOCK_0 = 512'd0;
        end
    endcase
    
    // ========================================
    // PASSO 3: Computar ASCII para nonce_1 (nonce_0 + 1) - COMBINACIONAL
    // ========================================
    // Nota: nonce_1 = nonce_0 + 1, então seus dígitos são derivados de digit*_1
    if (nonce_1 == 0) begin
        nonce_ascii_len_1 = 4'd1;
        nonce_ascii_1 = {64'd0, 8'h30};  // "0"
    end else if (nonce_1 < 10) begin
        nonce_ascii_len_1 = 4'd1;
        nonce_ascii_1 = {64'd0, 8'h30 + digit1_1[7:0]};  // "1" até "9"
    end else if (nonce_1 < 100) begin
        nonce_ascii_len_1 = 4'd2;
        nonce_ascii_1 = {56'd0, 8'h30 + digit2_1[7:0], 8'h30 + digit1_1[7:0]};  // "10" até "99"
    end else if (nonce_1 < 1000) begin
        nonce_ascii_len_1 = 4'd3;
        nonce_ascii_1 = {48'd0, 8'h30 + digit3_1[7:0], 8'h30 + digit2_1[7:0], 8'h30 + digit1_1[7:0]};  // "100" até "999"
    end else if (nonce_1 < 10000) begin
        nonce_ascii_len_1 = 4'd4;
        nonce_ascii_1 = {40'd0, 8'h30 + digit4_1[7:0], 8'h30 + digit3_1[7:0], 8'h30 + digit2_1[7:0], 8'h30 + digit1_1[7:0]};  // "1000" até "9999"
    end else if (nonce_1 < 100000) begin
        nonce_ascii_len_1 = 4'd5;
        nonce_ascii_1 = {32'd0, 8'h30 + digit5_1[7:0], 8'h30 + digit4_1[7:0], 8'h30 + digit3_1[7:0], 8'h30 + digit2_1[7:0], 8'h30 + digit1_1[7:0]};   // "10000" até "99999"
    end else if (nonce_1 < 1000000) begin
        nonce_ascii_len_1 = 4'd6;
        nonce_ascii_1 = {24'd0, 8'h30 + digit6_1[7:0], 8'h30 + digit5_1[7:0], 8'h30 + digit4_1[7:0], 8'h30 + digit3_1[7:0], 8'h30 + digit2_1[7:0], 8'h30 + digit1_1[7:0]};    // "100000" até "999999"
    end else if (nonce_1 < 10000000) begin
        nonce_ascii_len_1 = 4'd7;
        nonce_ascii_1 = {16'd0, 8'h30 + digit7_1[7:0], 8'h30 + digit6_1[7:0], 8'h30 + digit5_1[7:0], 8'h30 + digit4_1[7:0], 8'h30 + digit3_1[7:0], 8'h30 + digit2_1[7:0], 8'h30 + digit1_1[7:0]};   // "1000000" até "9999999"
    end else if (nonce_1 < 100000000) begin
        nonce_ascii_len_1 = 4'd8;
        nonce_ascii_1 = {8'd0, 8'h30 + digit8_1[7:0], 8'h30 + digit7_1[7:0], 8'h30 + digit6_1[7:0], 8'h30 + digit5_1[7:0], 8'h30 + digit4_1[7:0], 8'h30 + digit3_1[7:0], 8'h30 + digit2_1[7:0], 8'h30 + digit1_1[7:0]};   // "10000000" até "99999999"
    end else begin
        nonce_ascii_len_1 = 4'd9;
        nonce_ascii_1 = {8'h30 + digit9_1[7:0], 8'h30 + digit8_1[7:0], 8'h30 + digit7_1[7:0], 8'h30 + digit6_1[7:0], 8'h30 + digit5_1[7:0], 8'h30 + digit4_1[7:0], 8'h30 + digit3_1[7:0], 8'h30 + digit2_1[7:0], 8'h30 + digit1_1[7:0]};   // "100000000" até "999999999"
    end
    
    // ========================================
    // PASSO 4: Construir MESSAGE_BLOCK_1 com nonce_1
    // Total de dados: 40 (mensagem) + nonce_ascii_len_1 bytes
    // ========================================
    case (nonce_ascii_len_1)
        3'd1: begin
            // 40 + 1 = 41 bytes de dados
            // Comprimento da mensagem: 41 * 8 = 328 bits = 0x0148
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_1[7:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h48
            };
        end
        3'd2: begin
            // 40 + 2 = 42 bytes de dados
            // Comprimento da mensagem: 42 * 8 = 336 bits = 0x0150
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_1[15:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00,
                8'h01, 8'h50
            };
        end
        3'd3: begin
            // 40 + 3 = 43 bytes de dados
            // Comprimento da mensagem: 43 * 8 = 344 bits = 0x0158
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_1[23:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00,
                8'h01, 8'h58
            };
        end
        3'd4: begin
            // 40 + 4 = 44 bytes de dados
            // Comprimento da mensagem: 44 * 8 = 352 bits = 0x0160
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_1[31:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00,
                8'h01, 8'h60
            };
        end
        3'd5: begin
            // 40 + 5 = 45 bytes de dados
            // Comprimento da mensagem: 45 * 8 = 360 bits = 0x0168
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_1[39:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h68
            };
        end
        3'd6: begin
            // 40 + 6 = 46 bytes de dados
            // Comprimento da mensagem: 46 * 8 = 368 bits = 0x0170
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_1[47:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h70
            };
        end
        3'd7: begin
            // 40 + 7 = 47 bytes de dados
            // Comprimento da mensagem: 47 * 8 = 376 bits = 0x0178
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_1[55:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h78
            };
        end
        4'd8: begin
            // 40 + 8 = 48 bytes de dados
            // Comprimento da mensagem: 48 * 8 = 384 bits = 0x0180
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_1[63:0],  // Todos os 8 bytes
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h80
            };
        end
        4'd9: begin
            // 40 + 9 = 49 bytes de dados
            // Comprimento da mensagem: 49 * 8 = 392 bits = 0x0188
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_1[71:0],  // Todos os 9 bytes (72 bits = 9 bytes)
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00,
                8'h01, 8'h88
            };
        end
        default: begin
            // Fallback para valores não cobertos (segurança: evita latch)
            MESSAGE_BLOCK_1 = 512'd0;
        end
    endcase

    // ========================================
    // PASSO 5: Computar ASCII para nonce_2 (nonce_1 + 1) - COMBINACIONAL
    // ========================================
    // Nota: nonce_2 = nonce_1 + 1, então seus dígitos são derivados de digit*_2
    if (nonce_2 == 0) begin
        nonce_ascii_len_2 = 4'd1;
        nonce_ascii_2 = {64'd0, 8'h30};  // "0"
    end else if (nonce_2 < 10) begin
        nonce_ascii_len_2 = 4'd1;
        nonce_ascii_2 = {64'd0, 8'h30 + digit1_2[7:0]};  // "1" até "9"
    end else if (nonce_2 < 100) begin
        nonce_ascii_len_2 = 4'd2;
        nonce_ascii_2 = {56'd0, 8'h30 + digit2_2[7:0], 8'h30 + digit1_2[7:0]};  // "10" até "99"
    end else if (nonce_2 < 1000) begin
        nonce_ascii_len_2 = 4'd3;
        nonce_ascii_2 = {48'd0, 8'h30 + digit3_2[7:0], 8'h30 + digit2_2[7:0], 8'h30 + digit1_2[7:0]};  // "100" até "999"
    end else if (nonce_2 < 10000) begin
        nonce_ascii_len_2 = 4'd4;
        nonce_ascii_2 = {40'd0, 8'h30 + digit4_2[7:0], 8'h30 + digit3_2[7:0], 8'h30 + digit2_2[7:0], 8'h30 + digit1_2[7:0]};  // "1000" até "9999"
    end else if (nonce_2 < 100000) begin
        nonce_ascii_len_2 = 4'd5;
        nonce_ascii_2 = {32'd0, 8'h30 + digit5_2[7:0], 8'h30 + digit4_2[7:0], 8'h30 + digit3_2[7:0], 8'h30 + digit2_2[7:0], 8'h30 + digit1_2[7:0]};   // "10000" até "99999"
    end else if (nonce_2 < 1000000) begin
        nonce_ascii_len_2 = 4'd6;
        nonce_ascii_2 = {24'd0, 8'h30 + digit6_2[7:0], 8'h30 + digit5_2[7:0], 8'h30 + digit4_2[7:0], 8'h30 + digit3_2[7:0], 8'h30 + digit2_2[7:0], 8'h30 + digit1_2[7:0]};    // "100000" até "999999"
    end else if (nonce_2 < 10000000) begin
        nonce_ascii_len_2 = 4'd7;
        nonce_ascii_2 = {16'd0, 8'h30 + digit7_2[7:0], 8'h30 + digit6_2[7:0], 8'h30 + digit5_2[7:0], 8'h30 + digit4_2[7:0], 8'h30 + digit3_2[7:0], 8'h30 + digit2_2[7:0], 8'h30 + digit1_2[7:0]};   // "1000000" até "9999999"
    end else if (nonce_2 < 100000000) begin
        nonce_ascii_len_2 = 4'd8;
        nonce_ascii_2 = {8'd0, 8'h30 + digit8_2[7:0], 8'h30 + digit7_2[7:0], 8'h30 + digit6_2[7:0], 8'h30 + digit5_2[7:0], 8'h30 + digit4_2[7:0], 8'h30 + digit3_2[7:0], 8'h30 + digit2_2[7:0], 8'h30 + digit1_2[7:0]};   // "10000000" até "99999999"
    end else begin
        nonce_ascii_len_2 = 4'd9;
        nonce_ascii_2 = {8'h30 + digit9_2[7:0], 8'h30 + digit8_2[7:0], 8'h30 + digit7_2[7:0], 8'h30 + digit6_2[7:0], 8'h30 + digit5_2[7:0], 8'h30 + digit4_2[7:0], 8'h30 + digit3_2[7:0], 8'h30 + digit2_2[7:0], 8'h30 + digit1_2[7:0]};   // "100000000" até "999999999"
    end
    
    // ========================================
    // PASSO 6: Construir MESSAGE_BLOCK_2 com nonce_2
    // Total de dados: 40 (mensagem) + nonce_ascii_len_2 bytes
    // ========================================
    case (nonce_ascii_len_2)
        3'd1: begin
            // 40 + 1 = 41 bytes de dados
            // Comprimento da mensagem: 41 * 8 = 328 bits = 0x0148
            MESSAGE_BLOCK_2 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_2[7:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h48
            };
        end
        3'd2: begin
            // 40 + 2 = 42 bytes de dados
            // Comprimento da mensagem: 42 * 8 = 336 bits = 0x0150
            MESSAGE_BLOCK_2 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_2[15:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00,
                8'h01, 8'h50
            };
        end
        3'd3: begin
            // 40 + 3 = 43 bytes de dados
            // Comprimento da mensagem: 43 * 8 = 344 bits = 0x0158
            MESSAGE_BLOCK_2 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_2[23:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00,
                8'h01, 8'h58
            };
        end
        3'd4: begin
            // 40 + 4 = 44 bytes de dados
            // Comprimento da mensagem: 44 * 8 = 352 bits = 0x0160
            MESSAGE_BLOCK_2 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_2[31:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00,
                8'h01, 8'h60
            };
        end
        3'd5: begin
            // 40 + 5 = 45 bytes de dados
            // Comprimento da mensagem: 45 * 8 = 360 bits = 0x0168
            MESSAGE_BLOCK_2 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_2[39:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h68
            };
        end
        3'd6: begin
            // 40 + 6 = 46 bytes de dados
            // Comprimento da mensagem: 46 * 8 = 368 bits = 0x0170
            MESSAGE_BLOCK_2 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_2[47:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h70
            };
        end
        3'd7: begin
            // 40 + 7 = 47 bytes de dados
            // Comprimento da mensagem: 47 * 8 = 376 bits = 0x0178
            MESSAGE_BLOCK_2 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_2[55:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h78
            };
        end
        4'd8: begin
            // 40 + 8 = 48 bytes de dados
            // Comprimento da mensagem: 48 * 8 = 384 bits = 0x0180
            MESSAGE_BLOCK_2 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_2[63:0],  // Todos os 8 bytes
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h80
            };
        end
        4'd9: begin
            // 40 + 9 = 49 bytes de dados
            // Comprimento da mensagem: 49 * 8 = 392 bits = 0x0188
            MESSAGE_BLOCK_2 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_2[71:0],  // Todos os 9 bytes (72 bits = 9 bytes)
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00,
                8'h01, 8'h88
            };
        end
        default: begin
            // Fallback para valores não cobertos (segurança: evita latch)
            MESSAGE_BLOCK_2 = 512'd0;
        end
    endcase

    // ========================================
    // PASSO 7: Computar ASCII para nonce_3 (nonce_2 + 1) - COMBINACIONAL
    // ========================================
    // Nota: nonce_3 = nonce_2 + 1, então seus dígitos são derivados de digit*_3
    if (nonce_3 == 0) begin
        nonce_ascii_len_3 = 4'd1;
        nonce_ascii_3 = {64'd0, 8'h30};  // "0"
    end else if (nonce_3 < 10) begin
        nonce_ascii_len_3 = 4'd1;
        nonce_ascii_3 = {64'd0, 8'h30 + digit1_3[7:0]};  // "1" até "9"
    end else if (nonce_3 < 100) begin
        nonce_ascii_len_3 = 4'd2;
        nonce_ascii_3 = {56'd0, 8'h30 + digit2_3[7:0], 8'h30 + digit1_3[7:0]};  // "10" até "99"
    end else if (nonce_3 < 1000) begin
        nonce_ascii_len_3 = 4'd3;
        nonce_ascii_3 = {48'd0, 8'h30 + digit3_3[7:0], 8'h30 + digit2_3[7:0], 8'h30 + digit1_3[7:0]};  // "100" até "999"
    end else if (nonce_3 < 10000) begin
        nonce_ascii_len_3 = 4'd4;
        nonce_ascii_3 = {40'd0, 8'h30 + digit4_3[7:0], 8'h30 + digit3_3[7:0], 8'h30 + digit2_3[7:0], 8'h30 + digit1_3[7:0]};  // "1000" até "9999"
    end else if (nonce_3 < 100000) begin
        nonce_ascii_len_3 = 4'd5;
        nonce_ascii_3 = {32'd0, 8'h30 + digit5_3[7:0], 8'h30 + digit4_3[7:0], 8'h30 + digit3_3[7:0], 8'h30 + digit2_3[7:0], 8'h30 + digit1_3[7:0]};   // "10000" até "99999"
    end else if (nonce_3 < 1000000) begin
        nonce_ascii_len_3 = 4'd6;
        nonce_ascii_3 = {24'd0, 8'h30 + digit6_3[7:0], 8'h30 + digit5_3[7:0], 8'h30 + digit4_3[7:0], 8'h30 + digit3_3[7:0], 8'h30 + digit2_3[7:0], 8'h30 + digit1_3[7:0]};    // "100000" até "999999"
    end else if (nonce_3 < 10000000) begin
        nonce_ascii_len_3 = 4'd7;
        nonce_ascii_3 = {16'd0, 8'h30 + digit7_3[7:0], 8'h30 + digit6_3[7:0], 8'h30 + digit5_3[7:0], 8'h30 + digit4_3[7:0], 8'h30 + digit3_3[7:0], 8'h30 + digit2_3[7:0], 8'h30 + digit1_3[7:0]};   // "1000000" até "9999999"
    end else if (nonce_3 < 100000000) begin
        nonce_ascii_len_3 = 4'd8;
        nonce_ascii_3 = {8'd0, 8'h30 + digit8_3[7:0], 8'h30 + digit7_3[7:0], 8'h30 + digit6_3[7:0], 8'h30 + digit5_3[7:0], 8'h30 + digit4_3[7:0], 8'h30 + digit3_3[7:0], 8'h30 + digit2_3[7:0], 8'h30 + digit1_3[7:0]};   // "10000000" até "99999999"
    end else begin
        nonce_ascii_len_3 = 4'd9;
        nonce_ascii_3 = {8'h30 + digit9_3[7:0], 8'h30 + digit8_3[7:0], 8'h30 + digit7_3[7:0], 8'h30 + digit6_3[7:0], 8'h30 + digit5_3[7:0], 8'h30 + digit4_3[7:0], 8'h30 + digit3_3[7:0], 8'h30 + digit2_3[7:0], 8'h30 + digit1_3[7:0]};   // "100000000" até "999999999"
    end
    
    // ========================================
    // PASSO 4: Construir MESSAGE_BLOCK_3 com nonce_3
    // Total de dados: 40 (mensagem) + nonce_ascii_len_3 bytes
    // ========================================
    case (nonce_ascii_len_3)
        3'd1: begin
            // 40 + 1 = 41 bytes de dados
            // Comprimento da mensagem: 41 * 8 = 328 bits = 0x0148
            MESSAGE_BLOCK_3 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_3[7:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h48
            };
        end
        3'd2: begin
            // 40 + 2 = 42 bytes de dados
            // Comprimento da mensagem: 42 * 8 = 336 bits = 0x0150
            MESSAGE_BLOCK_3 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_3[15:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00,
                8'h01, 8'h50
            };
        end
        3'd3: begin
            // 40 + 3 = 43 bytes de dados
            // Comprimento da mensagem: 43 * 8 = 344 bits = 0x0158
            MESSAGE_BLOCK_3 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_3[23:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00,
                8'h01, 8'h58
            };
        end
        3'd4: begin
            // 40 + 4 = 44 bytes de dados
            // Comprimento da mensagem: 44 * 8 = 352 bits = 0x0160
            MESSAGE_BLOCK_3 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_3[31:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00,
                8'h01, 8'h60
            };
        end
        3'd5: begin
            // 40 + 5 = 45 bytes de dados
            // Comprimento da mensagem: 45 * 8 = 360 bits = 0x0168
            MESSAGE_BLOCK_3 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_3[39:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h68
            };
        end
        3'd6: begin
            // 40 + 6 = 46 bytes de dados
            // Comprimento da mensagem: 46 * 8 = 368 bits = 0x0170
            MESSAGE_BLOCK_3 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_3[47:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h70
            };
        end
        3'd7: begin
            // 40 + 7 = 47 bytes de dados
            // Comprimento da mensagem: 47 * 8 = 376 bits = 0x0178
            MESSAGE_BLOCK_3 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_3[55:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h78
            };
        end
        4'd8: begin
            // 40 + 8 = 48 bytes de dados
            // Comprimento da mensagem: 48 * 8 = 384 bits = 0x0180
            MESSAGE_BLOCK_3 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_3[63:0],  // Todos os 8 bytes
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h80
            };
        end
        4'd9: begin
            // 40 + 9 = 49 bytes de dados
            // Comprimento da mensagem: 49 * 8 = 392 bits = 0x0188
            MESSAGE_BLOCK_3 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii_3[71:0],  // Todos os 9 bytes (72 bits = 9 bytes)
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00,
                8'h01, 8'h88
            };
        end
        default: begin
            // Fallback para valores não cobertos (segurança: evita latch)
            MESSAGE_BLOCK_3 = 512'd0;
        end
    endcase

    
    // SHA1_EXPECTED: Decodifica 40 caracteres ASCII hexadecimais de buffer[40..79] em hash binário de 160 bits
    // Conversão: cada par de caracteres ASCII hex [2n, 2n+1] torna-se um byte binário
    // Exemplo: ASCII '48' -> 0x48, 'a3' -> 0xa3, etc. (suporta maiúsculas e minúsculas)
    SHA1_EXPECTED = {
        // Bytes 0-19: Decodifica pares hex de índices de buffer 40-79
        (buffer[40] >= 8'h61 ? buffer[40] - 8'h57 : buffer[40] - 8'h30) << 4 | 
        (buffer[41] >= 8'h61 ? buffer[41] - 8'h57 : buffer[41] - 8'h30),
        (buffer[42] >= 8'h61 ? buffer[42] - 8'h57 : buffer[42] - 8'h30) << 4 | 
        (buffer[43] >= 8'h61 ? buffer[43] - 8'h57 : buffer[43] - 8'h30),
        (buffer[44] >= 8'h61 ? buffer[44] - 8'h57 : buffer[44] - 8'h30) << 4 | 
        (buffer[45] >= 8'h61 ? buffer[45] - 8'h57 : buffer[45] - 8'h30),
        (buffer[46] >= 8'h61 ? buffer[46] - 8'h57 : buffer[46] - 8'h30) << 4 | 
        (buffer[47] >= 8'h61 ? buffer[47] - 8'h57 : buffer[47] - 8'h30),
        (buffer[48] >= 8'h61 ? buffer[48] - 8'h57 : buffer[48] - 8'h30) << 4 | 
        (buffer[49] >= 8'h61 ? buffer[49] - 8'h57 : buffer[49] - 8'h30),
        (buffer[50] >= 8'h61 ? buffer[50] - 8'h57 : buffer[50] - 8'h30) << 4 | 
        (buffer[51] >= 8'h61 ? buffer[51] - 8'h57 : buffer[51] - 8'h30),
        (buffer[52] >= 8'h61 ? buffer[52] - 8'h57 : buffer[52] - 8'h30) << 4 | 
        (buffer[53] >= 8'h61 ? buffer[53] - 8'h57 : buffer[53] - 8'h30),
        (buffer[54] >= 8'h61 ? buffer[54] - 8'h57 : buffer[54] - 8'h30) << 4 | 
        (buffer[55] >= 8'h61 ? buffer[55] - 8'h57 : buffer[55] - 8'h30),
        (buffer[56] >= 8'h61 ? buffer[56] - 8'h57 : buffer[56] - 8'h30) << 4 | 
        (buffer[57] >= 8'h61 ? buffer[57] - 8'h57 : buffer[57] - 8'h30),
        (buffer[58] >= 8'h61 ? buffer[58] - 8'h57 : buffer[58] - 8'h30) << 4 | 
        (buffer[59] >= 8'h61 ? buffer[59] - 8'h57 : buffer[59] - 8'h30),
        (buffer[60] >= 8'h61 ? buffer[60] - 8'h57 : buffer[60] - 8'h30) << 4 | 
        (buffer[61] >= 8'h61 ? buffer[61] - 8'h57 : buffer[61] - 8'h30),
        (buffer[62] >= 8'h61 ? buffer[62] - 8'h57 : buffer[62] - 8'h30) << 4 | 
        (buffer[63] >= 8'h61 ? buffer[63] - 8'h57 : buffer[63] - 8'h30),
        (buffer[64] >= 8'h61 ? buffer[64] - 8'h57 : buffer[64] - 8'h30) << 4 | 
        (buffer[65] >= 8'h61 ? buffer[65] - 8'h57 : buffer[65] - 8'h30),
        (buffer[66] >= 8'h61 ? buffer[66] - 8'h57 : buffer[66] - 8'h30) << 4 | 
        (buffer[67] >= 8'h61 ? buffer[67] - 8'h57 : buffer[67] - 8'h30),
        (buffer[68] >= 8'h61 ? buffer[68] - 8'h57 : buffer[68] - 8'h30) << 4 | 
        (buffer[69] >= 8'h61 ? buffer[69] - 8'h57 : buffer[69] - 8'h30),
        (buffer[70] >= 8'h61 ? buffer[70] - 8'h57 : buffer[70] - 8'h30) << 4 | 
        (buffer[71] >= 8'h61 ? buffer[71] - 8'h57 : buffer[71] - 8'h30),
        (buffer[72] >= 8'h61 ? buffer[72] - 8'h57 : buffer[72] - 8'h30) << 4 | 
        (buffer[73] >= 8'h61 ? buffer[73] - 8'h57 : buffer[73] - 8'h30),
        (buffer[74] >= 8'h61 ? buffer[74] - 8'h57 : buffer[74] - 8'h30) << 4 | 
        (buffer[75] >= 8'h61 ? buffer[75] - 8'h57 : buffer[75] - 8'h30),
        (buffer[76] >= 8'h61 ? buffer[76] - 8'h57 : buffer[76] - 8'h30) << 4 | 
        (buffer[77] >= 8'h61 ? buffer[77] - 8'h57 : buffer[77] - 8'h30),
        (buffer[78] >= 8'h61 ? buffer[78] - 8'h57 : buffer[78] - 8'h30) << 4 | 
        (buffer[79] >= 8'h61 ? buffer[79] - 8'h57 : buffer[79] - 8'h30)
    };
    
end

// Sinais de computação SHA-1 (QUAD-CORE)
reg [27:0] clock_counter;     // Contador de temporização da máquina de estados

// ========== REGISTRADORES DE RESULTADO PARA SHA1_CORE_0 ==========
reg [159:0] sha1_digest_0;        // Resultado do resumo SHA-1 computado para nonce_0
reg sha1_digest_0_valid;          // flag: computação SHA-1 completa para nonce_0

// ========== REGISTRADORES DE RESULTADO PARA SHA1_CORE_1 ==========
reg [159:0] sha1_digest_1;        // Resultado do resumo SHA-1 computado para nonce_1
reg sha1_digest_1_valid;          // flag: computação SHA-1 completa para nonce_1

// ========== REGISTRADORES DE RESULTADO PARA SHA1_CORE_2 ==========
reg [159:0] sha1_digest_2;        // Resultado do resumo SHA-1 computado para nonce_2
reg sha1_digest_2_valid;          // flag: computação SHA-1 completa para nonce_2

// ========== REGISTRADORES DE RESULTADO PARA SHA1_CORE_3 ==========
reg [159:0] sha1_digest_3;        // Resultado do resumo SHA-1 computado para nonce_3
reg sha1_digest_3_valid;          // flag: computação SHA-1 completa para nonce_3

// ========== SINAIS PARA SHA1_CORE_0 ==========
wire sha1_core_0_ready;           // Sinal: núcleo SHA-1 pronto (pode aceitar nova computação)
wire [159:0] sha1_core_0_digest;  // Resumo de saída do núcleo SHA-1 (160 bits)
wire sha1_core_0_digest_valid;    // flag: conclusão do núcleo SHA-1

reg sha1_0_init;                  // Sinal pulsado: dispara inicialização do núcleo SHA-1
reg sha1_0_next;                  // Sinal pulsado: dispara processamento do próximo bloco

// ========== SINAIS PARA SHA1_CORE_1 ==========
wire sha1_core_1_ready;           // Sinal: núcleo SHA-1 pronto (pode aceitar nova computação)
wire [159:0] sha1_core_1_digest;  // Resumo de saída do núcleo SHA-1 (160 bits)
wire sha1_core_1_digest_valid;    // flag: conclusão do núcleo SHA-1

reg sha1_1_init;                  // Sinal pulsado: dispara inicialização do núcleo SHA-1
reg sha1_1_next;                  // Sinal pulsado: dispara processamento do próximo bloco

// ========== SINAIS PARA SHA1_CORE_2 ==========
wire sha1_core_2_ready;           // Sinal: núcleo SHA-1 pronto (pode aceitar nova computação)
wire [159:0] sha1_core_2_digest;  // Resumo de saída do núcleo SHA-1 (160 bits)
wire sha1_core_2_digest_valid;    // flag: conclusão do núcleo SHA-1

reg sha1_2_init;                  // Sinal pulsado: dispara inicialização do núcleo SHA-1
reg sha1_2_next;                  // Sinal pulsado: dispara processamento do próximo bloco

// ========== SINAIS PARA SHA1_CORE_3 ==========
wire sha1_core_3_ready;           // Sinal: núcleo SHA-1 pronto (pode aceitar nova computação)
wire [159:0] sha1_core_3_digest;  // Resumo de saída do núcleo SHA-1 (160 bits)
wire sha1_core_3_digest_valid;    // flag: conclusão do núcleo SHA-1

reg sha1_3_init;                  // Sinal pulsado: dispara inicialização do núcleo SHA-1
reg sha1_3_next;                  // Sinal pulsado: dispara processamento do próximo bloco

// Sinais de controle geral
wire sha1_start;                  // Sinal de início: ativado quando buffer UART está cheio (estado BUFFER_FULL)
wire uart_tx_done_signal;         // Sinal de conclusão: ativado quando transmissão UART termina (estado UART_TX_DONE)

reg led_output;           // Saída LED: status de correspondência SHA-1
reg led_sha1_work_output;     // Saída LED: processamento SHA-1 ativo
reg led_sha1_finish_output;   // Saída LED: computação SHA-1 finalizada
reg led_uart_work_output;     // Saída LED: transmissão UART em andamento
reg led_uart_finish_output;   // Saída LED: transmissão UART finalizada

reg [27:0] blink_counter;    // Contador de pisca para LED

// Máquina de estados SHA-1: implementa proof-of-work com iteração de nonce
// Estados: RESET → IDLE → INIT_SHA1 → RUNNING → DONE_WAIT → RESULT
// Em RESULT: se hash corresponde, transmite nonce; caso contrário, incrementa e tenta novamente
reg [2:0] state;
localparam STATE_RESET      = 3'b000;  // Inicializar: reinicia todos os contadores
localparam STATE_IDLE       = 3'b001;  // Aguardar: núcleo SHA-1 pronto E buffer UART cheio
localparam STATE_INIT_SHA1  = 3'b010;  // Inicializar núcleo SHA-1 com MESSAGE_BLOCK
localparam STATE_RUNNING    = 3'b011;  // Atraso: aguardar conclusão do núcleo SHA-1 (~1 segundo)
localparam STATE_DONE_WAIT  = 3'b100;  // Pesquisar: aguardar flag digest_valid SHA-1
localparam STATE_RESULT     = 3'b101;  // Verificar: se correspondência encontrada, sinaliza TX UART; caso contrário incrementa nonce e tenta novamente

// Sinais de recepção UART
wire [7:0] rx_data;        // Byte de dados recebido
wire rx_data_valid;       // flag de dados válidos RX
reg rx_data_ready = 1'b1; // flag RX pronto

// Sinais de transmissão UART
reg [7:0] tx_data;       // Byte de dados a transmitir
reg tx_data_valid;      // flag de dados válidos TX
wire tx_data_ready;    // flag TX pronto

wire rst_n = !rst;  // Converte reset para convenção ativo-baixo para núcleos IP

// Saídas LED: invertidas porque LEDs estão em ativo-baixo
assign led = ~led_output;                     // LED: hash SHA-1 computado corresponde ao valor esperado
assign led_sha1_work = ~led_sha1_work_output;   // LED: computação SHA-1 em progresso (pisca 1 segundo)
assign led_sha1_finish = ~led_sha1_finish_output;  // LED: computação SHA-1 finalizada (pisca 0.5 segundo)
assign led_uart_work = ~led_uart_work_output;  // LED: transmissão UART em progresso (pisca 1 segundo)
assign led_uart_finish = ~led_uart_finish_output;  // LED: transmissão UART finalizada (pisca 0.5 segundo)

// ========================================
// INSTANCIAÇÃO DOS 2 CORES SHA-1
// ========================================

// ========== SHA1_CORE_0: Processa nonce_0 (nonce par) ==========
// Conecta MESSAGE_BLOCK_0 com sinais de controle sha1_0_*
sha1_core sha1_inst_0(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_0_init),         // Sinal pulsado para inicializar
    .next(sha1_0_next),         // Sinal pulsado para processar
    .block(MESSAGE_BLOCK_0),    // Bloco de mensagem com nonce_0
    .ready(sha1_core_0_ready),  // Flag: core pronto
    .digest(sha1_core_0_digest),  // Resultado SHA-1 (160 bits)
    .digest_valid(sha1_core_0_digest_valid)  // Flag: resultado válido
);

// ========== SHA1_CORE_1: Processa nonce_1 (nonce ímpar) ==========
// Conecta MESSAGE_BLOCK_1 com sinais de controle sha1_1_*
sha1_core sha1_inst_1(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_1_init),         // Sinal pulsado para inicializar
    .next(sha1_1_next),         // Sinal pulsado para processar
    .block(MESSAGE_BLOCK_1),    // Bloco de mensagem com nonce_1
    .ready(sha1_core_1_ready),  // Flag: core pronto
    .digest(sha1_core_1_digest),  // Resultado SHA-1 (160 bits)
    .digest_valid(sha1_core_1_digest_valid)  // Flag: resultado válido
);

// ========== SHA1_CORE_2: Processa nonce_2 (nonce ímpar) ==========
// Conecta MESSAGE_BLOCK_2 com sinais de controle sha1_2_*
sha1_core sha1_inst_2(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_2_init),         // Sinal pulsado para inicializar
    .next(sha1_2_next),         // Sinal pulsado para processar
    .block(MESSAGE_BLOCK_2),    // Bloco de mensagem com nonce_2
    .ready(sha1_core_2_ready),  // Flag: core pronto
    .digest(sha1_core_2_digest),  // Resultado SHA-1 (160 bits)
    .digest_valid(sha1_core_2_digest_valid)  // Flag: resultado válido
);

// ========== SHA1_CORE_3: Processa nonce_3 (nonce ímpar) ==========
// Conecta MESSAGE_BLOCK_3 com sinais de controle sha1_3_*
sha1_core sha1_inst_3(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_3_init),         // Sinal pulsado para inicializar
    .next(sha1_3_next),         // Sinal pulsado para processar
    .block(MESSAGE_BLOCK_3),    // Bloco de mensagem com nonce_3
    .ready(sha1_core_3_ready),  // Flag: core pronto
    .digest(sha1_core_3_digest),  // Resultado SHA-1 (160 bits)
    .digest_valid(sha1_core_3_digest_valid)  // Flag: resultado válido
);

// Recepção UART
uart_rx #(
    .CLK_FRE(CLK_FRE),
    .BAUD_RATE(UART_FRE)
) uart_rx_inst (
    .clk(clk),
    .rst_n(rst_n),
    .rx_data(rx_data),
    .rx_data_valid(rx_data_valid),
    .rx_data_ready(rx_data_ready),
    .rx_pin(uart_rx)
);

// Transmissão UART
uart_tx #(
    .CLK_FRE(CLK_FRE),
    .BAUD_RATE(UART_FRE)
) uart_tx_inst (
    .clk(clk),
    .rst_n(rst_n),
    .tx_data(tx_data),
    .tx_data_valid(tx_data_valid),
    .tx_data_ready(tx_data_ready),
    .tx_pin(uart_tx)
);

// Lógica principal da máquina de estados SHA-1
// Implementa mineração proof-of-work com QUAD-CORE SHA-1
// itera nonce_0 de 4 em 4: processando nonce_0 e nonce_1 e nonce_2 e nonce_3 em paralelo
always @(posedge clk) begin
    // ========== RESET DOS SINAIS DE CONTROLE ==========
    // Estes sinais são pulsados (ativos por 1 ciclo apenas)
    sha1_0_init <= 1'b0;  // Pulso: ativado por um ciclo para disparar inicialização SHA-1 core 0
    sha1_0_next <= 1'b0;  // Pulso: ativado por um ciclo para disparar próximo bloco SHA-1 core 0
    sha1_1_init <= 1'b0;  // Pulso: ativado por um ciclo para disparar inicialização SHA-1 core 1
    sha1_1_next <= 1'b0;  // Pulso: ativado por um ciclo para disparar próximo bloco SHA-1 core 1
    sha1_2_init <= 1'b0;  // Pulso: ativado por um ciclo para disparar inicialização SHA-1 core 2
    sha1_2_next <= 1'b0;  // Pulso: ativado por um ciclo para disparar próximo bloco SHA-1 core 2
    sha1_3_init <= 1'b0;  // Pulso: ativado por um ciclo para disparar inicialização SHA-1 core 3
    sha1_3_next <= 1'b0;  // Pulso: ativado por um ciclo para disparar próximo bloco SHA-1 core 3

    case (state)
STATE_RESET: begin
    // ========== INICIALIZAÇÃO: RESET GERAL ==========
    // Reinicia todos os contadores e saídas
    led_output <= 1'b0;
    led_sha1_work_output <= 1'b0;
    led_sha1_finish_output <= 1'b0;
    clock_counter <= 28'd0;
    nonce_0 <= 32'd0;  // Reinicia nonce_0 para 0 na inicialização

    // Aguarda 5 ciclos de relógio para estabilização do sistema
    if (clock_counter >= 28'd5) begin
        clock_counter <= 28'd0;
        state <= STATE_IDLE;
    end else begin
        clock_counter <= clock_counter + 1'b1;
    end
end

STATE_IDLE: begin
    // ========== AGUARDAR QUAD-CORE PRONTO + BUFFER CHEIO ==========
    // Reinicia nonce_0 quando transmissão UART completa (prepara para próxima mensagem)
    if (uart_tx_done_signal) begin
        nonce_0 <= 32'd0;
    end
    
    // ========== INCREMENTAR NONCE_0 (ESTRATÉGIA QUAD-CORE) ==========
    // Primeiro incremento: disparado por sha1_start e flag nonce_increment_done
    // Garante que nonce_0 incrementa exatamente uma vez por buffer de mensagem
    // Incrementa de +4 para processar nonce_0 e nonce_1 e nonce_2 e nonce_3 em paralelo
    if (sha1_start && !nonce_increment_done) begin
        if (nonce_0 < DIFFICULTY - 4) begin  // Garante espaço para nonce_1 = nonce_0 + 1
            nonce_0 <= nonce_0 + 32'd4;  // INCREMENTA +4 (em vez de +1)
        end else begin
            nonce_0 <= 32'd0;  // Reinicia para 0 após atingir dificuldade máxima
        end
        nonce_increment_done <= 1'b1;  // Define flag para prevenir incrementos redundantes
    end
    
    // ========== TRANSIÇÃO PARA INIT_SHA1 ==========
    // Condição: AMBOS cores prontos AND buffer cheio AND nonce já incrementado
    if ((sha1_core_0_ready && sha1_core_1_ready && sha1_core_2_ready && sha1_core_3_ready) && sha1_start && nonce_increment_done) begin
        state <= STATE_INIT_SHA1;
        clock_counter <= 28'd0;
    end
end

STATE_INIT_SHA1: begin
    // ========== DISPARAR AMBOS OS CORES SHA-1 ==========
    // Inicializa simultaneamente:
    // - sha1_core_0 com MESSAGE_BLOCK_0 (nonce_0)
    // - sha1_core_1 com MESSAGE_BLOCK_1 (nonce_1 = nonce_0 + 1)
    // - sha1_core_2 com MESSAGE_BLOCK_2 (nonce_2 = nonce_1 + 1)
    // - sha1_core_3 com MESSAGE_BLOCK_3 (nonce_3 = nonce_2 + 1)
    led_sha1_work_output <= 1'b1;  // LED: indica que processamento começou
    
    sha1_0_init <= 1'b1;  // Pulso: dispara CORE 0 por um ciclo
    sha1_1_init <= 1'b1;  // Pulso: dispara CORE 1 por um ciclo (AMBOS ao mesmo tempo!)
    sha1_2_init <= 1'b1;  // Pulso: dispara CORE 2 por um ciclo (AMBOS ao mesmo tempo!)
    sha1_3_init <= 1'b1;  // Pulso: dispara CORE 3 por um ciclo (AMBOS ao mesmo tempo!)
    
    state <= STATE_RUNNING;
    clock_counter <= 28'd0;
end

STATE_RUNNING: begin
             // Aguarda conclusão do núcleo SHA-1 contador atinge ~185 ns, mas SHA-1 normalmente completa neste intervalo
             if (clock_counter >= 28'd5) begin
                 state <= STATE_DONE_WAIT;
                 clock_counter <= 28'd0;
             end else begin
                 clock_counter <= clock_counter + 1'b1;
             end
         end

STATE_DONE_WAIT: begin
    // ========== AGUARDAR AMBOS OS CORES COMPLETAREM ==========
    // Pesquisa sinais válidos de resumo SHA-1 (ambos resultados prontos)
    // Quando AMBOS os cores terminam, captura os resultados
    if (sha1_core_0_digest_valid && sha1_core_1_digest_valid && sha1_core_2_digest_valid && sha1_core_3_digest_valid) begin
        sha1_digest_0 <= sha1_core_0_digest;  // Captura resultado de nonce_0
        sha1_digest_0_valid <= 1'b1;
        sha1_digest_1 <= sha1_core_1_digest;  // Captura resultado de nonce_1
        sha1_digest_1_valid <= 1'b1;
        sha1_digest_2 <= sha1_core_2_digest;  // Captura resultado de nonce_2
        sha1_digest_2_valid <= 1'b1;
        sha1_digest_3 <= sha1_core_3_digest;  // Captura resultado de nonce_3
        sha1_digest_3_valid <= 1'b1;

        clock_counter <= 28'd0;
        state <= STATE_RESULT;
    end
end

STATE_RESULT: begin
    // ========== VERIFICAR QUAD-CORE: MATCH EM NONCE_0 OU NONCE_1 OU NONCE_2 OU NONCE_3 ==========
    // Lógica: Verifica se SHA1(msg) correspondem ao esperado
    // Ou se atingimos limite de dificuldade (nonce_0 >= DIFFICULTY-1, o que faria nonce_1, nonce_2 e nonce_3 >= DIFFICULTY)
    //        ************************************** MATCH ************************************** 
    if ((sha1_digest_0 == SHA1_EXPECTED) || 
        (sha1_digest_1 == SHA1_EXPECTED) || 
        (sha1_digest_2 == SHA1_EXPECTED) || 
        (sha1_digest_3 == SHA1_EXPECTED) || 
        (nonce_0 >= DIFFICULTY - 4)) begin
        // ========== CORRESPONDÊNCIA ENCONTRADA OU DIFICULDADE ATINGIDA ==========
        led_output <= 1'b1;  // LED: correspondência encontrada!
        led_sha1_work_output <= 1'b0;  // Desativa indicador de trabalho
        
        // ========== AGUARDAR AMBOS OS CORES PRONTOS ANTES DE RETORNAR À IDLE ==========
        if (sha1_core_0_ready && sha1_core_1_ready && sha1_core_2_ready && sha1_core_3_ready) begin
            state <= STATE_IDLE;
            clock_counter <= 28'd0;
            led_sha1_finish_output <= 1'b0;
            sha1_digest_0_valid <= 1'b0;
            sha1_digest_1_valid <= 1'b0;
            sha1_digest_2_valid <= 1'b0;
            sha1_digest_3_valid <= 1'b0;

            nonce_increment_done <= 1'b0;  // Reinicia flag para próximo buffer de mensagem
        end else begin
            // Pisca LED enquanto aguarda cores ficarem prontos
            if (clock_counter >= 28'd5) begin
                clock_counter <= 28'd0;
                led_sha1_finish_output <= ~led_sha1_finish_output;  // Alterna LED
            end else begin
                clock_counter <= clock_counter + 1'b1;
            end
        end
    end else begin
        // ========== SEM CORRESPONDÊNCIA: INCREMENTA NONCE E TENTA NOVAMENTE ==========
        led_output <= 1'b0;
        
        // Sem correspondência: incrementa nonce_0 em +4 para próxima tentativa
        // e recalcula SHA-1 para ambos os nonces
        if (sha1_core_0_ready && sha1_core_1_ready && sha1_core_2_ready && sha1_core_3_ready) begin
            // Incrementa nonce_0 em +4 (para processar próximo par de nonces)
            if (nonce_0 < DIFFICULTY - 1) begin
                nonce_0 <= nonce_0 + 32'd4;
            end else begin
                nonce_0 <= 32'd0;  // Reinicia para 0 após atingir dificuldade máxima
            end
            
            state <= STATE_INIT_SHA1;  // Volta ao init para próxima iteração
            clock_counter <= 28'd0;

            sha1_digest_0_valid <= 1'b0;  // Limpa para próxima computação
            sha1_digest_1_valid <= 1'b0;  // Limpa para próxima computação
            sha1_digest_2_valid <= 1'b0;  // Limpa para próxima computação
            sha1_digest_3_valid <= 1'b0;  // Limpa para próxima computação

            led_sha1_work_output <= ~led_sha1_work_output;  // Reativa LED indicador de trabalho
        end
    end
end

default: begin
            state <= STATE_RESET;
        end
    endcase
end

// Máquina de Estados de Recepção e Transmissão UART
// ===================================================
// Implementa buffering de 80 bytes: 40 bytes de mensagem + 40 bytes de hash ASCII hex
// Recebe buffer completo, então dispara computação SHA-1
// Ao encontrar correspondência, transmite resultado de nonce de 4 bytes
// Estrutura: buffer[0..39] = mensagem, buffer[40..79] = hash esperado

// Constante de tamanho de buffer
localparam BUFFER_SIZE = 80;  // Total: 40 bytes de mensagem + 40 bytes de hash ASCII

// Estados da máquina de estados UART
localparam UART_IDLE         = 2'd0;  // Acumulando bytes no buffer
localparam UART_BUFFER_FULL  = 2'd1;  // Buffer completo, pronto para computação SHA-1
localparam UART_TRANSMIT_NONCE = 2'd2; // Transmitindo resultado de nonce (4 bytes = 32 bits)
localparam UART_TX_DONE      = 2'd3;  // Transmissão completa

// Sinais combinacionais para controle baseado em estado
// Sinal: início SHA-1 (ativado quando buffer UART está cheio)
// Isso notifica a máquina de estados SHA-1 que nova mensagem está pronta
assign sha1_start = (uart_state == UART_BUFFER_FULL) ? 1'b1 : 1'b0;

// Sinal: transmissão UART completa (ativado quando transmissão termina)
// Notifica a máquina de estados SHA-1 para reiniciar nonce para próxima mensagem
assign uart_tx_done_signal = (uart_state == UART_TX_DONE) ? 1'b1 : 1'b0;

// Registradores da máquina de estados UART
reg [1:0] uart_state;           // Estado atual

// Buffer de recepção dinâmico
reg [7:0] buffer [0:BUFFER_SIZE-1];  // Buffer de 80 bytes: [0..39] mensagem, [40..79] hash

reg [6:0] byte_count;           // Contador de recepção: 0 a 80 (necessita 7 bits)
reg [4:0] tx_index;             // Índice de transmissão: 0 a 3 para 4 bytes de nonce (necessita 5 bits)
reg nonce_increment_done;       // flag: garante que nonce incrementa exatamente uma vez por buffer

// Registrador para armazenar qual nonce transmitir (nonce_0 ou nonce_1 ou nonce_2 ou nonce_3)
reg [31:0] nonce_to_transmit;  // Armazena nonce a ser transmitido (nonce_0 ou nonce_1 ou nonce_2 ou nonce_3)

// Detector de borda de subida: detecta chegada de novo byte UART
reg rx_valid_reg1;
reg rx_valid_reg2;
wire rx_new_byte = rx_valid_reg1 && !rx_valid_reg2;

// Máquina de estados UART: manipula recepção de mensagem e transmissão de resultado
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
         // Reinicia: inicializa todas as variáveis de estado UART
         uart_state <= UART_IDLE;
         byte_count <= 7'd0;  // Começa em 0 (suporta até 80)
         tx_index <= 5'd0;    // Começa em 0 (transmite 4 bytes: índices 0-3)
         tx_data <= 8'd0;
         tx_data_valid <= 1'b0;
         rx_valid_reg1 <= 1'b0;
         rx_valid_reg2 <= 1'b0;
         led_uart_work_output <= 1'b0;
         led_uart_finish_output <= 1'b0;
    end else begin
        // Detecção de borda de subida: captura chegada de novo byte UART
        rx_valid_reg1 <= rx_data_valid;
        rx_valid_reg2 <= rx_valid_reg1;

        // Lógica principal da máquina de estados UART
        case (uart_state)
            //------------------------------------------
UART_IDLE: begin
                // Acumula bytes no buffer conforme chegam
                // byte_count rastreia quantos bytes foram recebidos até agora (0 a 80)
                tx_data_valid <= 1'b0;  // Ainda não transmitindo
                led_uart_work_output <= 1'b0;

                // Novo byte chegou: armazena e incrementa contador
                if (rx_new_byte && byte_count < BUFFER_SIZE) begin
                    buffer[byte_count] <= rx_data;      // Armazena no índice atual
                    byte_count <= byte_count + 1'b1;    // Incrementa contador
                    
                     // Transição quando último byte recebido (byte_count atinge 79, incrementará para 80)
                     if (byte_count == BUFFER_SIZE - 1) begin
                         uart_state <= UART_BUFFER_FULL;
                     end
                end
            end

             //------------------------------------------
UART_BUFFER_FULL: begin
    // ========== AGUARDAR RESULTADO DE QUAD-CORE SHA-1 ==========
    // Incremento de nonce_0 acontece na máquina de estados SHA-1 (STATE_IDLE e STATE_RESULT)
    
    // Quando resultado SHA-1 estão prontos, prepara transmissão do nonce correto
    // Transmite nonce_0 se SHA1(msg) == SHA1_EXPECTED
    // Transmite nonce_1 se SHA1(msg) == SHA1_EXPECTED
    // Transmite nonce_2 se SHA1(msg) == SHA1_EXPECTED
    // Transmite nonce_3 se SHA1(msg) == SHA1_EXPECTED
    // Transmite nonce_0 ou nonce_1 ou nonce_2 ou nonce_3 se atingiu dificuldade máxima (>= DIFFICULTY-1)
    
     if ((sha1_digest_0_valid && tx_data_ready && (sha1_digest_0 == SHA1_EXPECTED)) || 
         (sha1_digest_1_valid && tx_data_ready && (sha1_digest_1 == SHA1_EXPECTED)) ||
         (sha1_digest_2_valid && tx_data_ready && (sha1_digest_2 == SHA1_EXPECTED)) ||
         (sha1_digest_3_valid && tx_data_ready && (sha1_digest_3 == SHA1_EXPECTED)) ||
         (nonce_0 >= DIFFICULTY - 1)) begin
         
         // ========== SELECIONAR QUAL NONCE TRANSMITIR ==========
         // Prioridade: nonce_3 (verifica primeiro), depois restante...
         if (sha1_digest_3 == SHA1_EXPECTED) begin
             nonce_to_transmit <= nonce_3;  // Transmite nonce_3 
         end else 
         if (sha1_digest_2 == SHA1_EXPECTED) begin
             nonce_to_transmit <= nonce_2;  // Transmite nonce_2 
         end else 
         if (sha1_digest_1 == SHA1_EXPECTED) begin
             nonce_to_transmit <= nonce_1;  // Transmite nonce_1 
         end else begin
             nonce_to_transmit <= nonce_0;  // Transmite nonce_0 por padrão
         end
        
        // Começa transmissão do resultado de nonce de 4 bytes
        // Byte 0 (MSB): nonce_to_transmit[31:24]
        tx_data <= nonce_to_transmit[31:24];  // Byte 0 - Transmite MSB primeiro (big-endian)
        tx_data_valid <= 1'b1;
        led_uart_work_output <= 1'b1;         // LED: transmissão iniciada
        tx_index <= 5'd0;                     // Começa no índice 0
        uart_state <= UART_TRANSMIT_NONCE;    // Move para estado de transmissão
    end
end

UART_TRANSMIT_NONCE: begin
    // ========== TRANSMITIR 4 BYTES DO NONCE QUAD-CORE ==========
    // Transmite nonce_to_transmit (que contém nonce_0 ou nonce_1)
    // Ordem de transmissão: MSB-primeiro (big-endian) [31:24], [23:16], [15:8], [7:0]
    
    if (tx_data_ready) begin
        if (tx_index < 5'd3) begin
            // Mais bytes de nonce para transmitir: prepara próximo byte
            // Byte 0 já foi enviado; necessário enviar bytes 1, 2, 3
            // tx_index: 0→1→2→3 (4 transições para 4 bytes total)
            tx_index <= tx_index + 1'b1;
            
            // Extrai próximo byte do nonce_to_transmit usando (tx_index + 1)
            case(tx_index + 1'b1)
                5'd1:  tx_data <= nonce_to_transmit[23:16];   // Byte 1
                5'd2:  tx_data <= nonce_to_transmit[15:8];    // Byte 2
                5'd3:  tx_data <= nonce_to_transmit[7:0];     // Byte 3 (LSB)
                default: tx_data <= 8'd0;
            endcase
            
            tx_data_valid <= 1'b1;
        end else begin
            // Todos os 4 bytes de nonce (índices 0-3) transmitidos: finaliza
            tx_data_valid <= 1'b0;
            led_uart_finish_output <= ~led_uart_finish_output;  // Alterna LED
            uart_state <= UART_TX_DONE;
        end
    end
end

             //------------------------------------------
UART_TX_DONE: begin
                  // Transmissão completa: prepara para próxima mensagem
                  // Reinicia byte_count para 0 para receber próximo buffer de mensagem
                  byte_count <= 7'd0;
                  uart_state <= UART_IDLE;
                  // Nota: máquina de estados SHA-1 reinicia nonce quando transmissão UART completa
               end
        endcase
    end
end


endmodule
