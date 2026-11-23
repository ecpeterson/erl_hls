import domain_fault;

// No indication selects neither a spurious actor nor a fault code.
#[test]
fn no_fault() {
  assert_eq(domain_fault::first(domain_fault::Fault[0]:[]), zero!<domain_fault::Fault>());
  assert_eq(domain_fault::first([domain_fault::Fault {actor: u32:37, code: u16:0}]),
    zero!<domain_fault::Fault>());
}

// Priority follows network order, not actor number, fault magnitude or a nonzero actor tag.
#[test]
fn simultaneous_faults() {
  let earlier = domain_fault::Fault {actor: u32:17, code: u16:3};
  let later = domain_fault::Fault {actor: u32:4, code: u16:99};
  assert_eq(domain_fault::first([earlier, later]), earlier);
  let actor_zero = domain_fault::Fault {actor: u32:0, code: u16:2};
  assert_eq(domain_fault::first([actor_zero, earlier]), actor_zero);
}

// Exercise all 48 positions and a later competing fault without deeply nested source.
#[test]
fn bank_positions() {
  for (i, _): (u32, ()) in u32:0..u32:48 {
    let selected = domain_fault::Fault {actor: i * u32:2, code: (i + u32:1) as u16};
    let faults = update(zero!<domain_fault::Fault[48]>(), i, selected);
    assert_eq(domain_fault::first(faults), selected);
    let competing = update(faults, u32:47, domain_fault::Fault {actor: u32:99, code: u16:65535});
    if i < u32:47 { assert_eq(domain_fault::first(competing), selected) } else { () }
  }(())
}
