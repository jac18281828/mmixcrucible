% ----------------------------------------------------
% Fibonacci (Big Integer) - bounded arbitrary precision
% BigInt = MAXLIMBS limbs, each limb is 64-bit unsigned
% Little-endian limbs: limb[0] is least significant
%
% Computes fib(n) where n is in $1
% Result is in BufB
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
Newline BYTE    10,0

% Working buffers for big integers (32 limbs = 256 bytes each)
        LOC     #2000
BufA    OCTA    0
        LOC     #2100

BufB    OCTA    0
        LOC     #2200

BufT    OCTA    0
        LOC     #2300

% Conversion buffers
TempBuf OCTA    0
        LOC     #2400

Remainder OCTA  0               % scratch for DivBy10 remainder
        LOC     #2408

OutputStr BYTE  0               % Output string buffer (up to 617 digits)
        LOC     #2800

DigitBuf BYTE   0               % Digit collection buffer
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
        GETA    $8,BufT              % $8 = &T
        
        % Zero all buffers (A, B, T) via shared routine
        SET     Arg0,$6            % pointer = A
        SETI    Arg1,MAXLIMBS      % limbs to clear
        PUSHJ   $31,ZeroBuf        % save broad register set, call

        SET     Arg0,$7            % pointer = B
        SETI    Arg1,MAXLIMBS
        PUSHJ   $31,ZeroBuf

        SET     Arg0,$8            % pointer = T
        SETI    Arg1,MAXLIMBS
        PUSHJ   $31,ZeroBuf

        % Compute fib(100)
        SETI    Arg0,100           % n = 100
        SET     Arg1,$6            % buffer A
        SET     Arg2,$7            % buffer B
        PUSHJ   $31,Fibonacci

% ====================================================
% Convert Result and Output
% ====================================================
Done
        % Build decimal string representation of BufB
        OR      $10,$7,Zero           % pointer to BufB
        GETA    $11,OutputStr         % pointer to output buffer
        PUSHJ   $31,BigIntToDecStr    % save caller regs, convert to decimal
        
        % Print the result string
        GETA    $0,ResultMsg
        TRAP    0,Fputs,StdOut
        GETA    $0,OutputStr
        TRAP    0,Fputs,StdOut
        GETA    $0,Newline
        TRAP    0,Fputs,StdOut
        
        TRAP    0,Halt,0

% Expected fib(100) = 354224848179261915075
% In hex (little-endian limbs):
%   Limb 0: 0xCC2B73A0CA855B83
%   Limb 1: 0x1D8A758E36AFA2B5
%   Limb 2+: 0x0000000000000000

% ====================================================
% Subroutines
% ====================================================

% ----------------------------------------------------
% ZeroBuf - zero out a buffer of limbs
% Input: $10 = pointer to buffer
%        $11 = limb count
% Returns: none (POP restores caller frame)
% ----------------------------------------------------
ZeroBuf
        SETI $12,0                % limb index
ZeroLoop CMP     $13,$12,$11
        BNN     $13,ZeroBufReturn
        SLI     $14,$12,3
        STOU    Zero,$10,$14
        ADDUI   $12,$12,1
        JMP     ZeroLoop
ZeroBufReturn
         POP     0,0               % restore frame saved by PUSHJ $15

% ----------------------------------------------------
% Fibonacci - Compute nth Fibonacci number
% Input: Arg0 ($32) = n (which fibonacci number to compute)
%        Arg1 ($33) = pointer to buffer A
%        Arg2 ($34) = pointer to buffer B
% Uses:  $8 = pointer to buffer T (must be set before calling)
% Returns: result in buffer B (POP restores caller frame)
% ----------------------------------------------------
Fibonacci
        % Handle n==0
        CMP     $10,Arg0,Zero
        BZ      $10,FibReturn
        
        % Set B[0] = 1 for n>=1
        SETI $11,1
        STOU    $11,Arg2,Zero
        
        % Handle n==1
        SETI $12,1
        CMP     $10,Arg0,$12
        BZ      $10,FibReturn
        
        % Main loop: compute fib(2) through fib(n)
        SETI $13,2                % i = 2
FibLoop
        CMP     $14,$13,Arg0
        BP      $14,FibReturn        % if i > n, done
        
        % Save Arg0, Arg1, Arg2 before function calls
        SET     $20,Arg0           % save n
        SET     $21,Arg1           % save A
        SET     $22,Arg2           % save B
        
        % T = A + B (multi-precision addition)
        SET     Arg0,$21           % A buffer
        SET     Arg1,$22           % B buffer
        SET     Arg2,$8            % T buffer (result)
        PUSHJ   $31,MPAddWithCarry
        
        % A = B (copy)
        SET     Arg0,$22           % source = B
        SET     Arg1,$21           % dest = A
        SETI    Arg2,MAXLIMBS      % limbs to copy
        PUSHJ   $31,CopyBuf
        
        % B = T (copy)
        SET     Arg0,$8            % source = T
        SET     Arg1,$22           % dest = B
        SETI    Arg2,MAXLIMBS      % limbs to copy
        PUSHJ   $31,CopyBuf
        
        % Restore Arg0, Arg1, Arg2
        SET     Arg0,$20           % restore n
        SET     Arg1,$21           % restore A
        SET     Arg2,$22           % restore B
        
        ADDUI   $13,$13,1
        JMP     FibLoop
FibReturn
         POP     0,0               % restore frame saved by PUSHJ

% ----------------------------------------------------
% CopyBuf - copy limbs from source to destination buffer
% Input: Arg0 ($32) = pointer to source buffer
%        Arg1 ($33) = pointer to destination buffer
%        Arg2 ($34) = limb count
% Returns: none (POP restores caller frame)
% ----------------------------------------------------
CopyBuf
        SETI $10,0                % limb index
CopyLoop CMP     $11,$10,Arg2
        BNN     $11,CopyBufReturn
        SLI     $12,$10,3
        LDOU    $13,Arg0,$12
        STOU    $13,Arg1,$12
        ADDUI   $10,$10,1
        JMP     CopyLoop
CopyBufReturn
         POP     0,0               % restore frame saved by PUSHJ

% ----------------------------------------------------
% MPAddWithCarry - Multi-precision addition with carry
% Input: Arg0 ($32) = pointer to buffer A
%        Arg1 ($33) = pointer to buffer B
%        Arg2 ($34) = pointer to buffer T (result, T = A + B)
% Returns: none (POP restores caller frame)
% ----------------------------------------------------
MPAddWithCarry
        SETI $10,0                % limb index
        SETI $14,0                % carry
        SETI $22,MAXLIMBS
MPALoop
        CMP     $15,$10,$22
        BNN     $15,MPADone
        
        SLI     $21,$10,3            % offset
        LDOU    $16,Arg0,$21         % x = A[i]
        LDOU    $17,Arg1,$21         % y = B[i]
        
        ADDU    $18,$16,$17          % s = x + y
        CMPU    $19,$18,$16          % carry1 = (s < x) ? 1 : 0
        BN      $19,MPAC1Yes
        SETI $19,0
        JMP     MPAC1Done
MPAC1Yes
        SETI $19,1
MPAC1Done
        
        ADDU    $20,$18,$14          % s2 = s + carry_in
        CMPU    $15,$20,$18          % carry2 = (s2 < s) ? 1 : 0
        BN      $15,MPAC2Yes
        SETI $15,0
        JMP     MPAC2Done
MPAC2Yes
        SETI $15,1
MPAC2Done
        
        SLI     $21,$10,3
        STOU    $20,Arg2,$21         % T[i] = s2
        
        OR      $14,$19,$15          % carry = carry1 | carry2
        
        ADDUI   $10,$10,1
        JMP     MPALoop
MPADone
         POP     0,0               % restore frame saved by PUSHJ

% ----------------------------------------------------
% BigIntToDecStr - Convert big integer to decimal string
% Input: $10 = pointer to big integer buffer
%        $11 = pointer to output string buffer
% Returns: none (writes string, terminates with POP)
% Uses TempBuf to avoid modifying input
% ----------------------------------------------------
BigIntToDecStr
        % Copy input to TempBuf (we'll modify it during conversion)
        SETI $12,0                % limb index
        GETA    $13,TempBuf
        SETI $14,MAXLIMBS
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
        SETI $12,0                % digit count
        
ExtractDigits
        % Check if TempBuf is zero
        OR      $13,$13,Zero         % reload TempBuf address
        GETA    $13,TempBuf
        SETI $14,0                % limb index
        SETI $15,MAXLIMBS
CheckZero
        CMP     $16,$14,$15
        BNN     $16,IsZero
        SLI     $17,$14,3
        LDOU    $18,$13,$17
        BNZ     $18,NotZero
        ADDUI   $14,$14,1
        JMP     CheckZero
        
IsZero  % All done extracting digits
        BZ      $12,WasZero          % if no digits, it was zero
        JMP     ReverseDigits
        
WasZero % Store '0'
        SETI $16,48
        STBU    $16,$11,Zero
        SETI $16,1
        STBU    Zero,$11,$16         % null terminator
        JMP     BigIntReturn
        
NotZero % Divide TempBuf by 10, get remainder
        GETA    $13,TempBuf
        PUSHJ   $26,DivBy10          % save caller locals, remainder returned via POP
        OR      $9,$26,Zero          % move returned remainder into $9 for digit emit
        ADDUI   $9,$9,48             % convert to ASCII
        GETA    $14,DigitBuf
        STBU    $9,$14,$12           % store digit
        ADDUI   $12,$12,1            % increment digit count
        JMP     ExtractDigits
        
ReverseDigits
        % Reverse digits from DigitBuf into OutputStr
        SETI $13,0                % output position
RevLoop CMP     $14,$13,$12
        BNN     $14,RevDone
        SUBUI   $15,$12,1
        SUBU    $15,$15,$13          % source index = count-1-i
        GETA    $16,DigitBuf
        LDBU    $17,$16,$15
        STBU    $17,$11,$13
        ADDUI   $13,$13,1
        JMP     RevLoop
RevDone STBU    Zero,$11,$13         % null terminator
BigIntReturn
        POP     0,0                  % restore frame saved by PUSHJ $30

% ----------------------------------------------------
% DivBy10 - Divide big integer by 10 in place
% Input: $13 = pointer to big integer buffer
% Output: remainder returned via POP (caller sees it in $26)
% Destroys: $14-$19, $22-$25
% ----------------------------------------------------
DivBy10
        SETI $9,0                 % remainder accumulator
        SETI $14,MAXLIMBS
        SUBUI   $14,$14,1            % start from MSL
        
DivLoop BN      $14,DivDone
        SLI     $15,$14,3
        LDOU    $16,$13,$15          % load limb
        
        % Divide: (remainder << 64) | limb / 10
        % We do this digit by digit in the limb
        SETI $17,0                % quotient for this limb
        SETI $18,64               % bits remaining
        
BitLoop BZ      $18,LimbDone
        % Shift remainder and bring in next bit from limb
        SLI     $9,$9,1              % remainder *= 2
        SETI $22,63
        SRU     $23,$16,$22          % get top bit of limb
        OR      $9,$9,$23            % add to remainder
        SLI     $16,$16,1            % shift limb left
        
        SLI     $17,$17,1            % shift quotient left
        
        % If remainder >= 10, subtract 10 and set quotient bit
        SETI $24,10
        CMP     $25,$9,$24
        BN      $25,SkipSub
        SUBU    $9,$9,$24
        ORI     $17,$17,1            % set low bit of quotient
SkipSub
        SUBUI   $18,$18,1
        JMP     BitLoop
        
LimbDone
        % Store quotient limb
        STOU    $17,$13,$15
        SUBUI   $14,$14,1
        JMP     DivLoop
        
DivDone OR      $0,$9,Zero          % return remainder via $0
        POP     1,0                 % restore frame and return remainder
