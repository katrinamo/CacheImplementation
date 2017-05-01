// basic sizes of things
`define WORD  [15:0]
`define Opcode  [15:12]
`define Immed [11:0]
`define OP  [7:0]
`define PRE [3:0]
`define REGSIZE [511:0] // 256 for each PID
`define REGNUM  [7:0]
`define MEMSIZE [65535:0]

//slowmem stuff
`define PID [1:0]
`define WORD [15:0]
`define MEMSIZE [65535:0]
`define MEMDELAY 4

//cache stuff
`define CACHESIZE [7:0]

// pid-dependent things
`define PID0  (pid)
`define PID1  (!pid)
`define PC0 pc[`PID0]
`define PC1 pc[`PID1]
`define PRESET0 preset[`PID0]
`define PRESET1 preset[`PID1]
`define PRE0  pre[`PID0]
`define PRE1  pre[`PID1]
`define TORF0 torf[`PID0]
`define TORF1 torf[`PID1]
`define SP0 sp[`PID0]
`define SP1 sp[`PID1]
`define HALT0 halts[`PID0]
`define HALT1 halts[`PID1]

// opcode values hacked into state numbers
`define OPAdd {4'h0, 4'h0}
`define OPSub {4'h0, 4'h1}
`define OPTest  {4'h0, 4'h2}
`define OPLt  {4'h0, 4'h3}

`define OPDup {4'h0, 4'h4}
`define OPAnd {4'h0, 4'h5}
`define OPOr  {4'h0, 4'h6}
`define OPXor {4'h0, 4'h7}

`define OPLoad  {4'h0, 4'h8}
`define OPStore {4'h0, 4'h9}

`define OPRet {4'h0, 4'ha}
`define OPSys {4'h0, 4'hb}

`define OPPush  {4'h1, 4'h0}

`define OPCall  {4'h4, 4'h0}
`define OPJump  {4'h5, 4'h0}
`define OPJumpF {4'h6, 4'h0}
`define OPJumpT {4'h7, 4'h0}

`define OPGet {4'h8, 4'h0}
`define OPPut {4'h9, 4'h0}
`define OPPop {4'ha, 4'h0}
`define OPPre {4'hb, 4'h0}

`define OPNOP {4'hf, 4'hf}

`define NOREG   255

module processor(halt, reset, clk);
output halt;
input reset, clk;

reg `WORD r `REGSIZE;
//reg `WORD m `MEMSIZE;
  reg mfc;
  reg `WORD rdata, addr, wdata;
  reg rnotw, strobe;
  slowmem m(mfc, rdata, addr, wdata, rnotw, strobe, clk);
reg `WORD pc `PID;
wire `OP op;
reg `OP s0op, s1op, s2op;
reg `REGNUM sp `PID;
reg `REGNUM s0d, s1d, s2d, s0s, s1s;
reg `WORD s0immed, s1immed, s2immed;
reg `WORD s1sv, s1dv, s2sv, s2dv;
wire `WORD ir;
reg `WORD immed;
wire teststall, retstall, writestall;
reg `PID torf, preset, halts;
reg `PRE pre `PID;
reg pid;
  reg `PID hit;
  

always @(posedge reset) begin
  //halt <= 0;
  `SP0 <= 0;
  `SP1 <= 0;
  `PC0 <= 0;
  `PC1 <= 16'h8000;
  `HALT0 <= 0;
  `HALT1 <= 0;
end

// Halted?
assign halt = (HALT0 && HALT1);

// Stall for Test?
assign teststall = (s1op == `OPTest);

// Stall for Ret?
assign retstall = (s1op == `OPRet);

// Instruction fetch interface
//assign ir = m[`PC0];
//assign op = {(ir `Opcode), (((ir `Opcode) == 0) ? ir[3:0] : 4'd0)};
  
  instr_cache instructioncache(clk, reset, `PCO, ir, hit[0], rdata, rnotw, mfc);
  instr_cache instructioncache(clk, reset, `PC1, ir, hit[1], rdata, rnotw, mfc);
// Instruction fetch
always @(posedge clk) begin
  // set immed, accounting for pre
  case (op)
    `OPPre: begin
      `PRE0 <= ir `PRE;
      `PRESET0 <= 1;
      immed = ir `Immed;
    end
    `OPCall,
    `OPJump,
    `OPJumpF,
    `OPJumpT: begin
      if (`PRESET0) begin
  immed = {`PRE0, ir `Immed};
  `PRESET0 <= 0;
      end else begin
  // Take top bits of pc
  immed <= {`PC0[14:12], ir `Immed};
      end
    end
    `OPPush: begin
      if (`PRESET0) begin
  immed = {`PRE0, ir `Immed};
  `PRESET0 <= 0;
      end else begin
  // Sign extend
  immed = {{4{ir[11]}}, ir `Immed};
      end
    end
    default:
      immed = ir `Immed;
  endcase

  // set s0immed, pc, s0op, halt
  case (op)
    `OPPre: begin
      s0op <= `OPNOP;
      `PC0 <= `PC0 + 1;
    end
    `OPCall: begin
      s0immed <= `PC0 + 1;
      `PC0 <= immed;
      s0op <= `OPCall;
    end
    `OPJump: begin
      `PC0 <= immed;
      s0op <= `OPNOP;
    end
    `OPJumpF: begin
      if (teststall == 0) begin
  `PC0 <= (`TORF0 ? (`PC0 + 1) : immed);
      end else begin
  `PC0 <= `PC0 + 1;
      end
      s0op <= `OPNOP;
    end
    `OPJumpT: begin
      if (teststall == 0) begin
  `PC0 <= (`TORF0 ? immed : (`PC0 + 1));
      end else begin
  `PC0 <= `PC0 + 1;
      end
      s0op <= `OPNOP;
    end
    `OPRet: begin
      if (retstall) begin
  s0op <= `OPNOP;
      end else if (s2op == `OPRet) begin
  s0op <= `OPNOP;
  `PC0 <= s1sv;
      end else begin
  s0op <= op;
      end
    end
    `OPSys: begin
      // basically idle this thread
      s0op <= `OPNOP;
      `HALT0 <= ((s0op == `OPNOP) && (s1op == `OPNOP) && (s2op == `OPNOP));
    end
    default: begin
      s0op <= op;
      s0immed <= immed;
      `PC0 <= `PC0 + 1;
    end
  endcase
end

// Instruction decode
always @(posedge clk) begin
  case (s0op)
    `OPAdd,
    `OPSub,
    `OPLt,
    `OPAnd,
    `OPOr,
    `OPXor,
    `OPStore:
      begin s1d <= `SP1-1; s1s <= `SP1; `SP1 <= `SP1-1; end
    `OPTest:
      begin s1d <= `NOREG; s1s <= `SP1; `SP1 <= `SP1-1; end
    `OPDup:
      begin s1d <= `SP1+1; s1s <= `SP1; `SP1 <= `SP1+1; end
    `OPLoad:
      begin s1d <= `SP1; s1s <= `SP1; end
    `OPRet:
      begin s1d <= `NOREG; s1s <= `NOREG; `PC1 <= r[{`PID1, `SP1}]; `SP1 <= `SP1-1; end
    `OPPush:
      begin s1d <= `SP1+1; s1s <= `NOREG; `SP1 <= `SP1+1; end
    `OPCall:
      begin s1d <= `SP1+1; s1s <= `NOREG; `SP1 <= `SP1+1; end
    `OPGet:
      begin s1d <= `SP1+1; s1s <= `SP1-(s0immed `REGNUM); `SP1 <= `SP1+1; end
    `OPPut:
      begin s1d <= `SP1-(s0immed `REGNUM); s1s <= `SP1; end
    `OPPop:
      begin s1d <= `NOREG; s1s <= `NOREG; `SP1 <= `SP1-(s0immed `REGNUM); end
    default:
      begin s1d <= `NOREG; s1s <= `NOREG; end
  endcase
  s1op <= s0op;
  s1immed <= s0immed;
end

// Register read
always @(posedge clk) begin
  s2dv <= ((s1d == `NOREG) ? 0 : r[{`PID0, s1d}]);
  s2sv <= ((s1s == `NOREG) ? 0 : r[{`PID0, s1s}]);
  s2d <= s1d;
  s2op <= s1op;
  s2immed <= s1immed;
end

// ALU or data memory access and write
always @(posedge clk) begin
  case (s2op)
    `OPAdd: begin r[{`PID1, s2d}] <= s2dv + s2sv; end
    `OPSub: begin r[{`PID1, s2d}] <= s2dv - s2sv; end
    `OPTest: begin `TORF1 <= (s2sv != 0); end
    `OPLt: begin r[{`PID1, s2d}] <= (s2dv < s2sv); end
    `OPDup: begin r[{`PID1, s2d}] <= s2sv; end
    `OPAnd: begin r[{`PID1, s2d}] <= s2dv & s2sv; end
    `OPOr: begin r[{`PID1, s2d}] <= s2dv | s2sv; end
    `OPXor: begin r[{`PID1, s2d}] <= s2dv ^ s2sv; end
    `OPLoad: begin r[{`PID1, s2d}] <= m[s2sv]; end
    `OPStore: begin m[s2dv] <= s2sv; end
    `OPPush,
    `OPCall: begin r[{`PID1, s2d}] <= s2immed; end
    `OPGet,
    `OPPut: begin r[{`PID1, s2d}] <= s2sv; end
  endcase
end
endmodule


                               module instr_cache(clk, reset, instrAddr, instruction, hit, rdata, rnotw, mfc);
input wire clk;
input wire reset;

//Input instruction address >> output instruction (DECODED)
input wire `WORD instrAddr;
output wire `WORD instruction;

//If in cache hit=1
output wire hit;

//If miss, find instr using memoryIn
input wire `WORD memoryIn;

//Output read Data = 1 to slow mem if need read along w/strobe
output reg readData;
output reg strobe;

//Wait for mfc to signal complete fetch
input wire mfc;

reg `CACHESIZE cache;

intial begin

endmodule


module slowmem(mfc, rdata, addr, wdata, rnotw, strobe, clk);
output reg mfc;
output reg `WORD rdata;
input `WORD addr, wdata;
input rnotw, strobe, clk;
reg [7:0] pend;
reg `WORD raddr;
reg `WORD m `MEMSIZE;
//reg `WORD r `REGSIZE;

initial begin
  pend <= 0;
//  $readmemh0(r);
  $readmemh1(m);
end

always @(posedge clk) begin
  if (strobe && rnotw) begin
    // new read request
    raddr <= addr;
    pend <= `MEMDELAY;
  end else begin
    if (strobe && !rnotw) begin
      // do write
      m[addr] <= wdata;
    end

    // pending read?
    if (pend) begin
      // write satisfies pending read
      if ((raddr == addr) && strobe && !rnotw) begin
        rdata <= wdata;
        mfc <= 1;
        pend <= 0;
      end else if (pend == 1) begin
        // finally ready
        rdata <= m[raddr];
        mfc <= 1;
        pend <= 0;
      end else begin
        pend <= pend - 1;
      end
    end else begin
      // return invalid data
      rdata <= 16'hxxxx;
      mfc <= 0;
    end
  end
end
endmodule

module testbench;
reg reset = 0;
reg clk = 0;
wire halted;
processor PE(halted, reset, clk);
initial begin
  $dumpfile;
  $dumpvars(0, PE);
  #10 reset = 1;
  #10 reset = 0;
  while (!halted) begin
    #10 clk = 1;
    #10 clk = 0;
  end
  $finish;
end
endmodule
