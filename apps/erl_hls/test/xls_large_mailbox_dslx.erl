-module(xls_large_mailbox_dslx).
-moduledoc false.
-export([write/1]).

-doc "Writes ordinary 64/255-slot actors with selection and compaction witnesses.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    {ok, Source} = file:read_file("test/hls_large_mailbox_fixture.erl"),
    lists:foreach(fun(Capacity) ->
        Stem = filename:join(Stage, "large_mailbox_" ++ integer_to_list(Capacity)),
        Path = Stem ++ ".erl",
        Replaced = binary:replace(Source, <<"-hls_mailbox_capacity(64).">>,
            iolist_to_binary(io_lib:format("-hls_mailbox_capacity(~p).", [Capacity]))),
        ok = file:write_file(Path, Replaced),
        ok = file:write_file(Stem ++ ".x", [xls_parse:to_xls(Path), probe(Capacity)])
    end, [64, 255]).

%% Populate a real mailbox, then observe the ordinary machine step and compacted contents.
-spec probe(64 | 255) -> iolist().
probe(Capacity) ->
    ["\nconst PROBE_CAPACITY = u32:", integer_to_list(Capacity), ";\n", """
pub fn selection_probe(pending: bits[PROBE_CAPACITY], occupied: u8) -> (u8, u8, u8) {
  let slots = for (i, slots): (u32, MailboxSlot[PROBE_CAPACITY]) in u32:0..PROBE_CAPACITY {
    let frame = axis::pack(Tag::VALUE as u8, hls_bits::frame_payload((i + u32:1) as u8));
    update(slots, i, MailboxSlot { frame, postponed: !((pending >> i) as u1) })
  }(zero!<MailboxSlot[PROBE_CAPACITY]>());
  let machine = Machine { slots, occupied, enter_pending: false, ..initial_machine() };
  let step = machine_step(machine, zero!<axis::Frame>(), false, true);
  let head = value_from_bits(step.machine.slots[u32:0].frame.payload).index;
  (step.machine.data.selected, step.machine.occupied, head)
}

#[test]
fn oldest_eligible() {
  // Empty, wholly postponed, and wholly eligible mailboxes retain their existing conventions.
  let all = !bits[PROBE_CAPACITY]:0;
  let size = PROBE_CAPACITY as u8;
  assert_eq(selection_probe(all, u8:0), (u8:0, u8:0, u8:1));
  assert_eq(selection_probe(bits[PROBE_CAPACITY]:0, size), (u8:0, size, u8:1));
  assert_eq(selection_probe(all, size), (u8:1, size - u8:1, u8:2));
  let indices = [u32:0, u32:1, u32:31, PROBE_CAPACITY / u32:2,
      PROBE_CAPACITY - u32:2, PROBE_CAPACITY - u32:1];
  for (case_index, ()): (u32, ()) in u32:0..u32:6 {
    let i = indices[case_index];
    let one = bits[PROBE_CAPACITY]:1 << i;
    let expected_head = if i == u32:0 { u8:2 } else { u8:1 };
    // A singleton eligible slot and the same slot followed by every younger slot choose identically.
    let expected = ((i + u32:1) as u8, size - u8:1, expected_head);
    assert_eq(selection_probe(one, size), expected);
    assert_eq(selection_probe(all << i, size), expected);
    // Slots beyond occupied cannot become eligible, even when their bits are set.
    assert_eq(selection_probe(all << i, i as u8), (u8:0, i as u8, u8:1));
  }(())
}
"""].
