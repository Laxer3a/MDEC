module gpu_mem_addr_gen
(
     input           clk_i
    ,input           rst_i

    ,input           req_start_i
    ,input           req_incr_i
    ,input  [ 15:0]  req_x_i
    ,input  [ 15:0]  req_y_i
    ,input  [ 15:0]  req_sizex_i
    ,input  [ 15:0]  req_sizey_i

    ,output          valid_o
    ,output [31:0]   addr_o
    ,output [3:0]    offset_o
    ,output [15:0]   mask_o
    ,output          last_line_o
    ,output          last_o
    ,input           accept_i
);

localparam PIXEL_BURST       = 16;

//-----------------------------------------------------------------
// Active / valid addr
//-----------------------------------------------------------------
reg active_q;

always @ (posedge clk_i )
if (rst_i)
    active_q <= 1'b0;
else if (req_start_i)
    active_q <= 1'b1;
else if (valid_o && last_o && accept_i)
    active_q <= 1'b0;

//-----------------------------------------------------------------
// Direction storage
//-----------------------------------------------------------------
reg req_incr_q;

always @ (posedge clk_i )
if (rst_i)
    req_incr_q <= 1'b0;
else if (req_start_i)
    req_incr_q <= req_incr_i;

//-----------------------------------------------------------------
// Dimensions
//-----------------------------------------------------------------
reg [15:0] start_x_q;
reg [15:0] start_y_q;
reg [15:0] cur_x_q;
reg [15:0] cur_y_q;
reg [15:0] end_x_q;
reg [15:0] end_y_q;

reg [15:0] start_x_r;
reg [15:0] start_y_r;
reg [15:0] cur_x_r;
reg [15:0] cur_y_r;
reg [15:0] end_x_r;
reg [15:0] end_y_r;

// This is the last access
reg         end_reached_r;

// Last column access, maybe moves to another row
reg         end_line_r;

// Next Y coordinate
wire [15:0] next_y_w            = cur_y_q + 16'd1;

// [INCR] Number of pixels until the edge of the square
wire [15:0] incr_remaining_w    = end_x_q - cur_x_q;

// [INCR] Max access size (capped to burst length)
wire [15:0] incr_max_x_w        = (incr_remaining_w > PIXEL_BURST) ? PIXEL_BURST : incr_remaining_w;

// [INCR] Pixels remaining in the line
wire [15:0] x_line_remain_w     = PIXEL_BURST - {12'b0, cur_x_q[3:0]};

// [INCR] Pixels to access taking into account alignment and remainder
wire [15:0] incr_x_w            = (x_line_remain_w > incr_max_x_w) ? incr_max_x_w : x_line_remain_w;

// [DECR] Rounded down start of line
wire [15:0] x_line_start_w      = {cur_x_q[15:4], 4'b0};

// [DECR] Line address (no underflow past start address)
wire [15:0] curr_x_line_start_w = (x_line_start_w < start_x_q) ? start_x_q : x_line_start_w;

// [DECR] How many pixels were consumed in the access + 1 (to take you the next line
wire [15:0] decr_avail_max_x_w  = end_x_q + 16'd1 - curr_x_line_start_w;

// [DECR] As above but pegged to burst size
wire [15:0] decr_avail_x_w      = (decr_avail_max_x_w > PIXEL_BURST) ? PIXEL_BURST : decr_avail_max_x_w;

// [DECR] Pixels to decrement by for the next read
wire [15:0] decr_x_w            = (cur_x_q - x_line_start_w) + 16'd1;

// Next X position - taking into account direction
wire [15:0] curr_x_next_w       = req_incr_q ? (cur_x_q + incr_x_w) : (cur_x_q - decr_x_w);

always @ *
begin
    start_x_r     = start_x_q;
    start_y_r     = start_y_q;
    cur_x_r       = cur_x_q;
    cur_y_r       = cur_y_q;
    end_x_r       = end_x_q;
    end_y_r       = end_y_q;
    end_reached_r = 1'b0;
    end_line_r    = 1'b0;

    if (req_start_i)
    begin
        if (req_incr_i)
        begin
            start_x_r = req_x_i;
            start_y_r = req_y_i;
            cur_x_r   = req_x_i;
            cur_y_r   = req_y_i;
            end_x_r   = req_x_i + req_sizex_i;
            end_y_r   = req_y_i + req_sizey_i;        
        end
        else
        begin
            start_x_r = req_x_i;
            end_x_r   = req_x_i + req_sizex_i-1;
            cur_x_r   = end_x_r;
            start_y_r = req_y_i;
            cur_y_r   = req_y_i;
            end_y_r   = req_y_i + req_sizey_i;
        end
    end
    else if (valid_o && accept_i)
    begin
        // Incrementing X
        if (req_incr_q)
        begin
            if (curr_x_next_w >= end_x_r)
            begin
                end_line_r = 1'b1;

                if (next_y_w >= end_y_r)
                begin
                    cur_y_r       = next_y_w;
                    end_reached_r = 1'b1;
                end
                else
                begin
                    cur_x_r = start_x_r;
                    cur_y_r = next_y_w;
                end
            end
            else
                cur_x_r = curr_x_next_w;
        end
        // Decrementing X
        else
        begin
            if (curr_x_line_start_w <= start_x_r)
            begin
                end_line_r = 1'b1;

                if (next_y_w >= end_y_r)
                begin
                    cur_y_r       = next_y_w;
                    end_reached_r = 1'b1;
                end
                else
                begin
                    cur_x_r = end_x_r;
                    cur_y_r = next_y_w;
                end
            end
            else
                cur_x_r = curr_x_next_w;
        end
    end
end

always @ (posedge clk_i )
if (rst_i)
    start_x_q <= 16'b0;
else
    start_x_q <= start_x_r;

always @ (posedge clk_i )
if (rst_i)
    start_y_q <= 16'b0;
else
    start_y_q <= start_y_r;

always @ (posedge clk_i )
if (rst_i)
    cur_x_q <= 16'b0;
else
    cur_x_q <= cur_x_r;

always @ (posedge clk_i )
if (rst_i)
    cur_y_q <= 16'b0;
else
    cur_y_q <= cur_y_r;

always @ (posedge clk_i )
if (rst_i)
    end_x_q <= 16'b0;
else
    end_x_q <= end_x_r;

always @ (posedge clk_i )
if (rst_i)
    end_y_q <= 16'b0;
else
    end_y_q <= end_y_r;


//-----------------------------------------------------------------
// Mask
//-----------------------------------------------------------------
reg [15:0] mask_r;

always @ *
begin
    mask_r = 16'b0;

    case (req_incr_q ? incr_x_w : decr_avail_x_w)
    16'd1: mask_r = 16'b0000000000000001;
    16'd2: mask_r = 16'b0000000000000011;
    16'd3: mask_r = 16'b0000000000000111;
    16'd4: mask_r = 16'b0000000000001111;
    16'd5: mask_r = 16'b0000000000011111;
    16'd6: mask_r = 16'b0000000000111111;
    16'd7: mask_r = 16'b0000000001111111;
    16'd8: mask_r = 16'b0000000011111111;
    16'd9: mask_r = 16'b0000000111111111;
    16'd10: mask_r = 16'b0000001111111111;
    16'd11: mask_r = 16'b0000011111111111;
    16'd12: mask_r = 16'b0000111111111111;
    16'd13: mask_r = 16'b0001111111111111;
    16'd14: mask_r = 16'b0011111111111111;
    16'd15: mask_r = 16'b0111111111111111;
    default: mask_r = 16'b1111111111111111;
    endcase

    if (req_incr_q)
        mask_r = mask_r << cur_x_q[3:0];
    else
        mask_r = mask_r << curr_x_line_start_w[3:0];
end

assign mask_o = mask_r;

//-----------------------------------------------------------------
// Outputs
//-----------------------------------------------------------------
// Valid address output
assign valid_o     = active_q;

// Full byte address to VRAM
assign addr_o      = {12'b0, cur_y_q[8:0], cur_x_q[9:4], 5'b0};

// Pixel within the line (16 pixels per 32-byte line)
assign offset_o    = cur_x_q[3:0];

// Last x axis address, could go back to the start on another y value
assign last_line_o = end_line_r;

// Last ever transaction
assign last_o      = end_reached_r;

endmodule