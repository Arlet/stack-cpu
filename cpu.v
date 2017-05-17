/*
 * CPU module
 *
 * (C) Arlet Ottens
 *
 *   8   7   6   5   4   3   2   1   0
 * +---+---+---+---+---+---+---+---+---+	
 * | 0 |            literal            |   push literal value on A stack
 * +---+---+---+---+---+---+---+---+---+ 
 * | 1   0   0 |   cond    |    rel    |   branch if cond
 * +---+---+---+---+---+---+---+---+---+
 * | 1   0   1   0 | r | x |   offset  |   load (r, #offset)  r=X/~R
 * +---+---+---+---+---+---+---+---+---+
 * | 1   0   1   1 | r | x |   offset  |   store (r, #offset)
 * +---+---+---+---+---+---+---+---+---+
 * | 1   1   0   0 |    op1    |  src  |   A = <op1> {src}
 * +---+---+---+---+---+---+---+---+---+	
 * | 1   1   0   1 |    op2    |  src  |   A = A <op2> {src}
 * +---+---+---+---+---+---+---+---+---+	
 * | 1   1   1   0   0 | x | abs[10:8] |   jmp {abs, A}
 * +---+---+---+---+---+---+---+---+---+ 
 * | 1   1   1   0   1 | x | abs[10:8] |   call {abs, A}
 * +---+---+---+---+---+---+---+---+---+
 * | 1   1   1   1   0 |  dst  |  src  |   move (dup when src == dst)
 * +---+---+---+---+---+---+---+---+---+
 * | 1   1   1   1   1   0   0 |  src  |   ret {src}
 * +---+---+---+---+---+---+---+---+---+
 * | 1   1   1   1   1   1   0 | stack |   drop 
 * +---+---+---+---+---+---+---+---+---+
 * | 1   1   1   1   1   1   1   0   0 |   nop 
 * +---+---+---+---+---+---+---+---+---+
 *
 * rel | pc			 op | op2    op1  
 * ----+----			----+-----------
 * 0   | -6                       0 |  +     not 
 * 1   | -5                       1 |  -     swap 
 * 2   | -4                       2 | and    asr 
 * 3   | -3                       3 | 
 * 4   | -2                       4 | 
 * 5   | +2                       5 |
 * 6   | +3                       6 |
 * 7   | +4                       7 |
 *
 * stack |
 * ------+---
 * 0     | A
 * 1     | X
 * 2     | Y
 * 3     | R
 *
 */

module cpu( clock, reset, 
	    ext_we, ext_re, ext_addr, ext_out, ext_in, 
            shmem_clock, shmem_we, shmem_en, shmem_addr, shmem_out, shmem_in );

input clock;
input reset;

// external memory interface
output ext_we;
output ext_re;
output [15:0] ext_addr;
output [17:0] ext_out;
input  [17:0] ext_in;

// byte wide data memory interface
input shmem_clock;
input shmem_en;
input shmem_we;
input [15:0] shmem_addr;
output [8:0] shmem_out;
input  [8:0] shmem_in;


reg load;
wire store = ~load;

reg [17:0] a;		  // top of A stack (accumulator)
reg [17:0] x;		  // top of X stack (index)
reg [17:0] r;		  // top of R stack (return)
reg [10:0] pc;		  // program counter
reg [10:0] pc_1;	  // program counter delayed
reg [9:0] asp;		  // A stack pointer
reg [9:0] xsp;		  // X stack pointer
reg [9:0] rsp;		  // R stack pointer
wire [8:0] ir;		  // instruction register

wire [2:0] cond = ir[5:3];
wire [2:0] rel  = ir[2:0];
wire [2:0] abs3 = ir[2:0];
wire [1:0] src_stack = ir[1:0];
wire [1:0] dst_stack = ir[3:2];

wire lit    = ir[8]   == 1'b0;
wire branch = ir[8:6] == 3'b100; 
wire mem_ld = ir[8:5] == 4'b1010;
wire mem_st = ir[8:5] == 4'b1011;
wire op1    = ir[8:5] == 4'b1100;
wire op2    = ir[8:5] == 4'b1101;
wire jump   = ir[8:4] == 5'b11100; 
wire call   = ir[8:4] == 5'b11101;
wire move   = ir[8:4] == 5'b11110;
wire ret    = ir[8:2] == 7'b1111100;
wire drop   = ir[8:2] == 7'b1111110;
wire ea_reg = ir[4];

parameter
	A = 2'b00,
	X = 2'b01,
	Y = 2'b10,
	R = 2'b11;

wire dup = move & (src_stack == dst_stack);
wire pop = ret | drop | op2 | (move & ~dup);

// a control
wire pusha   = lit | mem_ld | (move & dst_stack == A);
wire popa    = branch | jump | call | mem_st | (pop & (src_stack == A));

// x control
wire pushx   = (move & dst_stack == X);
wire popx    = (pop | op1) & (src_stack == X);

// r control
wire pushr   = call | (move & dst_stack == R);
wire popr    = (pop | op1) & (src_stack == R);

parameter
	NOP	= 9'h164;

reg [10:0] pc_inc;	// program counter increment
reg [17:0] res;		// result bus

// alu
reg [17:0] oper2;
wire [15:0] addsub_out;
wire addsub_co;
wire addsub_lt;

// conditions & flags
wire flag_z  = ~|a[15:0];
wire flag_n  = a[15];
wire flag_lt = a[16];
wire flag_c  = a[17];
reg condition;

parameter
	EQ = 2'b00,
	CS = 2'b01,
	MI = 2'b10,
	LT = 2'b11;

// memory interface

reg [17:0] wrdata;
wire [17:0] rddata;
reg [15:0] memaddr;
wire extern = |memaddr[15:10];
reg extern_1;
reg [15:0] ea;
wire data_we = store & (pusha | pushx | pushr | mem_st);

assign ext_we = extern & mem_st;
assign ext_re = extern & mem_ld;
assign ext_addr = ea;
assign ext_out = wrdata;

RAMB16_S9 code( 
	.WE(1'b0),
	.EN(1'b1),
	.SSR(1'b0),
	.CLK(clock),
	.ADDR(pc),
	.DO(ir[7:0]),
	.DOP(ir[8])
	);

// 9/18 bit wide RAM for data and stacks
RAMB16_S9_S18 data( 		      	
	.WEA(shmem_we),			// shared memory port
	.ENA(shmem_en),
	.SSRA(1'b0),
	.CLKA(shmem_clock),
	.ADDRA(shmem_addr),
	.DIA(shmem_in[7:0]),
	.DIPA(shmem_in[8]),
	.DOA(shmem_out[7:0]),
	.DOPA(shmem_out[8]),

	.WEB(data_we & ~extern),	// CPU port
	.ENB(1'b1),
	.SSRB(1'b0),
	.CLKB(clock),
	.ADDRB(memaddr[9:0]),
	.DIB(wrdata[15:0]),
	.DIPB(wrdata[17:16]),
	.DOB(rddata[15:0]),
	.DOPB(rddata[17:16]) );

/*
 * ALU
 */
addsub addsub( 
	.sub(ir[2]), 
	.a(oper2), 
	.b(a), 
	.ci(ir[2]), 
	.co(addsub_co),
	.lt(addsub_lt),
	.s(addsub_out) );

always @(src_stack or rddata or a or x or r or op1)
    if( src_stack == X )
        oper2 = x;
    else if( src_stack == R )
        oper2 = r;
    else if( op1 )
        oper2 = a;
    else
        oper2 = rddata;

always @(a or rddata or ir or addsub_out or addsub_lt or addsub_co
	 or move or ret or src_stack or x or r or lit or op1 
	 or op2 or mem_ld or call or pc_1 or oper2 or extern_1 or ext_in)  
begin
    res = a;
    if( mem_ld & extern_1 )
	res = ext_in;
    else if( mem_ld & ~extern_1 )
        res = rddata;
    else if( lit )
        res = { 8'b0, ir[7:0] };
    else if( move | ret )
        case( src_stack )
	    A   : res = a;
	    X, Y: res = x;
	    R   : res = r;
	endcase
    else if( op1 | op2 )
        casez( ir[5:2] )
	    4'b0000 : res = { 1'b0, 1'b0, ~oper2 };
	    4'b0001 : res = { 1'b0, 1'b0, oper2[7:0], oper2[15:8] };
	    4'b0010 : res = { oper2[0], 1'b0, oper2[15], oper2[15:1] };
	    4'b100? : res = { addsub_co, addsub_lt, addsub_out };
	    4'b1010 : res = { 1'b0, 1'b0, a[15:0] & oper2[15:0] };
	endcase
    else if( call )
        res = pc_1;
end

/*
 * conditional evaluation
 */

always @(a or cond or flag_z or flag_c or flag_n or flag_lt) begin
    case( cond[2:1] )
       EQ: condition = flag_z;
       CS: condition = flag_c;
       MI: condition = flag_n;
       LT: condition = flag_lt;
    endcase
    if( cond[0] )
	condition = ~condition;
end

/*
 * local memory access 
 */

always @(posedge clock)
    extern_1 <= extern;

always @(a or pushx or x or pushr or r)
    if( pushx )
        wrdata = x;
    else if( pushr )
        wrdata = r;
    else
	wrdata = a; 

always @(store or asp or xsp or rsp 
         or pushx or pushr or popx or popr 
	 or mem_ld or mem_st or ea )
    if( (store & pushx) | (~store & popx) )
        memaddr = xsp;
    else if( (store & pushr) | (~store & popr) )
	memaddr = rsp;
    else if( (store & mem_st) | (~store & mem_ld) )
        memaddr = ea; 
    else
        memaddr = asp;

always @(x or r or ea_reg or rel)
    ea = (ea_reg ? r : x ) + { 8'b0, rel };

/*
 * Program counter
 */

always @(posedge clock or posedge reset)
    if( reset ) 
        load  <= 0;
    else
        load  <= ~load;

always @(rel)
    case( rel )
        3'b000: pc_inc = -10'd6;
        3'b001: pc_inc = -10'd5;
        3'b010: pc_inc = -10'd4;
        3'b011: pc_inc = -10'd3;
        3'b100: pc_inc = -10'd2;
        3'b101: pc_inc =  10'd2;
        3'b110: pc_inc =  10'd3;
        3'b111: pc_inc =  10'd4;
    endcase

always @(posedge clock)
    pc_1 <= pc + 1;

always @(posedge clock or posedge reset)
    if( reset ) 
        pc <= 0;
    else if( load ) begin
        if( ret )
	    pc <= res;
	else if( jump | call )
	    pc <= { abs3, a[7:0] };
	else if( branch & condition )
	    pc <= pc + pc_inc;
	else
	    pc <= pc + 1;
    end

// A stack

always @(posedge clock)
    if( store & (pusha | op1 | op2) )
	a <= res;
    else if( store & popa )
	a <= rddata;

always @(posedge clock or posedge reset)
    if( reset )
        asp <= 0;
    else if( load & pusha )
        asp <= asp + 1;
    else if( load & popa )
        asp <= asp - 1;

// X stack

always @(posedge clock)
    if( store & pushx )
        x <= res;
    else if( store & popx )
        x <= rddata;

always @(posedge clock or posedge reset)
    if( reset )
        xsp <= 9'h20;
    else if( load & pushx )
        xsp <= xsp + 1;
    else if( load & popx )
        xsp <= xsp - 1;

// R stack

always @(posedge clock)
    if( store & pushr )
        r <= res;
    else if( store & popr )
        r <= rddata;

always @(posedge clock or posedge reset)
    if( reset )
        rsp <= 9'h40;
    else if( load & pushr )
        rsp <= rsp + 1;
    else if( load & popr )
        rsp <= rsp - 1;

endmodule

    
