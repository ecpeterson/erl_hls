// Generated source helpers; failure codes belong to the enclosing actor bundle.
import hls_failure;
import hls_integer;

pub fn select_grid(argument_1: u32, argument_2: u32) -> (u32, hls_failure::Code) {  // L37
  let v_Mask_1 = argument_1;
  let v_Random_1 = argument_2;
  let _0 = v_Mask_1 & 1;
  let v_North_1 = _0;
  let _1 = hls_integer::shift<false>(v_Mask_1, u1:1);
  let _2 = _1 & 1;
  let v_East_1 = _2;
  let _3 = hls_integer::shift<false>(v_Mask_1, u2:2);
  let _4 = _3 & 1;
  let v_West_1 = _4;
  let _5 = hls_integer::shift<false>(v_Mask_1, u2:3);
  let _6 = _5 & 1;
  let v_South_1 = _6;
  let _7 = ((v_North_1) + (v_East_1));
  let _8 = ((_7) + (v_West_1));
  let _9 = ((_8) + (v_South_1));
  let v_Count_1 = _9;
  let _10 = v_Random_1 & 2147483647;
  let _11 = (_10 as u64);
  let v_Draw_1 = _11;
  let _12 = (v_Count_1 as u64);
  let _13 = v_Draw_1 * _12;
  let _14 = hls_integer::shift<false>(_13, u5:31);
  let _15 = (_14 as u32);
  let v_Rank_1 = _15;
  let _19 = {
    let _16 = hls_integer::equal(v_Count_1, sN[2]:0);
    if _16 {
      (u32:0, hls_failure::NONE)
    } else {
      let _16 = hls_integer::less(v_Rank_1, v_North_1);
      if _16 {
        (u32:1, hls_failure::NONE)
      } else {
        let _16 = ((v_North_1) + (v_East_1));
        let _17 = hls_integer::less(v_Rank_1, _16);
        if _17 {
          (u32:2, hls_failure::NONE)
        } else {
          let _16 = ((v_North_1) + (v_East_1));
          let _17 = ((_16) + (v_West_1));
          let _18 = hls_integer::less(v_Rank_1, _17);
          if _18 {
            (u32:4, hls_failure::NONE)
          } else {
            {
              (u32:8, hls_failure::NONE)
            }
          }
        }
      }
    }
  };
  (_19.0, _19.1)
}
