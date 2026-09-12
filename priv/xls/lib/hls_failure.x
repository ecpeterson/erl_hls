// Selected expression failures. Values on a failed path are placeholders;
// consumers must check the kind before committing state or publishing effects.
pub enum Kind : u3 {
    NONE = 0,
    FUNCTION_CLAUSE = 1,
    MATCH_FAILURE = 2,
    REQUEST_LENGTH = 3,
    CASE_CLAUSE = 4,
    IF_CLAUSE = 5,
}

pub fn first(earlier: Kind, later: Kind) -> Kind {
    if earlier != Kind::NONE { earlier } else { later }
}

pub fn check(failed: bool, kind: Kind) -> Kind {
    if failed { kind } else { Kind::NONE }
}
