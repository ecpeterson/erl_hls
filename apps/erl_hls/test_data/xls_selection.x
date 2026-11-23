// Minimal encode-then-index comparison, independent of application or scheduler.
// Bit zero names the first value; idle selection returns value zero's payload.
fn grant<COUNT:u32>(pending:bool[COUNT],cursor:u32)->uN[COUNT] {
  let requests=rev(pending as uN[COUNT]);
  let after=requests & (!uN[COUNT]:0 << cursor);
  one_hot(if or_reduce(after) { after } else { requests },true) as uN[COUNT]
}

// The all-zero grant encodes index zero.
fn index<COUNT:u32>(selected:uN[COUNT])->u32 {
  let indices=unroll_for!(i,values):(u32,u32[COUNT]) in u32:0..COUNT {
    update(values,i,i)
  }(zero!<u32[COUNT]>());
  one_hot_sel(selected,indices)
}

// Round-trip through an index; keep that index observable in both alternatives.
fn indexed<COUNT:u32>(pending:bool[COUNT],cursor:u32,values:u32[COUNT])->(bool,u32,u32) {
  let selected=grant(pending,cursor);
  let producer=index(selected);
  (or_reduce(selected),producer,values[producer])
}

// Preserve the empty-grant payload while keeping the data selection one-hot.
fn direct<COUNT:u32>(pending:bool[COUNT],cursor:u32,values:u32[COUNT])->(bool,u32,u32) {
  let selected=grant(pending,cursor);
  (or_reduce(selected),index(selected),one_hot_sel(selected | (!or_reduce(selected) as uN[COUNT]),values))
}

// Instantiate the 19-producer indexed comparison.
pub fn indexed19(pending:bool[19],cursor:u32,values:u32[19])->(bool,u32,u32) {
  indexed(pending,cursor,values)
}

// Instantiate the 19-producer direct comparison.
pub fn direct19(pending:bool[19],cursor:u32,values:u32[19])->(bool,u32,u32) {
  direct(pending,cursor,values)
}

// Instantiate the 22-producer indexed comparison.
pub fn indexed22(pending:bool[22],cursor:u32,values:u32[22])->(bool,u32,u32) {
  indexed(pending,cursor,values)
}

// Instantiate the 22-producer direct comparison.
pub fn direct22(pending:bool[22],cursor:u32,values:u32[22])->(bool,u32,u32) {
  direct(pending,cursor,values)
}

// Keep availability independent of priority encoding, including the idle fallback.
fn early<COUNT:u32>(pending:bool[COUNT],cursor:u32,values:u32[COUNT])->(bool,u32,u32) {
  let selected=grant(pending,cursor);
  let valid=or_reduce(pending as uN[COUNT]);
  (valid,index(selected),one_hot_sel(selected | (!valid as uN[COUNT]),values))
}

// Instantiate the 19-producer early-valid comparison.
pub fn early19(pending:bool[19],cursor:u32,values:u32[19])->(bool,u32,u32) {
  early(pending,cursor,values)
}

// Instantiate the 22-producer early-valid comparison.
pub fn early22(pending:bool[22],cursor:u32,values:u32[22])->(bool,u32,u32) {
  early(pending,cursor,values)
}
