module a_gpu_tb
    ();

    localparam     gpu_clk_period = 1000 / 33.8; // ns/mhz
    typedef int unsigned uint;


    logic          clk;
    logic          i_nrst;

    logic          gpuAdrA2;
    logic          gpuSel;
    logic          o_canWrite;
    logic          IRQRequest;
    logic [31:0]   mydebugCnt;

    logic [19:0]   adr_o;
    logic [31:0]   dat_i;
    logic [31:0]   dat_o;
    logic  [2:0]   cnt_o;
    logic  [3:0]   sel_o;
    logic          wrt_o;
    logic          req_o;
    logic          ack_i;

    logic          write;
    logic          read;
    logic [31:0]   cpuDataIn;
    logic [31:0]   cpuDataOut;
    logic          validDataOut;
    //
    // tasks
    task automatic WaitClk(int count = 1);
        for (int i=0; i<count; i++) begin
            @(posedge clk);
        end
    endtask

    task automatic CpuWrite(uint data);
        gpuSel   = 1'b1;
        gpuAdrA2 = 1'b0;
        write    = 1'b1;
        cpuDataIn = data;

        $display("Cpu Write :%08X", data);
        WaitClk;
        gpuSel   = 1'b0;
        gpuAdrA2 = 1'b0;
        write    = 1'b0;
    endtask

    task automatic CpuRead;

    endtask
    //
    //
    // clock and reset
    //
    initial begin
        i_nrst = 1'b0;
        #1ns;
        i_nrst = 1'b1;
    end

    initial begin
        clk = 1'b0;
        forever begin
            #(gpu_clk_period/2);
            clk = 1'b1;
            #(gpu_clk_period - gpu_clk_period/2);
            clk = 1'b0;
        end
    end

    gpu gpu_inst ( .*);


    // memory interface
    assign dat_i = '0;
    assign ack_i = 1'b0;

    // cpu driver
    initial begin


        gpuAdrA2  = 1'b0;
        gpuSel    = 1'b0;
        write     = 1'b0;
        read      = 1'b0;
        cpuDataIn = '0;

        WaitClk(100);
        CpuWrite(32'h380000b2);
        CpuWrite((192<<0) | (240<<16));

        CpuWrite(32'h00008cb2);
        CpuWrite((320<<0) | (112<<16));

        CpuWrite(32'h00008cb2);
        CpuWrite((320<<0) | (368<<16));

        CpuWrite(32'h000000b2);
        CpuWrite((448<<0) | (240<<16));

    end

endmodule