// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "VX_define.vh"

module VX_ibuffer import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = ""
) (
    input wire          clk,
    input wire          reset,

`ifdef PERF_ENABLE
    output wire [`PERF_CTR_BITS-1:0] perf_stalls,
    output wire [`PERF_CTR_BITS-1:0] perf_ibf_pops_out,	    
`endif

    // inputs
    VX_decode_if.slave  decode_if,

    // outputs
    VX_ibuffer_if.master ibuffer_if [PER_ISSUE_WARPS]
);
    `UNUSED_SPARAM (INSTANCE_ID)
    localparam DATAW = `UUID_WIDTH + `NUM_THREADS + `PC_BITS + 1 + `EX_BITS + `INST_OP_BITS + `INST_ARGS_BITS + (`NR_BITS * 4);

    wire [PER_ISSUE_WARPS-1:0] ibuf_ready_in;
    assign decode_if.ready = ibuf_ready_in[decode_if.data.wid];

    for (genvar w = 0; w < PER_ISSUE_WARPS; ++w) begin : g_instr_bufs
        VX_elastic_buffer #(
            .DATAW   (DATAW),
            .SIZE    (`IBUF_SIZE),
            .OUT_REG (1)
        ) instr_buf (
            .clk      (clk),
            .reset    (reset),
            .valid_in (decode_if.valid && decode_if.data.wid == ISSUE_WIS_W'(w)),
            .data_in  ({
                decode_if.data.uuid,
                decode_if.data.tmask,
                decode_if.data.PC,
                decode_if.data.ex_type,
                decode_if.data.op_type,
                decode_if.data.op_args,
                decode_if.data.wb,
                decode_if.data.rd,
                decode_if.data.rs1,
                decode_if.data.rs2,
                decode_if.data.rs3
            }),
            .ready_in (ibuf_ready_in[w]),
            .valid_out(ibuffer_if[w].valid),
            .data_out (ibuffer_if[w].data),
            .ready_out(ibuffer_if[w].ready)
        );
    `ifndef L1_ENABLE
        assign decode_if.ibuf_pop[w] = ibuffer_if[w].valid && ibuffer_if[w].ready;
    `endif
    end
/*
`ifdef PERF_ENABLE
    reg [`PERF_CTR_BITS-1:0] perf_ibf_stalls;
    reg [`PERF_CTR_BITS-1:0] perf_ibf_pops;
    integer i;
    wire decode_if_stall = decode_if.valid && ~decode_if.ready;

    always @(posedge clk) begin
        if (reset) begin
            perf_ibf_stalls <= '0;
            perf_ibf_pops <= '0;
        end else begin
            perf_ibf_stalls <= perf_ibf_stalls + `PERF_CTR_BITS'(decode_if_stall);
            for (i = 0; i < PER_ISSUE_WARPS; i = i + 1) begin
                if (ibuffer_if[i].valid && ibuffer_if[i].ready)
                    perf_ibf_pops <= perf_ibf_pops + `PERF_CTR_BITS'(1);
            end
        end
    end

    assign perf_stalls = perf_ibf_stalls;
    assign perf_ibf_pops_out = perf_ibf_pops;
`endif
*/
`ifdef PERF_ENABLE
    // Existing ibuffer stall counter
    reg [`PERF_CTR_BITS-1:0] perf_ibf_stalls;
    wire decode_if_stall = decode_if.valid && ~decode_if.ready;
    always @(posedge clk) begin
        if (reset) begin
            perf_ibf_stalls <= '0;
        end else begin
            perf_ibf_stalls <= perf_ibf_stalls + `PERF_CTR_BITS'(decode_if_stall);
        end
    end
    assign perf_stalls = perf_ibf_stalls;

    // New Performance Counter: IBF Pops
    wire [PER_ISSUE_WARPS-1:0] ibuf_pop_events;
    genvar j;
    generate
        for (j = 0; j < PER_ISSUE_WARPS; j = j + 1) begin : gen_ibuf_pop
            assign ibuf_pop_events[j] = ibuffer_if[j].valid && ~ibuffer_if[j].ready;
        end
    endgenerate

    // $countones returns the number of bits set to 1.
    reg [`PERF_CTR_BITS-1:0] perf_ibf_pops;
    always @(posedge clk) begin
        if (reset) begin
            perf_ibf_pops <= '0;
        end else begin
            // Add the number of pop events (from all instances) to the accumulator.
            perf_ibf_pops <= perf_ibf_pops + `PERF_CTR_BITS'($countones(ibuf_pop_events));
        end
    end

    assign perf_ibf_pops_out = perf_ibf_pops;
`endif

endmodule
