// Generated source helpers; failure codes belong to the enclosing actor bundle.
import hls_failure;
import hls_integer;

pub fn select_grid(argument_1: u32, argument_2: u32) -> (u32, hls_failure::Code) {  // @erl "phi_direction.erl":37
  let v_Mask_1 = argument_1;                                                    // @erl "phi_direction.erl":37
  let v_Random_1 = argument_2;                                                  // @erl "phi_direction.erl":37
  let _0 = v_Mask_1 & 1;                                                        // @erl "phi_direction.erl":38
  let v_North_1 = _0;                                                           // @erl "phi_direction.erl":38
  let _1 = hls_integer::shift<false>(v_Mask_1, u1:1);                           // @erl "phi_direction.erl":39
  let _2 = _1 & 1;                                                              // @erl "phi_direction.erl":39
  let v_East_1 = _2;                                                            // @erl "phi_direction.erl":39
  let _3 = hls_integer::shift<false>(v_Mask_1, u2:2);                           // @erl "phi_direction.erl":40
  let _4 = _3 & 1;                                                              // @erl "phi_direction.erl":40
  let v_West_1 = _4;                                                            // @erl "phi_direction.erl":40
  let _5 = hls_integer::shift<false>(v_Mask_1, u2:3);                           // @erl "phi_direction.erl":41
  let _6 = _5 & 1;                                                              // @erl "phi_direction.erl":41
  let v_South_1 = _6;                                                           // @erl "phi_direction.erl":41
  let _7 = ((v_North_1) + (v_East_1));                                          // @erl "phi_direction.erl":42
  let _8 = ((_7) + (v_West_1));                                                 // @erl "phi_direction.erl":42
  let _9 = ((_8) + (v_South_1));                                                // @erl "phi_direction.erl":42
  let v_Count_1 = _9;                                                           // @erl "phi_direction.erl":42
  let _10 = v_Random_1 & 2147483647;                                            // @erl "phi_direction.erl":43
  let _11 = (_10 as u64);                                                       // @erl "phi_direction.erl":43
  let v_Draw_1 = _11;                                                           // @erl "phi_direction.erl":43
  let _12 = (v_Count_1 as u64);                                                 // @erl "phi_direction.erl":46
  let _13 = v_Draw_1 * _12;                                                     // @erl "phi_direction.erl":46
  let _14 = hls_integer::shift<false>(_13, u5:31);                              // @erl "phi_direction.erl":46
  let _15 = (_14 as u32);                                                       // @erl "phi_direction.erl":44
  let v_Rank_1 = _15;                                                           // @erl "phi_direction.erl":44
  let _19 = {                                                                   // @erl "phi_direction.erl":48
    let _16 = hls_integer::equal(v_Count_1, sN[2]:0);                           // @erl "phi_direction.erl":49
    if _16 {                                                                    // @erl "phi_direction.erl":48
      (u32:0, hls_failure::NONE)                                                // @erl "phi_direction.erl":48
    } else {                                                                    // @erl "phi_direction.erl":48
      let _16 = hls_integer::less(v_Rank_1, v_North_1);                         // @erl "phi_direction.erl":50
      if _16 {                                                                  // @erl "phi_direction.erl":48
        (u32:1, hls_failure::NONE)                                              // @erl "phi_direction.erl":48
      } else {                                                                  // @erl "phi_direction.erl":48
        let _16 = ((v_North_1) + (v_East_1));                                   // @erl "phi_direction.erl":51
        let _17 = hls_integer::less(v_Rank_1, _16);                             // @erl "phi_direction.erl":51
        if _17 {                                                                // @erl "phi_direction.erl":48
          (u32:2, hls_failure::NONE)                                            // @erl "phi_direction.erl":48
        } else {                                                                // @erl "phi_direction.erl":48
          let _16 = ((v_North_1) + (v_East_1));                                 // @erl "phi_direction.erl":52
          let _17 = ((_16) + (v_West_1));                                       // @erl "phi_direction.erl":52
          let _18 = hls_integer::less(v_Rank_1, _17);                           // @erl "phi_direction.erl":52
          if _18 {                                                              // @erl "phi_direction.erl":48
            (u32:4, hls_failure::NONE)                                          // @erl "phi_direction.erl":48
          } else {                                                              // @erl "phi_direction.erl":48
            {                                                                   // @erl "phi_direction.erl":48
              (u32:8, hls_failure::NONE)                                        // @erl "phi_direction.erl":48
            }                                                                   // @erl "phi_direction.erl":48
          }                                                                     // @erl "phi_direction.erl":48
        }                                                                       // @erl "phi_direction.erl":48
      }                                                                         // @erl "phi_direction.erl":48
    }                                                                           // @erl "phi_direction.erl":48
  };                                                                            // @erl "phi_direction.erl":48
  (_19.0, _19.1)                                                                // @erl "phi_direction.erl":37
}                                                                               // @erl "phi_direction.erl":37
