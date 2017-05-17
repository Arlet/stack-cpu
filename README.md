CPU module using 4 stacks (A, X, Y, and R). The R stack is also used
for return address. The Y stack is not implemented, although there's 
room in the opcode field.

(C) Arlet Ottens

<pre>
  8   7   6   5   4   3   2   1   0
+---+---+---+---+---+---+---+---+---+	
| 0 |            literal            |   push literal value on A stack
+---+---+---+---+---+---+---+---+---+ 
| 1   0   0 |   cond    |    rel    |   branch if cond
+---+---+---+---+---+---+---+---+---+
| 1   0   1   0 | r | x |   offset  |   load (r, #offset)  r=X/~R
+---+---+---+---+---+---+---+---+---+
| 1   0   1   1 | r | x |   offset  |   store (r, #offset)
+---+---+---+---+---+---+---+---+---+
| 1   1   0   0 |    op1    |  src  |   A = <op1> {src}
+---+---+---+---+---+---+---+---+---+	
| 1   1   0   1 |    op2    |  src  |   A = A <op2> {src}
+---+---+---+---+---+---+---+---+---+	
| 1   1   1   0   0 | x | abs[10:8] |   jmp {abs, A}
+---+---+---+---+---+---+---+---+---+ 
| 1   1   1   0   1 | x | abs[10:8] |   call {abs, A}
+---+---+---+---+---+---+---+---+---+
| 1   1   1   1   0 |  dst  |  src  |   move (dup when src == dst)
+---+---+---+---+---+---+---+---+---+
| 1   1   1   1   1   0   0 |  src  |   ret {src}
+---+---+---+---+---+---+---+---+---+
| 1   1   1   1   1   1   0 | stack |   drop 
+---+---+---+---+---+---+---+---+---+
| 1   1   1   1   1   1   1   0   0 |   nop 
+---+---+---+---+---+---+---+---+---+

rel | pc			 op | op2    op1  
----+----			----+-----------
0   | -6                       0 |  +     not 
1   | -5                       1 |  -     swap 
2   | -4                       2 | and    asr 
3   | -3                       3 | 
4   | -2                       4 | 
5   | +2                       5 |
6   | +3                       6 |
7   | +4                       7 |

stack |
------+---
0     | A
1     | X
2     | Y
3     | R
</pre>
