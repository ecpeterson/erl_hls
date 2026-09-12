// Selected expression failures. Values on a failed path are placeholders;
// consumers must check the code before committing state or publishing effects.
pub enum Kind : u4 {
    NONE = 0,
    FUNCTION_CLAUSE = 1,
    MATCH_FAILURE = 2,
    REQUEST_LENGTH = 3,
    CASE_CLAUSE = 4,
    IF_CLAUSE = 5,
    EXPLICIT_FAIL = 6,
    INVALID_MESSAGE = 7,
    INVALID_REPEAT = 8,
    REDUCTION_MISMATCH = 9,
    REDUCTION_PROTOCOL = 10,
    INVALID_EFFECT = 11,
    INTERNAL = 12,
}

// Zero is success. Codes 1..15 are generic reasons; source-located codes are
// allocated by the actor compiler and decoded with that artifact's source map.
// Bits 3:0 retain the reason so GS error replies need no source lookup circuit.
pub type Code = u16;
pub const NONE = Code:0;
pub const FUNCTION_CLAUSE = Code:1;
pub const MATCH_FAILURE = Code:2;
pub const REQUEST_LENGTH = Code:3;
pub const CASE_CLAUSE = Code:4;
pub const IF_CLAUSE = Code:5;
pub const EXPLICIT_FAIL = Code:6;
pub const INVALID_MESSAGE = Code:7;
pub const INVALID_REPEAT = Code:8;
pub const REDUCTION_MISMATCH = Code:9;
pub const REDUCTION_PROTOCOL = Code:10;
pub const INVALID_EFFECT = Code:11;
pub const INTERNAL = Code:12;

pub fn first(earlier: Code, later: Code) -> Code {
    if earlier != NONE { earlier } else { later }
}

pub fn check(failed: bool, code: Code) -> Code {
    if failed { code } else { NONE }
}

pub fn failed(code: Code) -> bool { code != NONE }

// Transport and scheduler failures precede callback evaluation. A selected
// callback retains its original code rather than becoming a generic FAIL.
pub fn dispatch(invalid_message: bool, invalid_repeat: bool,
    incomplete_reduction: bool, effective: bool, callback: Code) -> Code {
    if invalid_message { INVALID_MESSAGE }
    else if invalid_repeat { INVALID_REPEAT }
    else if incomplete_reduction { REDUCTION_PROTOCOL }
    else { check(effective, callback) }
}

pub fn completion(dispatched: bool, invalid_repeat: bool, callback: Code) -> Code {
    if !dispatched { REDUCTION_PROTOCOL }
    else if invalid_repeat { INVALID_REPEAT }
    else { callback }
}

pub fn kind(code: Code) -> Kind { (code as u4) as Kind }
