% ----------------------------------------------------
% Fibonacci (Big Integer) - bounded arbitrary precision
% BigInt = MAXLIMBS limbs, each limb is 64-bit unsigned
% Little-endian limbs: limb[0] is least significant
%
% Result pointer is returned in Arg2 (after Fibonacci returns)
% ----------------------------------------------------

% ----------------------------------------------------
% Constants
% ----------------------------------------------------
Zero    IS      $255
Arg0    IS      $32              % global arg registers (persist across calls)
Arg1    IS      $33
Arg2    IS      $34
MAXLIMBS IS     32              % 32 * 64 = 2048 bits
Halt    IS      0
Fputs   IS      7
StdOut  IS      1

% ----------------------------------------------------
% Data Segment
% ----------------------------------------------------
        LOC     #1000

% String data
ResultMsg BYTE  "fib(100) = ",0
Newline  BYTE   10,0

% Working buffers for big integers (32 limbs = 256 bytes each)
        LOC     #2000
BufA    OCTA    0
        LOC     #2100
BufB    OCTA    0
        LOC     #2200

% Conversion buffers
TempBuf   OCTA   0
        LOC     #2400
Remainder OCTA   0               % (unused; safe to keep)
        LOC     #2408
OutputStr BYTE   0               % Output string buffer (up to 617 digits)
        LOC     #2800
DigitBuf  BYTE   0               % Digit collection buffer
        LOC     #2C00

% ----------------------------------------------------
% Code Segment
% ----------------------------------------------------
        LOC     #100
        JMP     Main

% ====================================================
% Main Program
% ====================================================
Main
        % Initialize pointers
        GETA    $6,BufA              % $6 = &A
        GETA    $7,BufB              % $7 = &B

        % Zero all buffers (A, B) via shared routine
        SET     Arg0,$6              % pointer = A
        SETI    Arg1,MAXLIMBS        % limbs to clear
        PUSHJ   $31,ZeroBuf

        SET     Arg0,$7              % pointer = B
        SETI    Arg1,MAXLIMBS
        PUSHJ   $31,ZeroBuf

        % Compute fib(100)
        SETI    Arg0,100             % n = 100
        SET     Arg1,$6              % buffer A
        SET     Arg2,$7              % buffer B
        PUSHJ   $31,Fibonacci        % Arg2 updated to point at result

% ====================================================
% Convert Result and Output
% ====================================================
Done
        % Build decimal string representation of result
        SET     $10,Arg2             % pointer to result buffer
        GETA    $11,OutputStr        % pointer to output buffer
        PUSHJ   $31,BigIntToDecStr

        % Print the result string
        GETA    $0,ResultMsg
        TRAP    0,Fputs,StdOut
        GETA    $0,OutputStr
        TRAP    0,Fputs,StdOut
        GETA    $0,Newline
        TRAP    0,Fputs,StdOut

        TRAP    0,Halt,0

% ====================================================
% Subroutines
% ====================================================

% ----------------------------------------------------
% ZeroBuf - zero out a buffer of limbs
% Input: Arg0 = pointer to buffer
%        Arg1 = limb count
% ----------------------------------------------------
ZeroBuf
        SETI    $12,0
ZeroLoop
        CMP     $13,$12,Arg1
        BNN     $13,ZeroBufReturn
        SLI     $14,$12,3
        STOU    Zero,Arg0,$14
        ADDUI   $12,$12,1
        JMP     ZeroLoop
ZeroBufReturn
        POP     0,0

% ----------------------------------------------------
% Fibonacci - Compute nth Fibonacci number
% Input: Arg0 = n
%        Arg1 = pointer to buffer A
%        Arg2 = pointer to buffer B
% Output: Arg2 updated to point to result buffer on return
%
% Improvements vs original:
%   - keep n in a local ($24) so we don't save/restore Arg0 each iteration
%   - avoid saving/restoring Arg1/Arg2 each iteration (we already have $21/$22)
%   - keep Arg1/Arg2 as the live A/B pointers for clarity at return
% ----------------------------------------------------
Fibonacci
        SET     $24,Arg0             % local copy of n (avoid per-iter save/restore)

        % Handle n==0: result is A (already zero)
        CMP     $10,$24,Zero
        BZ      $10,FibN0

        % Set B[0] = 1 for n>=1
        SETI    $11,1
        STOU    $11,Arg2,Zero

        % Handle n==1: result is B
        SETI    $12,1
        CMP     $10,$24,$12
        BZ      $10,FibReturnResult

        % Main loop: compute fib(2) through fib(n)
        SETI    $13,2                % i = 2
FibLoop
        CMP     $14,$13,$24
        BP      $14,FibReturnResult  % if i > n, done

        % Snapshot current pointers into locals (no need to save n)
        SET     $21,Arg1             % A
        SET     $22,Arg2             % B

        % In-place: A := A + B  (dest aliases A)
        SET     Arg0,$21             % A (src)
        SET     Arg1,$22             % B (src)
        SET     Arg2,$21             % A (dest)
        PUSHJ   $31,MPAddWithCarry

        % Pointer swap: (A,B) := (B,A)
        SET     $23,$21              % tmp = A
        SET     $21,$22              % A = B
        SET     $22,$23              % B = tmp

        % Commit current pointers back to Arg regs (Arg2 always B/result)
        SET     Arg1,$21
        SET     Arg2,$22

        ADDUI   $13,$13,1
        JMP     FibLoop

FibReturnResult
        % Result pointer is current B in Arg2
        POP     0,0

FibN0
        % n==0: result is A, so make Arg2 point at A for caller
        SET     Arg2,Arg1
        POP     0,0

% ----------------------------------------------------
% MPAddWithCarry - Multi-precision addition with carry
% Input: Arg0 = pointer to buffer A
%        Arg1 = pointer to buffer B
%        Arg2 = pointer to dest buffer (T = A + B), may alias Arg0 (in-place)
% ----------------------------------------------------
MPAddWithCarry
        SETI    $10,0
        SETI    $14,0
        SETI    $22,MAXLIMBS
MPALoop
        CMP     $15,$10,$22
        BNN     $15,MPADone

        SLI     $21,$10,3
        LDOU    $16,Arg0,$21
        LDOU    $17,Arg1,$21

        ADDU    $18,$16,$17
        CMPU    $19,$18,$16
        BN      $19,MPAC1Yes
        SETI    $19,0
        JMP     MPAC1Done
MPAC1Yes
        SETI    $19,1
MPAC1Done

        ADDU    $20,$18,$14
        CMPU    $15,$20,$18
        BN      $15,MPAC2Yes
        SETI    $15,0
        JMP     MPAC2Done
MPAC2Yes
        SETI    $15,1
MPAC2Done

        STOU    $20,Arg2,$21
        OR      $14,$19,$15

        ADDUI   $10,$10,1
        JMP     MPALoop
MPADone
        POP     0,0

% ----------------------------------------------------
% BigIntToDecStr - Convert big integer to decimal string
% Input: $10 = pointer to big integer buffer
%        $11 = pointer to output string buffer
% ----------------------------------------------------
BigIntToDecStr
        % Copy input to TempBuf (we'll modify it during conversion)
        SETI    $12,0
        GETA    $13,TempBuf
        SETI    $14,MAXLIMBS
CopyLoop
        CMP     $15,$12,$14
        BNN     $15,CopyDone
        SLI     $16,$12,3
        LDOU    $17,$10,$16
        STOU    $17,$13,$16
        ADDUI   $12,$12,1
        JMP     CopyLoop
CopyDone

        % Extract decimal digits by repeatedly dividing by 10
        SETI    $12,0

ExtractDigits
        % Check if TempBuf is zero
        GETA    $13,TempBuf
        SETI    $14,0
        SETI    $15,MAXLIMBS
CheckZero
        CMP     $16,$14,$15
        BNN     $16,IsZero
        SLI     $17,$14,3
        LDOU    $18,$13,$17
        BNZ     $18,NotZero
        ADDUI   $14,$14,1
        JMP     CheckZero

IsZero
        BZ      $12,WasZero
        JMP     ReverseDigits

WasZero
        SETI    $16,48
        STBU    $16,$11,Zero
        SETI    $16,1
        STBU    Zero,$11,$16
        JMP     BigIntReturn

NotZero
        GETA    $13,TempBuf
        PUSHJ   $26,DivBy10
        SET     $9,$26
        ADDUI   $9,$9,48
        GETA    $14,DigitBuf
        STBU    $9,$14,$12
        ADDUI   $12,$12,1
        JMP     ExtractDigits

ReverseDigits
        SETI    $13,0
RevLoop
        CMP     $14,$13,$12
        BNN     $14,RevDone
        SUBUI   $15,$12,1
        SUBU    $15,$15,$13
        GETA    $16,DigitBuf
        LDBU    $17,$16,$15
        STBU    $17,$11,$13
        ADDUI   $13,$13,1
        JMP     RevLoop
RevDone
        STBU    Zero,$11,$13
BigIntReturn
        POP     0,0

% ----------------------------------------------------
% DivBy10 - Divide big integer by 10 in place
% Input: $13 = pointer to big integer buffer
% Output: remainder returned via POP (caller sees it in $26)
% ----------------------------------------------------
DivBy10
        SETI    $9,0
        SETI    $14,MAXLIMBS
        SUBUI   $14,$14,1

DivLoop
        BN      $14,DivDone
        SLI     $15,$14,3
        LDOU    $16,$13,$15

        SETI    $17,0
        SETI    $18,64

BitLoop
        BZ      $18,LimbDone
        SLI     $9,$9,1
        SETI    $22,63
        SRU     $23,$16,$22
        OR      $9,$9,$23
        SLI     $16,$16,1

        SLI     $17,$17,1

        SETI    $24,10
        CMP     $25,$9,$24
        BN      $25,SkipSub
        SUBU    $9,$9,$24
        ORI     $17,$17,1
SkipSub
        SUBUI   $18,$18,1
        JMP     BitLoop

LimbDone
        STOU    $17,$13,$15
        SUBUI   $14,$14,1
        JMP     DivLoop

DivDone
        SET     $0,$9
        POP     1,0