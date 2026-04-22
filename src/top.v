// Top-level module for FPGA SHA-1 hash computation with dynamic nonce iteration
// Implements proof-of-work mining: receives message + expected hash via UART,
// iterates nonce from 0 to DIFFICULTY, computing SHA-1(message||nonce) until match found
`default_nettype wire

module top(
    input wire clk,            // System clock (27 MHz)
	input wire rst,            // Active-high reset
    input wire uart_rx,        // UART receive pin
    output wire uart_tx,       // UART transmit pin
    output wire led,           // LED: SHA-1 match status (active-low)
    output wire led_sha1_work, // LED: SHA-1 processing active (active-low)
    output wire led_sha1_finish, // LED: SHA-1 computation finished (active-low)
    output wire led_uart_work, // LED: UART transmit active (active-low)
    output wire led_uart_finish  // LED: UART transmit finished (active-low)
);

parameter CLK_FRE  = 27;    // Clock frequency in MHz
parameter UART_FRE = 115200; // UART baud rate

parameter DIFFICULTY = 9000000; // Maximum nonce value for proof-of-work (9,000,000 iterations)

// Input message (dynamic): 40 bytes received via UART, stored in buffer[0..39]
// Expected SHA-1 hash: 40 ASCII hex characters received via UART, stored in buffer[40..79]
// Hash represents 20 binary bytes (160 bits) for SHA-1 comparison
reg [159:0] SHA1_EXPECTED;  // Expected SHA-1 hash (160 bits = 20 bytes, decoded from buffer[40..79])

// Nonce variable: incremented from 0 to DIFFICULTY (2,000,000) during computation
reg [31:0] nonce;  // 32-bit nonce (sufficient for values up to 9,000,000 )

// Nonce ASCII conversion: variable length (without leading zeros)
// Maximum 7 bytes for values up to 2,000,000
// Example: nonce=1     -> nonce_ascii="1"      (1 byte)
//          nonce=12345 -> nonce_ascii="12345"  (5 bytes)
reg [55:0] nonce_ascii;     // ASCII representation of nonce (56 bits = 7 bytes maximum)
reg [2:0] nonce_ascii_len;  // Length in bytes (1-7)

// Digit extraction combinational logic: decimal digits derived from nonce value
wire [31:0] digit7 = (nonce / 32'd1000000) % 32'd10;  // 10^6
wire [31:0] digit6 = (nonce / 32'd100000) % 32'd10;   // 10^5
wire [31:0] digit5 = (nonce / 32'd10000) % 32'd10;    // 10^4
wire [31:0] digit4 = (nonce / 32'd1000) % 32'd10;     // 10^3
wire [31:0] digit3 = (nonce / 32'd100) % 32'd10;      // 10^2
wire [31:0] digit2 = (nonce / 32'd10) % 32'd10;       // 10^1
wire [31:0] digit1 = nonce % 32'd10;                  // 10^0

// Message block: 512-bit input block with padding (RFC 3174 SHA-1 standard)
// Dynamic structure:
//   Bytes 0-39:  Message (40 bytes) from UART buffer
//   Bytes 40+:   Nonce ASCII (1-7 bytes, variable length, no leading zeros)
//   Byte 47+:    0x80 (padding bit marker) + zero bytes + message_length_in_bits (64-bit big-endian)

reg [511:0] MESSAGE_BLOCK_1;  // 512-bit SHA-1 message block

// Combinational logic: constructs dynamic MESSAGE_BLOCK_1 with variable-length nonce
always @(*) begin
    // Determine ASCII nonce length and construct nonce_ascii register
    if (nonce == 0) begin
        nonce_ascii_len = 3'd1;
        nonce_ascii = {48'd0, 8'h30};  // "0"
    end else if (nonce < 10) begin
        nonce_ascii_len = 3'd1;
        nonce_ascii = {48'd0, 8'h30 + digit1[7:0]};  // "1" a "9"
    end else if (nonce < 100) begin
        nonce_ascii_len = 3'd2;
        nonce_ascii = {40'd0, 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};  // "10" a "99"
    end else if (nonce < 1000) begin
        nonce_ascii_len = 3'd3;
        nonce_ascii = {32'd0, 8'h30 + digit3[7:0], 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};  // "100" a "999"
    end else if (nonce < 10000) begin
        nonce_ascii_len = 3'd4;
        nonce_ascii = {24'd0, 8'h30 + digit4[7:0], 8'h30 + digit3[7:0], 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};  // "1000" a "9999"
    end else if (nonce < 100000) begin
        nonce_ascii_len = 3'd5;
        nonce_ascii = {16'd0, 8'h30 + digit5[7:0], 8'h30 + digit4[7:0], 8'h30 + digit3[7:0], 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};   // "10000" a "99999"
    end else if (nonce < 1000000) begin
        nonce_ascii_len = 3'd6;
        nonce_ascii = {8'd0, 8'h30 + digit6[7:0], 8'h30 + digit5[7:0], 8'h30 + digit4[7:0], 8'h30 + digit3[7:0], 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};    // "100000" a "999999"
    end else begin
        nonce_ascii_len = 3'd7;
        nonce_ascii = {8'h30 + digit7[7:0], 8'h30 + digit6[7:0], 8'h30 + digit5[7:0], 8'h30 + digit4[7:0], 8'h30 + digit3[7:0], 8'h30 + digit2[7:0], 8'h30 + digit1[7:0]};   // "1000000" a "9999999"
    end
    
    // Construir MESSAGE_BLOCK_1
    // Total data: 40 (message) + nonce_ascii_len bytes
    // Padding calculated to maintain 512-bit block size
    case (nonce_ascii_len)
        3'd1: begin
            // 40 + 1 = 41 bytes de dados
            // Message length: 41 * 8 = 328 bits = 0x0148
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
            // Message length: 42 * 8 = 336 bits = 0x0150
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
            // Message length: 43 * 8 = 344 bits = 0x0158
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
            // Message length: 44 * 8 = 352 bits = 0x0160
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
            // Message length: 45 * 8 = 360 bits = 0x0168
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
            // Message length: 46 * 8 = 368 bits = 0x0170
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
            // Message length: 47 * 8 = 376 bits = 0x0178
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
    
    // SHA1_EXPECTED: Decode 40 ASCII hex characters from buffer[40..79] into 160-bit binary hash
    // Conversion: each pair of ASCII hex chars [2n, 2n+1] becomes one binary byte
    // Example: ASCII '48' -> 0x48, 'a3' -> 0xa3, etc. (supports both uppercase and lowercase)
    SHA1_EXPECTED = {
        // Bytes 0-19: Decode hex pairs from buffer indices 40-79
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

// MESSAGE_BLOCK for SHA-1 core: dynamically constructed message block (512 bits total)
// Structure: message (40 bytes) + nonce (1-7 bytes) + padding + message_length
wire [511:0] MESSAGE_BLOCK = MESSAGE_BLOCK_1;

// SHA-1 computation signals
reg [27:0] clock_counter;     // State machine timing counter: counts to 27 (≈1 second at 27MHz) for SHA-1 computation wait and LED blink

reg [159:0] sha1_digest;     // Computed SHA-1 digest result
reg sha1_digest_valid;        // Flag: SHA-1 computation complete

wire sha1_core_ready;         // SHA-1 core ready signal (can accept new computation)
wire [159:0] sha1_core_digest;  // SHA-1 core output digest (160 bits)
wire sha1_core_digest_valid;   // SHA-1 core completion flag

reg sha1_init;             // Strobed signal: triggers SHA-1 core initialization
reg sha1_next;            // Strobed signal: triggers SHA-1 core to process next block
wire sha1_start;            // Start signal: asserted when UART buffer is full (BUFFER_FULL state)
wire uart_tx_done_signal;   // Completion signal: asserted when UART transmission finishes (UART_TX_DONE state)

reg led_output;           // LED output: SHA-1 match status
reg led_sha1_work_output;     // LED output: SHA-1 processing active
reg led_sha1_finish_output;   // LED output: SHA-1 computation finished
reg led_uart_work_output;     // LED output: UART transmit in progress
reg led_uart_finish_output;   // LED output: UART transmit finished

reg [27:0] blink_counter;    // Blink counter for LED

// SHA-1 state machine: implements proof-of-work with nonce iteration
// States: RESET → IDLE → INIT_SHA1 → RUNNING → DONE_WAIT → RESULT
// In RESULT: if hash matches, transmit nonce; otherwise increment and retry
reg [2:0] state;
localparam STATE_RESET      = 3'b000;  // Initialize: reset all counters
localparam STATE_IDLE       = 3'b001;  // Wait: SHA-1 core ready AND UART buffer full
localparam STATE_INIT_SHA1  = 3'b010;  // Initialize SHA-1 core with MESSAGE_BLOCK
localparam STATE_RUNNING    = 3'b011;  // Delay: wait for SHA-1 core to complete (~1 second)
localparam STATE_DONE_WAIT  = 3'b100;  // Poll: wait for SHA-1 digest_valid flag
localparam STATE_RESULT     = 3'b101;  // Check: if match found, signal UART TX; otherwise increment nonce and retry

// UART RX signals
wire [7:0] rx_data;        // Received data byte
wire rx_data_valid;       // RX data valid flag
reg rx_data_ready = 1'b1; // RX ready flag

// UART TX signals
reg [7:0] tx_data;       // Transmit data byte
reg tx_data_valid;      // TX data valid flag
wire tx_data_ready;    // TX ready flag

wire rst_n = !rst;  // Convert reset to active-low convention for IP cores

// LED outputs: inverted because LEDs are active-low
assign led = ~led_output;                     // LED: SHA-1 computed hash matches expected value
assign led_sha1_work = ~led_sha1_work_output;   // LED: SHA-1 computation in progress (1-second blink)
assign led_sha1_finish = ~led_sha1_finish_output;  // LED: SHA-1 computation finished (0.5-second blink)
assign led_uart_work = ~led_uart_work_output;  // LED: UART transmit in progress (1-second blink)
assign led_uart_finish = ~led_uart_finish_output;  // LED: UART transmit finished (0.5-second blink)

// SHA-1 core instantiation
// Note: reset_n is permanently enabled (hardwired to 1'b1); state machine provides control
sha1_core sha1_inst(
    .clk(clk),
    .reset_n(1'b1),
    .init(sha1_init),
    .next(sha1_next),
    .block(MESSAGE_BLOCK),
    .ready(sha1_core_ready),
    .digest(sha1_core_digest),
    .digest_valid(sha1_core_digest_valid)
);

// UART RX
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

// UART TX
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

// SHA-1 state machine main logic
// Implements proof-of-work mining: iterates nonce until SHA-1(message||nonce) == expected_hash
always @(posedge clk) begin
    sha1_init <= 1'b0;  // Strobe: asserted for one cycle to trigger SHA-1 init
    sha1_next <= 1'b0;  // Strobe: asserted for one cycle to trigger SHA-1 next block

    case (state)
STATE_RESET: begin
             // Initialize all outputs and counters
             led_output <= 1'b0;
             led_sha1_work_output <= 1'b0;
             led_sha1_finish_output <= 1'b0;
             clock_counter <= 28'd0;
             nonce <= 32'd0;  // Reset nonce to 0 at startup

             // Wait 10 clocks for system stabilization
             if (clock_counter >= 28'd10) begin
                 clock_counter <= 28'd0;
                 state <= STATE_IDLE;
             end else begin
                 clock_counter <= clock_counter + 1'b1;
             end
         end

STATE_IDLE: begin
             // Wait for SHA-1 core ready AND UART buffer full (indicates new message)
             
             // Reset nonce when UART transmission completes (prepare for next message)
             if (uart_tx_done_signal) begin
                 nonce <= 32'd0;
             end
             
             // First nonce increment: triggered by sha1_start and nonce_increment_done flag
             // Ensures nonce increments exactly once per message buffer
             if (sha1_start && !nonce_increment_done) begin
                  if (nonce < DIFFICULTY) begin
                      nonce <= nonce + 1'b1;
                  end else begin
                      nonce <= 32'd0;  // Reset to 0 after reaching max difficulty
                  end
                  nonce_increment_done <= 1'b1;  // Set flag to prevent redundant increments
              end
              
              // Transition condition: core ready AND buffer full AND nonce already incremented
              if (sha1_core_ready && sha1_start && nonce_increment_done) begin
                  state <= STATE_INIT_SHA1;
                  clock_counter <= 28'd0;
              end
          end

STATE_INIT_SHA1: begin
             // Trigger SHA-1 core to initialize and process MESSAGE_BLOCK
             led_sha1_work_output <= 1'b1;  // LED: indicate processing started
             sha1_init <= 1'b1;  // Strobe: pulse for one cycle to trigger core
             state <= STATE_RUNNING;
             clock_counter <= 28'd0;
         end

STATE_RUNNING: begin
             // Wait for SHA-1 core to complete (approximately 1 second at 27 MHz)
             // Actually: counter reaches 27 ≈ 1µs, but SHA-1 typically completes within this window
             if (clock_counter >= 28'd27) begin
                 state <= STATE_DONE_WAIT;
                 clock_counter <= 28'd0;
             end else begin
                 clock_counter <= clock_counter + 1'b1;
             end
         end

STATE_DONE_WAIT: begin
             // Poll for SHA-1 digest valid signal (result ready)
             if (sha1_core_digest_valid) begin
                 sha1_digest <= sha1_core_digest;  // Capture result
                 sha1_digest_valid <= 1'b1;
                 clock_counter <= 28'd0;
                 state <= STATE_RESULT;
             end
         end

STATE_RESULT: begin
             // Check if computed hash matches expected hash or all test
             if ((sha1_digest == SHA1_EXPECTED)||(nonce >= DIFFICULTY-1)) begin
                 led_output <= 1'b1;  // LED: match found!
                 led_sha1_work_output <= 1'b0;  // Turn off work indicator
                   
                  // On match: nonce will be transmitted by UART state machine
                  // Return to IDLE when core ready (wait for next message)
                  if (sha1_core_ready) begin
                      state <= STATE_IDLE;
                      clock_counter <= 28'd0;
                      led_sha1_finish_output <= 1'b0;
                      sha1_digest_valid <= 1'b0;
                      nonce_increment_done <= 1'b0;  // Reset flag for next message buffer

                  end else begin
                     // Blink LED every 0.5 seconds while waiting for core (debug indicator)
                     // At 27MHz, counter threshold 13 = ~481ns per increment
                     if (clock_counter >= 28'd13) begin
                         clock_counter <= 28'd0;
                         led_sha1_finish_output <= ~led_sha1_finish_output;  // Toggle LED
                     end else begin
                         clock_counter <= clock_counter + 1'b1;
                     end
                 end
             end else begin
                // No match: increment nonce and retry SHA-1 computation
                led_output <= 1'b0;
                
                // On no match: increment nonce for next attempt and recalculate
                // Wait for core ready before launching next computation
                if (sha1_core_ready) begin
                    // Increment nonce for retry attempt (wrap at DIFFICULTY)
                    if (nonce < DIFFICULTY) begin
                        nonce <= nonce + 1'b1;
                    end else begin
                        nonce <= 32'd0;  // Reset to 0 after reaching max difficulty
                    end
                    
                    state <= STATE_INIT_SHA1;  // Go back to init for next iteration
                    clock_counter <= 28'd0;
                    sha1_digest_valid <= 1'b0;  // Clear for next computation
                    led_sha1_work_output <= 1'b1;  // Re-enable work indicator LED
                end
            end
        end

default: begin
            state <= STATE_RESET;
        end
    endcase
end

// UART RX and TX State Machine
// ===========================
// Implements buffering of 80 bytes: 40 message bytes + 40 ASCII hex hash bytes
// Receives entire buffer, then triggers SHA-1 computation
// On match found, transmits 4-byte nonce result
// Structure: buffer[0..39] = message, buffer[40..79] = expected hash

// Buffer size constant
localparam BUFFER_SIZE = 80;  // Total: 40 message bytes + 40 ASCII hash bytes

// UART FSM states
localparam UART_IDLE         = 2'd0;  // Accumulating bytes in buffer
localparam UART_BUFFER_FULL  = 2'd1;  // Buffer complete, ready for SHA-1 computation
localparam UART_TRANSMIT_NONCE = 2'd2; // Transmitting nonce result (4 bytes = 32 bits)
localparam UART_TX_DONE      = 2'd3;  // Transmission complete

// Combinational signals for state-based control
// Signal: SHA-1 start (asserted when UART buffer is full)
// This notifies SHA-1 state machine that new message is ready
assign sha1_start = (uart_state == UART_BUFFER_FULL) ? 1'b1 : 1'b0;

// Signal: UART transmission complete (asserted when transmission finishes)
// Notifies SHA-1 state machine to reset nonce for next message
assign uart_tx_done_signal = (uart_state == UART_TX_DONE) ? 1'b1 : 1'b0;

// UART state machine registers
reg [1:0] uart_state;           // Current state

// Dynamic receive buffer
reg [7:0] buffer [0:BUFFER_SIZE-1];  // 80-byte buffer: [0..39] message, [40..79] hash

reg [6:0] byte_count;           // Receive counter: 0 to 80 (needs 7 bits)
reg [4:0] tx_index;             // Transmit index: 0 to 3 for 4 nonce bytes (needs 5 bits)
reg nonce_increment_done;       // Flag: ensures nonce incremented exactly once per buffer

// Rising-edge detector: detects arrival of new UART byte
reg rx_valid_reg1;
reg rx_valid_reg2;
wire rx_new_byte = rx_valid_reg1 && !rx_valid_reg2;

// UART FSM: handles message reception and result transmission
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
         // Reset: initialize all UART state variables
         uart_state <= UART_IDLE;
         byte_count <= 7'd0;  // Start at 0 (supports up to 80)
         tx_index <= 5'd0;    // Start at 0 (transmit 4 bytes: indices 0-3)
         tx_data <= 8'd0;
         tx_data_valid <= 1'b0;
         rx_valid_reg1 <= 1'b0;
         rx_valid_reg2 <= 1'b0;
         led_uart_work_output <= 1'b0;
         led_uart_finish_output <= 1'b0;
    end else begin
        // Rising-edge detection: capture new UART byte arrival
        rx_valid_reg1 <= rx_data_valid;
        rx_valid_reg2 <= rx_valid_reg1;

        // UART FSM main logic
        case (uart_state)
            //------------------------------------------
UART_IDLE: begin
                // Accumulate bytes in buffer as they arrive
                // byte_count tracks how many bytes received so far (0 to 80)
                tx_data_valid <= 1'b0;  // Not transmitting yet
                led_uart_work_output <= 1'b0;

                // New byte arrived: store it and increment counter
                if (rx_new_byte && byte_count < BUFFER_SIZE) begin
                    buffer[byte_count] <= rx_data;      // Store at current index
                    byte_count <= byte_count + 1'b1;    // Increment counter
                    
                     // Transition when last byte received (byte_count reaches 79, will increment to 80)
                     if (byte_count == BUFFER_SIZE - 1) begin
                         uart_state <= UART_BUFFER_FULL;
                     end
                end
            end

             //------------------------------------------
UART_BUFFER_FULL: begin
                 // Wait for SHA-1 computation results
                 // Nonce increment happens in SHA-1 state machine (STATE_IDLE and STATE_RESULT)
                
                 // When SHA-1 digest ready, prepare nonce transmission
                 // Only transmit nonce if SHA-1 hash matches expected value
                 if ((sha1_digest_valid && tx_data_ready && (sha1_digest == SHA1_EXPECTED))||(nonce >= DIFFICULTY-1)) begin
                     // Conditions met: SHA-1 result valid AND UART ready AND hash matches
                     // Start transmitting the 4-byte nonce result
                     // Byte 0 (MSB): nonce[31:24]
                     tx_data <= nonce[31:24];      // Transmit MSB first (big-endian)
                     tx_data_valid <= 1'b1;
                     led_uart_work_output <= 1'b1;         // LED: transmit started
                     tx_index <= 5'd0;                     // Start at index 0
                     uart_state <= UART_TRANSMIT_NONCE;     // Move to transmission state
                 end
             end

            //------------------------------------------
UART_TRANSMIT_NONCE: begin
                // Transmit 4 nonce bytes (32 bits total)
                // Transmission order: MSB-first (big-endian) [31:24], [23:16], [15:8], [7:0]
                
                if (tx_data_ready) begin
                    if (tx_index < 5'd3) begin
                        // More nonce bytes to transmit: prepare next byte
                        // Byte 0 already sent; need to send bytes 1, 2, 3
                        // tx_index: 0→1→2→3 (4 transitions for 4 bytes total)
                        tx_index <= tx_index + 1'b1;
                        
                        // Extract next byte: use (tx_index + 1) to get next slice
                        case(tx_index + 1'b1)
                            5'd1:  tx_data <= nonce[23:16];   // Byte 1
                            5'd2:  tx_data <= nonce[15:8];    // Byte 2
                            5'd3:  tx_data <= nonce[7:0];     // Byte 3 (LSB)
                            default: tx_data <= 8'd0;
                        endcase
                        
                        tx_data_valid <= 1'b1;
                    end else begin
                        // All 4 nonce bytes (indices 0-3) transmitted: finalize
                        tx_data_valid <= 1'b0;
                        led_uart_finish_output <= !led_uart_finish_output;  // Toggle LED
                        uart_state <= UART_TX_DONE;
                    end
                end
            end

             //------------------------------------------
UART_TX_DONE: begin
                  // Transmission complete: prepare for next message
                  // Reset byte_count to 0 to receive next message buffer
                  byte_count <= 7'd0;
                  uart_state <= UART_IDLE;
                  // Note: SHA-1 state machine resets nonce when UART transmission completes
               end
        endcase
    end
end


endmodule
