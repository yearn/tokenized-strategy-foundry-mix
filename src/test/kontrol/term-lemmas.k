requires "evm.md"
requires "foundry.md"

module TERM-LEMMAS
    imports EVM
    imports FOUNDRY
    imports INT-SYMBOLIC
    imports MAP-SYMBOLIC
    imports SET-SYMBOLIC

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

    claim [keccak-comparison]: <k> runLemma ( ( keccak ( #buf ( 32 , WORD:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 3 ) ==Int ( keccak ( #buf ( 32 , WORD1:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00!" ) +Int 2 ) ) => doneLemma ( false ) ... </k>

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

endmodule