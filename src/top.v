// Módulo de topo: computação SHA-1 em FPGA com iteração dinâmica de nonce
// Implementa mineração proof-of-work: recebe mensagem + hash esperado via UART,
// itera nonce de 0 até DIFFICULTY, calculando SHA-1(mensagem||nonce) até encontrar correspondência
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

parameter DIFFICULTY = 9000000; // Valor máximo de nonce para proof-of-work (9.000.000 iterações)

// Mensagem de entrada (dinâmica): 40 bytes recebidos via UART, armazenados em buffer[0..39]
// Hash SHA-1 esperado: 40 caracteres ASCII hexadecimais recebidos via UART, armazenados em buffer[40..79]
// Hash representa 20 bytes binários (160 bits) para comparação SHA-1
reg [159:0] SHA1_EXPECTED;  // Hash SHA-1 esperado (160 bits = 20 bytes, decodificado de buffer[40..79])

// Variável nonce: incrementada de 0 até DIFFICULTY (9.000.000) durante computação
reg [31:0] nonce;  // Nonce de 32 bits (suficiente para valores até 9.000.000)

// Conversão ASCII do nonce: comprimento variável (sem zeros à esquerda)
// Máximo 7 bytes para valores até 9.000.000
// Exemplo: nonce=1     -> nonce_ascii="1"      (1 byte)
//          nonce=12345 -> nonce_ascii="12345"  (5 bytes)
reg [55:0] nonce_ascii;     // Representação ASCII do nonce (56 bits = 7 bytes máximo)
reg [2:0] nonce_ascii_len;  // Comprimento em bytes (1-7)

// Lógica combinacional de extração de dígitos: dígitos decimais derivados do valor do nonce
wire [31:0] digit7 = (nonce / 32'd1000000) % 32'd10;  // 10^6
wire [31:0] digit6 = (nonce / 32'd100000) % 32'd10;   // 10^5
wire [31:0] digit5 = (nonce / 32'd10000) % 32'd10;    // 10^4
wire [31:0] digit4 = (nonce / 32'd1000) % 32'd10;     // 10^3
wire [31:0] digit3 = (nonce / 32'd100) % 32'd10;      // 10^2
wire [31:0] digit2 = (nonce / 32'd10) % 32'd10;       // 10^1
wire [31:0] digit1 = nonce % 32'd10;                  // 10^0

// Bloco de mensagem: bloco de entrada de 512 bits com preenchimento (padrão RFC 3174 SHA-1)
// Estrutura dinâmica:
//   Bytes 0-39:  Mensagem (40 bytes) do buffer UART
//   Bytes 40+:   Nonce ASCII (1-7 bytes, comprimento variável, sem zeros à esquerda)
//   Byte 47+:    0x80 (marcador de preenchimento) + bytes zero + comprimento_mensagem_bits (64-bit big-endian)

reg [511:0] MESSAGE_BLOCK_1;  // Bloco de mensagem SHA-1 de 512 bits

// Lógica combinacional: constrói dinamicamente MESSAGE_BLOCK_1 com nonce de comprimento variável
always @(*) begin
    // Determina comprimento ASCII do nonce e constrói registro nonce_ascii
    if (nonce == 0) begin
        nonce_ascii_len = 3'd1;
        nonce_ascii = {48'd0, 8'h30};  // "0"
    end else if (nonce < 10) begin
        nonce_ascii_len = 3'd1;
        nonce_ascii = {48'd0, 8'h30 + digit1[7:0]};  // "1" até "9"
    end else if (nonce < 100) begin
        nonce_ascii_len = 3'd2;
        nonce_ascii = {40'd0, 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};  // "10" até "99"
    end else if (nonce < 1000) begin
        nonce_ascii_len = 3'd3;
        nonce_ascii = {32'd0, 8'h30 + digit3[7:0], 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};  // "100" até "999"
    end else if (nonce < 10000) begin
        nonce_ascii_len = 3'd4;
        nonce_ascii = {24'd0, 8'h30 + digit4[7:0], 8'h30 + digit3[7:0], 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};  // "1000" até "9999"
    end else if (nonce < 100000) begin
        nonce_ascii_len = 3'd5;
        nonce_ascii = {16'd0, 8'h30 + digit5[7:0], 8'h30 + digit4[7:0], 8'h30 + digit3[7:0], 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};   // "10000" até "99999"
    end else if (nonce < 1000000) begin
        nonce_ascii_len = 3'd6;
        nonce_ascii = {8'd0, 8'h30 + digit6[7:0], 8'h30 + digit5[7:0], 8'h30 + digit4[7:0], 8'h30 + digit3[7:0], 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};    // "100000" até "999999"
    end else begin
        nonce_ascii_len = 3'd7;
        nonce_ascii = {8'h30 + digit7[7:0], 8'h30 + digit6[7:0], 8'h30 + digit5[7:0], 8'h30 + digit4[7:0], 8'h30 + digit3[7:0], 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};   // "1000000" até "9999999"
    end
    
    // Construir MESSAGE_BLOCK_1
    // Total de dados: 40 (mensagem) + nonce_ascii_len bytes
    // Preenchimento calculado para manter tamanho de bloco de 512 bits
    case (nonce_ascii_len)
         3'd1: begin
             // 40 + 1 = 41 bytes de dados
             // Comprimento da mensagem: 41 * 8 = 328 bits = 0x0148
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii[7:0],
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
                nonce_ascii[15:0],
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
                nonce_ascii[23:0],
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
                nonce_ascii[31:0],
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
                nonce_ascii[39:0],
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
                nonce_ascii[47:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h70
            };
        end
         default: begin  // 3'd7
             // 40 + 7 = 47 bytes de dados
             // Comprimento da mensagem: 47 * 8 = 376 bits = 0x0178
            MESSAGE_BLOCK_1 = {
                buffer[0], buffer[1], buffer[2], buffer[3], buffer[4], buffer[5], buffer[6], buffer[7],
                buffer[8], buffer[9], buffer[10], buffer[11], buffer[12], buffer[13], buffer[14], buffer[15],
                buffer[16], buffer[17], buffer[18], buffer[19], buffer[20], buffer[21], buffer[22], buffer[23],
                buffer[24], buffer[25], buffer[26], buffer[27], buffer[28], buffer[29], buffer[30], buffer[31],
                buffer[32], buffer[33], buffer[34], buffer[35], buffer[36], buffer[37], buffer[38], buffer[39],
                nonce_ascii[55:0],
                8'h80,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                8'h01, 8'h78
            };
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

// MESSAGE_BLOCK para núcleo SHA-1: bloco de mensagem construído dinamicamente (512 bits total)
// Estrutura: mensagem (40 bytes) + nonce (1-7 bytes) + preenchimento + comprimento_mensagem
wire [511:0] MESSAGE_BLOCK = MESSAGE_BLOCK_1;

// Sinais de computação SHA-1
reg [27:0] clock_counter;     // Contador de temporização da máquina de estados: conta até 27 (≈1 segundo a 27MHz) para espera de computação SHA-1 e pisca do LED

reg [159:0] sha1_digest;     // Resultado do resumo SHA-1 computado
reg sha1_digest_valid;        // flag: computação SHA-1 completa

wire sha1_core_ready;         // Sinal de núcleo SHA-1 pronto (pode aceitar nova computação)
wire [159:0] sha1_core_digest;  // Resumo de saída do núcleo SHA-1 (160 bits)
wire sha1_core_digest_valid;   // flag de conclusão do núcleo SHA-1

reg sha1_init;             // Sinal pulsado: dispara inicialização do núcleo SHA-1
reg sha1_next;            // Sinal pulsado: dispara processamento do próximo bloco do núcleo SHA-1
wire sha1_start;            // Sinal de início: ativado quando buffer UART está cheio (estado BUFFER_FULL)
wire uart_tx_done_signal;   // Sinal de conclusão: ativado quando transmissão UART termina (estado UART_TX_DONE)

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
localparam STATE_PIPELINE   = 3'b110;  // NOVO: Processa próximo nonce da fila sem interrupção

// ========================================================
// NOVO: Variáveis de Fila de Nonces (Pipelined)
// ========================================================
// Implementação simples: armazena até 4 nonces para processar em paralelo
reg [31:0] nonce_fila[0:3];     // Fila com 4 nonces (32-bit cada)
reg [1:0] fila_escrita;         // Índice escrita (0-3)
reg [1:0] fila_leitura;         // Índice leitura (0-3)
reg [2:0] fila_contador;        // Quantidade de nonces na fila (0-4)

// Sinais auxiliares para fila
wire fila_vazia = (fila_contador == 3'd0);   // Verdadeiro se fila vazia
wire fila_cheia = (fila_contador == 3'd4);   // Verdadeiro se fila cheia (4 nonces)

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

// Instanciação do núcleo SHA-1
sha1_core sha1_inst(
    .clk(clk),
    .reset_n(rst_n),
    .init(sha1_init),
    .next(sha1_next),
    .block(MESSAGE_BLOCK),
    .ready(sha1_core_ready),
    .digest(sha1_core_digest),
    .digest_valid(sha1_core_digest_valid)
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
// Implementa mineração proof-of-work: itera nonce até SHA-1(mensagem||nonce) == hash_esperado
always @(posedge clk) begin
    sha1_init <= 1'b0;  // Pulso: ativado por um ciclo para disparar inicialização SHA-1
    sha1_next <= 1'b0;  // Pulso: ativado por um ciclo para disparar próximo bloco SHA-1

    case (state)
STATE_RESET: begin
             // Inicializa todas as saídas e contadores
             led_output <= 1'b0;
             led_sha1_work_output <= 1'b0;
             led_sha1_finish_output <= 1'b0;
             clock_counter <= 28'd0;
             nonce <= 32'd0;  // Reinicia nonce para 0 na inicialização

             // Aguarda 5 ciclos de relógio para estabilização do sistema
             if (clock_counter >= 28'd5) begin
                 clock_counter <= 28'd0;
                 state <= STATE_IDLE;
             end else begin
                 clock_counter <= clock_counter + 1'b1;
             end
         end

STATE_IDLE: begin
              // MODIFICADO: Aguarda núcleo SHA-1 pronto E buffer UART cheio
              // Agora também preenche a fila de nonces para pipeline
              
              // Reinicia fila quando transmissão UART completa (nova mensagem)
              if (uart_tx_done_signal) begin
                  nonce <= 32'd0;
                  fila_escrita <= 2'd0;    // Reseta índice escrita
                  fila_leitura <= 2'd0;    // Reseta índice leitura
                  fila_contador <= 3'd0;   // Fila vazia
              end
              
              // NOVO: Preenche fila com nonces quando buffer cheia
              // Adiciona 4 nonces à fila (nonce, nonce+1, nonce+2, nonce+3)
              if (sha1_start && !fila_cheia && !nonce_increment_done) begin
                  // Preenche os 4 primeiros nonces
                  if (fila_contador == 3'd0) begin
                      // Adiciona nonce+0 na posição 0
                      nonce_fila[0] <= nonce;
                      nonce_fila[1] <= nonce + 1'b1;
                      nonce_fila[2] <= nonce + 2'd2;
                      nonce_fila[3] <= nonce + 2'd3;
                      fila_contador <= 3'd4;  // Fila agora tem 4 nonces
                      fila_escrita <= 2'd0;   // Próxima escrita na posição 0
                      fila_leitura <= 2'd0;   // Leitura começará em 0
                      nonce <= nonce + 4'd4;  // Próximo bloco começará em nonce+4
                      nonce_increment_done <= 1'b1;  // Marca como feito
                  end
              end
              
               // Condição de transição: núcleo pronto E fila tem dados
               if (sha1_core_ready && fila_contador > 3'd0 && nonce_increment_done) begin
                   state <= STATE_INIT_SHA1;  // Começa a processar fila
                   clock_counter <= 28'd0;
               end
           end

STATE_INIT_SHA1: begin
             // Dispara núcleo SHA-1 para inicializar e processar MESSAGE_BLOCK
             led_sha1_work_output <= 1'b1;  // LED: indica que processamento começou
             sha1_init <= 1'b1;  // Pulso: dispara por um ciclo para ativar núcleo
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
             // Pesquisa sinal válido de resumo SHA-1 (resultado pronto)
             if (sha1_core_digest_valid) begin
                 sha1_digest <= sha1_core_digest;  // Captura resultado
                 sha1_digest_valid <= 1'b1;
                 clock_counter <= 28'd0;
                 state <= STATE_RESULT;
             end
         end

STATE_RESULT: begin
             // Verifica se hash computado corresponde ao hash esperado MATCH ou teste completo
             if ((sha1_digest == SHA1_EXPECTED)||(nonce >= DIFFICULTY-1)) begin
                 led_output <= 1'b1;  // LED: correspondência encontrada!
                 led_sha1_work_output <= 1'b0;  // Desativa indicador de trabalho
                   
                  // Em correspondência: nonce será transmitido pela máquina de estados UART
                  // Retorna a IDLE quando núcleo estiver pronto (aguarda próxima mensagem)
                  if (sha1_core_ready) begin
                      state <= STATE_IDLE;
                      clock_counter <= 28'd0;
                      led_sha1_finish_output <= 1'b0;
                      sha1_digest_valid <= 1'b0;
                      nonce_increment_done <= 1'b0;  // Reinicia flag para próximo buffer de mensagem

                  end else begin
                     // Pisca LED A 27MHz, limite do contador 5 = ~185 ns por incremento (indicador de depuração)
                     if (clock_counter >= 28'd5) begin
                         clock_counter <= 28'd0;
                         led_sha1_finish_output <= ~led_sha1_finish_output;  // Alterna LED
                     end else begin
                         clock_counter <= clock_counter + 1'b1;
                     end
                  end
              end else begin
                 // Sem correspondência MATCH: incrementa nonce e tenta novamente computação SHA-1
                 led_output <= 1'b0;
                 
                 // Sem correspondência: incrementa nonce para próxima tentativa e recalcula
                 // Aguarda núcleo pronto antes de iniciar próxima computação
                 if (sha1_core_ready) begin
                     // MODIFICADO: Verifica se há nonces na fila para pipeline
                     if (fila_contador > 3'd0) begin
                         // Tem nonces na fila: usa pipeline para processar mais rápido
                         state <= STATE_PIPELINE;
                     end else begin
                         // Sem nonces na fila: incrementa nonce normalmente
                         if (nonce < DIFFICULTY) begin
                             nonce <= nonce + 1'b1;
                         end else begin
                             nonce <= 32'd0;  // Reinicia para 0 após atingir dificuldade máxima
                         end
                         state <= STATE_INIT_SHA1;  // Volta ao init para próxima iteração
                     end
                     clock_counter <= 28'd0;
                     sha1_digest_valid <= 1'b0;  // Limpa para próxima computação
                     led_sha1_work_output <= 1'b1;  // Reativa LED indicador de trabalho
                 end
              end
         end

STATE_PIPELINE: begin
             // NOVO: Estado de pipeline - processa próximos nonces da fila
             // Quando núcleo SHA-1 termina, pega o próximo nonce da fila e processa
             // Evita esperar regressar a IDLE (muito mais rápido!)
             
             // Se fila tem nonces E núcleo está pronto: pega próximo nonce
             if (fila_contador > 3'd0 && sha1_core_ready) begin
                 // Pega nonce do índice de leitura
                 nonce <= nonce_fila[fila_leitura];
                 
                 // Atualiza fila: remove nonce lido
                 fila_leitura <= fila_leitura + 1'b1;  // Próximo índice (0→1→2→3→0)
                 fila_contador <= fila_contador - 1'b1; // Reduz quantidade
                 
                 // Inicia processamento do nonce lido
                 state <= STATE_INIT_SHA1;
                 clock_counter <= 28'd0;
             end
             // Se fila vazia: retorna a IDLE para aguardar próxima mensagem
             else if (fila_vazia) begin
                 state <= STATE_IDLE;
                 nonce_increment_done <= 1'b0;  // Reset flag para próxima mensagem
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
                 // Aguarda resultados de computação SHA-1
                 // Incremento de nonce acontece na máquina de estados SHA-1 (STATE_IDLE e STATE_RESULT)
                
                 // Quando resumo SHA-1 está pronto, prepara transmissão de nonce
                 // Transmite nonce apenas se hash SHA-1 corresponde ao valor esperado ou nonce superou dificuldade
                 if ((sha1_digest_valid && tx_data_ready && (sha1_digest == SHA1_EXPECTED))||(nonce >= DIFFICULTY-1)) begin
                     // Condições atendidas: resultado SHA-1 válido E UART pronto E hash corresponde
                     // Começa transmissão do resultado de nonce de 4 bytes
                     // Byte 0 (MSB): nonce[31:24]
                     tx_data <= nonce[31:24];      // Byte 0 Transmite MSB primeiro (big-endian)
                     tx_data_valid <= 1'b1;
                     led_uart_work_output <= 1'b1;         // LED: transmissão iniciada
                     tx_index <= 5'd0;                     // Começa no índice 0
                     uart_state <= UART_TRANSMIT_NONCE;     // Move para estado de transmissão
                 end
             end

            //------------------------------------------
UART_TRANSMIT_NONCE: begin
                // Transmite 4 bytes de nonce (32 bits total)
                // Ordem de transmissão: MSB-primeiro (big-endian) [31:24], [23:16], [15:8], [7:0]
                
                if (tx_data_ready) begin
                    if (tx_index < 5'd3) begin
                        // Mais bytes de nonce para transmitir: prepara próximo byte
                        // Byte 0 já foi enviado; necessário enviar bytes 1, 2, 3
                        // tx_index: 0→1→2→3 (4 transições para 4 bytes total)
                        tx_index <= tx_index + 1'b1;
                        
                        // Extrai próximo byte: usa (tx_index + 1) para obter próximo slice
                        case(tx_index + 1'b1)
                            5'd1:  tx_data <= nonce[23:16];   // Byte 1
                            5'd2:  tx_data <= nonce[15:8];    // Byte 2
                            5'd3:  tx_data <= nonce[7:0];     // Byte 3 (LSB)
                            default: tx_data <= 8'd0;
                        endcase
                        
                        tx_data_valid <= 1'b1;
                    end else begin
                        // Todos os 4 bytes de nonce (índices 0-3) transmitidos: finaliza
                        tx_data_valid <= 1'b0;
                        led_uart_finish_output <= !led_uart_finish_output;  // Alterna LED
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
