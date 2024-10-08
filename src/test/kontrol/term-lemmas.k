requires "evm.md"
requires "foundry.md"
// requires "keccak.md"

module TERM-LEMMAS
    imports EVM
    imports FOUNDRY
    imports INT-SYMBOLIC
    imports MAP-SYMBOLIC
    imports SET-SYMBOLIC
    // imports KECCAK-LEMMAS

    syntax StepSort ::= Int
                      | Bool
                      | Bytes
                      | Map
                      | Set
 // -------------------------

    syntax KItem ::= runLemma ( StepSort )
                   | doneLemma( StepSort )
 // --------------------------------------
    rule <k> runLemma(T) => doneLemma(T) ... </k>

    // Instantiation of the Kontrol lemma
    // rule ( X ==Int ( X *Int Y ) /Word Y ) orBool Y ==Int 0 => true [simplification, preserves-definedness]
    // when Y is of the form Y *Int Z, because then the `Y ==Int 0` condition gets simplified to a different form
    rule ( X ==Int ( X *Int (Y *Int Z) ) /Word (Y *Int Z) ) orBool (Y ==Int 0 orBool Z ==Int 0) => true [simplification, preserves-definedness]

    // Instantiation of the Kontrol lemma
    // rule ( X ==Int ( X *Int Y ) /Word Y ) orBool Y ==Int 0 => true [simplification, preserves-definedness]
    // when Y is of the form Y *Int ( Z *Int T ), because then the `Y ==Int 0` condition gets simplified to a different form
    rule ( X ==Int ( X *Int (Y *Int (Z *Int T)) ) /Word (Y *Int (Z *Int T)) ) orBool (Y ==Int 0 orBool (Z ==Int 0 orBool T ==Int 0)) => true [simplification, preserves-definedness]

    // Instantiation of the Kontrol lemma
    // rule ( X ==Int ( X *Int Y ) /Word Y ) orBool Y ==Int 0 => true [simplification, preserves-definedness]
    // when Y is of the form Y /Int Z, because then the `Y ==Int 0` condition gets simplified to a different form
    rule ( X ==Int ( X *Int (Y /Int Z) ) /Word (Y /Int Z) ) orBool Y <Int Z => true
      requires notBool ( Z ==Int 0 )
      [simplification, preserves-definedness]

    rule [chop-sub]:
      chop ( Y -Int X:Int ) ==Int 0 => X ==Int Y
      requires #rangeUInt(256, X) andBool #rangeUInt(256, Y)
      [simplification, concrete(Y), comm]

    rule [keccak-slots-disjoint]:
      keccak ( A ) ==Int keccak ( B ) +Int C => false
      requires notBool 0 ==Int C
      [simplification, concrete(C), comm]

    rule [keccak-slots-disjoint-ml-l]:
      { keccak ( A ) #Equals keccak ( B ) +Int C } => #Bottom
      requires notBool 0 ==Int C
      [simplification, concrete(C)]

    rule [keccak-slots-disjoint-ml-r]:
      { keccak ( B ) +Int C #Equals keccak ( A ) } => #Bottom
      requires notBool 0 ==Int C
      [simplification, concrete(C)]

    // 2a. |Int and +Bytes, update to be done in left
    rule [bor-update-to-left-2]:
      #asWord ( B1 +Bytes B2 ) |Int A =>
        #asWord ( #buf ( 32 -Int lengthBytes(B2), (A /Int (2 ^Int (8 *Int lengthBytes(B2)))) |Int #asWord ( B1 ) ) +Bytes B2 )
        requires #rangeUInt(256, A) andBool A modInt (2 ^Int (8 *Int lengthBytes(B2))) ==Int 0 andBool lengthBytes(B1 +Bytes B2) <=Int 32
        [simplification, preserves-definedness]

    // 2b. |Int of +Bytes, update to be done in right
    rule [bor-update-to-right-2]:
      #asWord ( B1 +Bytes B2 ) |Int A =>
        #asWord ( B1 +Bytes #buf ( lengthBytes(B2), A |Int #asWord ( B2 ) ) )
        requires 0 <=Int A andBool A <Int 2 ^Int (8 *Int lengthBytes(B2)) andBool lengthBytes(B2) <=Int 32
        [simplification, preserves-definedness]

    rule ( SetItem(X:Int) S:Set ) |Set SetItem(Y:Int) => SetItem(X) ( S |Set SetItem (Y) ) requires notBool X ==Int Y [simplification, preserves-definedness]
    rule ( SetItem(X:Int) S:Set ) |Set SetItem(Y:Int) => SetItem(X) S                      requires         X ==Int Y [simplification, preserves-definedness]
    rule                     .Set |Set SetItem(X:Int) => SetItem(X)                                                   [simplification, preserves-definedness]

    rule K1 in_keys((K2 |-> _ ) M) => K1 ==Int K2 orBool K1 in_keys(M) [simplification]

    rule [transferFunds-hp-neq]:
      <k> #transferFunds ACCTFROM ACCTTO VALUE => .K ... </k>
      <account>
        <acctID> ACCTFROM </acctID>
        <balance> ORIGFROM => ORIGFROM -Word VALUE </balance>
        ...
      </account>
      <account>
        <acctID> ACCTTO </acctID>
        <balance> ORIGTO => ORIGTO +Word VALUE </balance>
        ...
      </account>
      requires ACCTFROM =/=K ACCTTO andBool VALUE <=Int ORIGFROM
      [priority(30), preserves-definedness]

    rule [accounts-in-keys]:
      `AccountCellMap:in_keys`(
        <acctID> (X:Int) </acctID>,
        (`_AccountCellMap_`(AccountCellMapItem(<acctID> Y:Int </acctID>, _:AccountCell):AccountCellMap, ACCOUNTS_REST:AccountCellMap)):AccountCellMap
      ) => X ==Int Y orBool `AccountCellMap:in_keys`(<acctID> (X:Int) </acctID>, ACCOUNTS_REST)
      [simplification, preserves-definedness]

endmodule

module TERM-LEMMAS-SPEC
    imports TERM-LEMMAS

    claim [storage-offset]: <k> runLemma ( ( #lookup ( STORAGE3:Map , 2 ) /Int pow160 ) ) => doneLemma ( #asWord ( #range ( #buf ( 32 , #lookup ( STORAGE3:Map , 2 ) ) , 0 , 12 ) ) ) ... </k>

    claim [chop-simplify]: <k> runLemma (
                                 notBool chop ( WORD7:Int +Int ( WORD12:Int *Int ( ( WORD5:Int -Int WORD6:Int ) /Int WORD11:Int ) ) ) ==Int
                                 chop ( chop ( WORD7:Int +Int ( WORD12:Int *Int ( ( WORD5:Int -Int WORD6:Int ) /Int WORD11:Int ) ) ) *Int 1000000000000000000 ) /Int 1000000000000000000
                               ) => runLemma ( false ) ... </k>
      requires 0 <=Int WORD5:Int
       andBool 0 <=Int WORD6:Int
       andBool 0 <=Int WORD7:Int
       andBool 0 <=Int WORD11:Int
       andBool 0 <=Int WORD12:Int
       andBool WORD11:Int =/=Int 0
       andBool WORD12:Int =/=Int 0
       andBool WORD6:Int <=Int WORD5:Int
       andBool WORD5:Int <Int pow96
       andBool WORD6:Int <Int pow96
       andBool WORD7:Int <Int pow96
       andBool WORD11:Int <Int pow96
       andBool WORD12:Int <Int pow96

    claim [storage-simplification]:
      <k> runLemma (
            STORAGE0:Map
            [ 5 <- #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , WORD4:Int ) +Bytes #buf ( 5 , WORD3:Int ) +Bytes b"\x00" ) ]
            [ 6 <- #asWord ( #buf ( 1 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ]
            [ 5 <- #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , WORD4:Int ) +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes b"\x01" ) ]
            [ 6 <- ( ( TIMESTAMP_CELL:Int *Int pow40 ) |Int ( 115792089237316195423570985008687907853269984665640562830531764394383466561535 &Int #asWord ( #buf ( 1 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ) ) ]
            [ 5 <- #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes b"\x01" ) ]
          ) => doneLemma (
            STORAGE0:Map
            [ 6 <- #asWord ( #buf ( 1 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ]
            [ 5 <- #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes b"\x01" ) ]
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int pow40

    claim [slot-update-01]:
      <k> runLemma(
        ( maxUInt8 &Int ( ( TIMESTAMP_CELL:Int *Int pow48 ) |Int ( 115792089237316195423570985008687907853269984665640254554447762944319381569535 &Int ( ( TIMESTAMP_CELL:Int *Int 256 ) |Int ( 115792089237316195423570985008687907853269984665640564039457583726438152929535 &Int ( 1 |Int #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , _WORD4:Int ) +Bytes #buf ( 5 , _WORD3:Int ) +Bytes b"\x00" ) ) ) ) ) ) )
      ) => doneLemma(
        1
      ) ... </k>
      requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 40

    claim [slot-update-02]:
      <k> runLemma (
            ( ( maxUInt40 &Int ( ( 115341543235797707419527244145998463631733976271937281205136574426583511597055 &Int #asWord ( #buf ( 2 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ) /Int pow40 ) ) )
          ) => doneLemma (
            TIMESTAMP_CELL
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 35

    claim [slot-update-03]:
      <k> runLemma (
            ( maxUInt40 &Int ( ( TIMESTAMP_CELL:Int |Int ( 115792089237316195423570985008687907853269984665640564039457584006813618012160 &Int #asWord ( #buf ( 1 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ) ) /Int pow40 ) ) <=Int TIMESTAMP_CELL:Int
          ) => doneLemma (
            true
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 35

    claim [slot-update-04]:
      <k> runLemma (
            #asWord ( #range ( #buf ( 10 , ( ( ( TIMESTAMP_CELL:Int *Int pow48 ) /Int 256 ) |Int TIMESTAMP_CELL:Int ) ) , 5 , 5 ) ) <=Int TIMESTAMP_CELL:Int
          ) => doneLemma (
            true
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 35

    claim [slot-update-05]:
      <k> runLemma (
            #asWord ( #range ( #buf ( 6 , TIMESTAMP_CELL:Int *Int 256 ) , 5 , 1 ) )
          ) => doneLemma (
            false
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 35

    claim [slot-update-06]:
      <k> runLemma (
            #asWord ( #range ( #buf ( 26 , 960911443338137442927181681227604902095826437272264907948032 |Int WORD4:Int ) , 21 , 5 ) ) <=Int TIMESTAMP_CELL:Int
          ) => doneLemma (
            WORD4 <=Int TIMESTAMP_CELL
          ) ... </k>
          requires 0 <=Int WORD4 andBool WORD4 <Int 2 ^Int 40

    claim [slot-update-07]:
      <k> runLemma (
            #asWord ( #range ( #buf ( 25 , ( ( ( WORD7:Int +Int 1 ) *Int pow200 ) |Int #asWord ( #buf ( 25 , ( 438052756531465687819472504520361015472122898704787692322816 |Int WORD6:Int ) ) ) ) ) , 20 , 5 ) ) <=Int TIMESTAMP_CELL:Int
          ) => doneLemma (
            WORD6 <=Int TIMESTAMP_CELL
          ) ... </k>
          requires 0 <=Int WORD6 andBool WORD6 <Int 2 ^Int 40
           andBool 0 <=Int WORD7 andBool WORD7 <Int 256

    claim [slot-update-08]:
      <k> runLemma (
            #asWord ( #buf ( 20 , 770621190285571058874329108704665103402425909248 |Int ( ( WORD7:Int +Int 1 ) *Int pow160 ) ) )
          ) => doneLemma (
            770621190285571058874329108704665103402425909248
          ) ... </k>
          requires 0 <=Int WORD7 andBool WORD7 <Int 256

    claim [slot-update-09]:
      <k> runLemma (
            ( 481644099385675654177479669474857658256926169505224677670350078624137216 |Int ( 115790322390251417039241401711187164934754157181743689629425282016341011726335 &Int #asWord ( #buf ( 2 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ) )
          ) => doneLemma (
            #asWord ( #buf ( 2 , WORD7:Int ) +Bytes b"E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) )
          ) ... </k>
          requires 0 <=Int WORD5 andBool WORD5 <Int 2 ^Int 35
           andBool 0 <=Int WORD6 andBool WORD6 <Int 2 ^Int 35
           andBool 0 <=Int WORD7 andBool WORD7 <Int 256

    claim [length-bytestack]: <k> runLemma ( lengthBytes ( #padToWidth ( 32 , #asByteStack ( ( ( ( ( ( WORD0:Int *Int VV0_amount_114b9705:Int ) /Int WORD:Int ) +Int WORD8:Int ) |Int #asWord ( #buf ( 16 , WORD9:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ) ) /Int pow128 ) ) ) ) ) => doneLemma ( 32 ) ... </k>

    claim [add-not-eq-zero]: <k> runLemma ( 0 ==Int ( ( ( ( ( VV0_purchaseTokenPrecision_114b9705:Int *Int ( WORD0:Int -Int TIMESTAMP_CELL:Int ) ) /Int 31104000 ) *Int WORD:Int ) /Int 1000000000000000000 ) +Int VV0_purchaseTokenPrecision_114b9705:Int ) ) => doneLemma ( false ) ... </k>
        requires 0 <Int VV0_purchaseTokenPrecision_114b9705
         andBool 0 <=Int WORD
         andBool 0 <=Int TIMESTAMP_CELL
         andBool TIMESTAMP_CELL <=Int WORD0

    claim [chop-comparison]: <k> runLemma ( 0 ==Int chop ( ( 491460923342184218035706888008750043977755113263 -Int VV0_repoToken_114b9705 ) ) ) => doneLemma ( 491460923342184218035706888008750043977755113263 ==Int VV0_repoToken_114b9705 ) ... </k>
        requires 0 <=Int VV0_repoToken_114b9705:Int
         andBool VV0_repoToken_114b9705:Int <Int pow160

    claim [keccak-lookup]: <k> runLemma ( #lookup ( STORAGE:Map [ maxUInt5 <- WORD:Int ] [ keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) <- 491460923342184218035706888008750043977755113263 ] [ ( keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 1 ) <- WORD0:Int ] [ ( keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 2 ) <- 263400868551549723330807389252719309078400616203 ] [ ( keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 3 ) <- 1405310203571408291950365054053061012934685786634 ] , keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00 " ) ) ) => doneLemma ( #lookup ( STORAGE:Map , keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00 " ) ) ) ... </k>

    claim [keccak-lookup-2]: <k> runLemma ( #asWord ( #range ( #buf ( 32 , #lookup ( STORAGE:Map [ maxUInt5 <- WORD:Int ] [ keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) <- 491460923342184218035706888008750043977755113263 ] [ ( keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 1 ) <- WORD0:Int ] [ ( keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 2 ) <- 263400868551549723330807389252719309078400616203 ] [ ( keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 3 ) <- 1405310203571408291950365054053061012934685786634 ] [ keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00 " ) <- WORD1:Int ] [ keccak ( #buf ( 32 , WORD1:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) <- 511347974759188522659820409854212399244223280809 ] [ ( keccak ( #buf ( 32 , WORD1:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 1 ) <- WORD2:Int ] [ ( keccak ( #buf ( 32 , WORD1:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 2 ) <- 1136628940260574992893479910319181283093952727985 ] , ( keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 3 ) ) ) , 12 , 20 ) ) ) => doneLemma ( 1405310203571408291950365054053061012934685786634 ) ... </k>

    claim [keccak-comparison-1]: <k> runLemma ( ( keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 2 ) ==Int ( keccak ( #buf ( 32 , WORD1:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 3 ) ) => doneLemma ( false ) ... </k>

    claim [keccak-comparison-2]: <k> runLemma ( ( keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 3 ) ==Int ( keccak ( #buf ( 32 , WORD1:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 2 ) ) => doneLemma ( false ) ... </k>

    claim [chop-check]: <k> runLemma ( chop ( ( VV2_purchaseTokenPrecision_114b9705:Int *Int WORD8:Int *Int WORD10:Int /Int 1000000000000000000000000000000000000 ) *Int ( WORD11:Int -Int TIMESTAMP_CELL:Int ) +Int ( VV2_purchaseTokenPrecision_114b9705:Int *Int WORD1:Int *Int WORD3:Int /Int 1000000000000000000000000000000000000 ) *Int ( WORD4:Int -Int TIMESTAMP_CELL:Int ) ) ) => doneLemma ( true ) ... </k>
    requires 0 <=Int VV2_purchaseTokenPrecision_114b9705 andBool VV2_purchaseTokenPrecision_114b9705 <Int 18
     andBool 0 <=Int WORD1 andBool WORD1 <Int 2 ^Int 95
     andBool 0 <=Int WORD3 andBool WORD3 <Int 2 ^Int 95
     andBool 0 <=Int WORD4 andBool WORD4 <Int 34359738368
     andBool 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int WORD4
     andBool 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int WORD11
     andBool 0 <=Int WORD8 andBool WORD8 <Int 2 ^Int 95
     andBool 0 <=Int WORD10 andBool WORD10 <Int 2 ^Int 95
     andBool 0 <=Int WORD11 andBool WORD11 <Int 34359738368

    claim [keccak-comparison-3]: <k> runLemma ( #lookup ( STORAGE:Map [ 34 <- #asWord ( #range ( #buf ( 32 , #lookup ( STORAGE:Map , 34 ) ) , 0 , 12 ) +Bytes b"V\x15\xde\xb7\x98\xbb>M\xfa\x019\xdf\xa1\xb3\xd43\xcc#\xb7/" ) ] [ maxUInt5 <- VV0_offerId_114b9705:Int ] [ keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00 " ) <- 0 ] [ keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) <- #asWord ( #range ( #buf ( 32 , #lookup ( STORAGE:Map , keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) ) ) , 0 , 12 ) +Bytes b".#M\xaeu\xc7\x93\xf6z5\x08\x9c\x9d\x99$^\x1cXG\x0b" ) ] [ ( keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 1 ) <- #lookup ( STORAGE3:Map , ( keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x1b" ) +Int 4 ) ) ] [ ( keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 2 ) <- #asWord ( #range ( #buf ( 32 , #lookup ( STORAGE:Map [ 34 <- #asWord ( #range ( #buf ( 32 , #lookup ( STORAGE:Map , 34 ) ) , 0 , 12 ) +Bytes b"V\x15\xde\xb7\x98\xbb>M\xfa\x019\xdf\xa1\xb3\xd43\xcc#\xb7/" ) ] [ maxUInt5 <- VV0_offerId_114b9705:Int ] [ keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00 " ) <- 0 ] , ( keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 2 ) ) ) , 0 , 12 ) +Bytes #buf ( 20 , WORD:Int ) ) ] [ ( keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 3 ) <- #asWord ( #range ( #buf ( 32 , #lookup ( STORAGE:Map [ 34 <- #asWord ( #range ( #buf ( 32 , #lookup ( STORAGE:Map , 34 ) ) , 0 , 12 ) +Bytes b"V\x15\xde\xb7\x98\xbb>M\xfa\x019\xdf\xa1\xb3\xd43\xcc#\xb7/" ) ] [ maxUInt5 <- VV0_offerId_114b9705:Int ] [ keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00 " ) <- 0 ] , ( keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 3 ) ) ) , 0 , 12 ) +Bytes b"\xf6(I\xf9\xa0\xb5\xbf)\x13\xb3\x96\t\x8f|p\x19\xb5\x1a\x82\n" ) ] , keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00 " ) ) )
                                  => doneLemma ( 0 ) ... </k>

    claim [slot-update-10]: <k> runLemma ( #asWord ( #range ( #buf ( 32 , ( #asWord ( #range ( #buf ( 32 , #lookup ( STORAGE:Map , ( keccak ( #buf ( 32 , VV0_offerId_114b9705:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 2 ) ) ) , 0 , 12 ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ) |Int WORD:Int ) ) , 12 , 20 ) )  )
                                => doneLemma ( WORD:Int ) ... </k>
                                requires #rangeUInt(160, WORD)

endmodule