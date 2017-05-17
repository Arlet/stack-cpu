module addsub( sub, a, b, ci, s, co, lt );
        input sub;
	input [15:0] a;
	input [15:0] b;
	input ci;
	output [15:0] s;
	output co;
	output lt;

wire [15:0] b_add = sub ? ~b : b;
wire [16:0] temp = a + b_add + ci;

assign s = temp[15:0];
assign co = temp[16];
assign lt = ((a[15] == b_add[15]) & (a[15] != s[15])) ^ s[15];

endmodule
