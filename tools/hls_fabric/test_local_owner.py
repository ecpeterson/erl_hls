"""Finite source-transaction and RTL witnesses for the clocked DSLX actor owner."""
from pathlib import Path
import argparse
import json

from compiler_paths import compiler_resource, compiler_root
from backend_paths import ROOT, erlang_environment, application_directory
from backend_commands import run


# Frames are constructed by the generated source codecs, including their tags.
PLAIN = """
const OWNER_MESSAGES = u32:3;
// The finite request sequence retains source codecs and declared schemas.
fn owner_message(i: u32) -> bits[128] {
  let value = match i { u32:0 => u32:3, u32:1 => u32:5, _ => u32:9 };
  axis::bits_from_frame(axis::Frame { header: axis::Header { op: Tag::ADD as u8,
    payload_words: u8:1, ..zero!<axis::Header>() }, payload: bits_from_add(Add { value }) as bits[96] })
}
// Check application values and require the intended control paths to execute.
fn owner_readout(w: OwnerWitness) {
  assert_eq(machine_from_bits(w.owner.machine).data.value, u32:8);
  assert_eq(local_observe(w.owner.machine, u32:0).failure != u16:0, true);
  assert_eq(w.emitted, u32:2);
  assert_eq(w.stalled > u32:10, true);
}
"""
SCALAR = """
const OWNER_MESSAGES = u32:5;
// The finite request sequence retains source codecs and declared schemas.
fn owner_message(i: u32) -> bits[128] {
  let (op, words, payload) = if i < u32:2 {
    (Tag::COUNT_VALUE as u8, u8:2, bits_from_countvalue(Countvalue { key: u32:0, value: i+u32:2 }) as bits[96])
  } else {
    let member = match i { u32:2 => u32:9, u32:3 => u32:2, _ => u32:7 };
    (Tag::MEMBER_VALUE as u8, u8:3, bits_from_membervalue(Membervalue { key: u32:0, member, value: i+u32:2 }) as bits[96])
  };
  axis::bits_from_frame(axis::Frame { header: axis::Header { op, payload_words: words,
    ..zero!<axis::Header>() }, payload })
}
// Check application values and require the intended control paths to execute.
fn owner_readout(w: OwnerWitness) {
  assert_eq(machine_from_bits(w.owner.machine).data.value, u32:15);
  assert_eq(local_observe(w.owner.machine, u32:0).failure, u16:0);
  assert_eq(w.emitted, u32:0);
}
"""
GATHER = """
const OWNER_MESSAGES = u32:5;
// The finite request sequence retains source codecs and declared schemas.
fn owner_message(i: u32) -> bits[128] {
  let (op, words, payload) = match i {
    u32:1 => (Tag::BEGIN_SET as u8, u8:2,
      bits_from_beginset(Beginset { key: u32:2, mask: u8:5 }) as bits[96]),
    u32:4 => (Tag::SCALAR as u8, u8:2,
      bits_from_scalar(Scalar { key: u32:2, value: u8:5 }) as bits[96]),
    _ => (Tag::PIECE as u8, u8:3, bits_from_piece(Piece { key: u32:2,
      member: if i == u32:2 { u32:2 } else { u32:0 },
      value: if i == u32:2 { u8:3 } else { u8:7 } }) as bits[96]),
  };
  axis::bits_from_frame(axis::Frame { header: axis::Header { op, payload_words: words,
    ..zero!<axis::Header>() }, payload })
}
// Check application values and require the intended control paths to execute.
fn owner_readout(w: OwnerWitness) {
  assert_eq(machine_from_bits(w.owner.machine).data.value, u32:312);
  assert_eq(local_observe(w.owner.machine, u32:0).failure, u16:0);
  assert_eq(w.emitted, u32:2);
  assert_eq(w.deferred, u32:1);
  assert_eq(w.postponed, u32:1);
  assert_eq(w.stalled > u32:0, true);
}
"""


def check_provider_initializers(xls: Path, stage: Path, paths: str, public: Path) -> None:
    """Lower provider-backed initialization with the same compiler sources and beams as the owner."""
    # Actual provider-backed initializers must lower as a clocked proc, not constexpr.
    providers = application_directory('hls_phi', 'default')/'src'
    provider_options = stage/'provider-options.term'
    provider_options.write_text('[{i,'+json.dumps(str(public/'include'))+'},{i,'+
                                json.dumps(str(providers.parent/'include'))+'},{i,'+json.dumps(str(providers))+'}].\n')
    for role in ['phi_line_cell', 'phi_halo_cell']:
        generated = stage/(role+'.x')
        run(['escript', 'tools/hls_fabric/emit_local_actor.escript', providers/(role+'.erl'),
             provider_options, generated], stage, role+'-emit', env=erlang_environment('default', compiler=public))
        run([xls/'ir_converter_main', '--top=local_owner_clock',
             '--warnings_as_errors=false', '--dslx_path='+paths+':'+str(providers),
             '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'), generated],
            stage, role+'-convert', stage/(role+'.ir'))


def main() -> None:
    """Exercise actual builders, original executor comparisons, reset and compiled RTL."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda p: Path(p).resolve())
    parser.add_argument('stage', type=lambda p: Path(p).resolve())
    parser.add_argument('--cases', nargs='+', choices=['plain', 'batch', 'scalar', 'gather'],
                        default=['plain', 'batch', 'scalar', 'gather'])
    args = parser.parse_args()
    stage = args.stage
    stage.mkdir()
    run(['rebar3', 'compile'], stage, 'build')
    public = compiler_root('default')
    options = stage/'options.term'
    options.write_text('[].\n')
    paths = ':'.join(map(str, [ROOT/'apps/hls_target/priv/xls/lib', ROOT/'apps/hls_fabric/priv/xls/fabric',
                              compiler_resource(public, 'hls_compile', 'priv/xls/lib'),
                              compiler_resource(public, 'hls_fabric', 'priv/xls/fabric')]))
    common = ['--warnings_as_errors=false', '--dslx_path='+paths,
              '--dslx_stdlib_path='+str(args.xls/'xls/dslx/stdlib')]
    batch_source = stage/'batch.erl'
    batch_source.write_text((ROOT/'apps/hls_fabric/test/hls_local_actor_fixture.erl').read_text().replace(
        '-hls_outputs([result]).', '-hls_outputs([result, extra]).').replace(
        '{cast, result, #total{value = Value}}',
        '{cast, result, #total{value = Value}}, {cast, extra, #total{value = Value + 100}}'))
    cases = [('batch', batch_source, PLAIN.replace('w.emitted, u32:2', 'w.emitted, u32:4')),
             ('plain', ROOT/'apps/hls_fabric/test/hls_local_actor_fixture.erl', PLAIN),
             ('scalar', public/'test_data/hls_statem_reduction_lower_fixture.erl', SCALAR),
             ('gather', public/'test_data/xls_statem_gather_fixture.erl', GATHER)]
    cases = [case for case in cases if case[0] in args.cases]
    for name, source, fixture in cases:
        generated = stage/(name+'.x')
        run(['escript', 'tools/hls_fabric/emit_local_actor.escript', source, options, generated], stage, name+'-emit',
            env=erlang_environment('default', compiler=public))
        test = stage/(name+'_test.x')
        test.write_bytes(generated.read_bytes() + (ROOT/'apps/hls_fabric/test/local_owner_semantics.x.in').read_bytes().replace(b'@@FIXTURE@@', fixture.encode()))
        run([args.xls/'interpreter_main', '--evaluator=ir-jit', '--compare=none', *common, test], stage, name+'-witness')
        run(['python3', 'tools/hls_fabric/compile_local_actor.py', '--erl-hls', public, args.xls, generated, stage/(name+'-rtl')],
            stage, name+'-rtl-build')
    for name, _, _ in cases:
        role = {'plain':0, 'scalar':1, 'gather':2, 'batch':3}[name]
        run(['iverilog', '-g2012', '-s', 'tb', '-Ptb.ROLE='+str(role), '-o', stage/(name+'-sim'),
             stage/(name+'-rtl/actor.v'), ROOT/'apps/hls_fabric/test/rtl/local_owner_tb.sv'], stage, name+'-rtl-compile')
        run(['vvp', stage/(name+'-sim')], stage, name+'-rtl-sim')
        assert 'LOCAL_OWNER_PASS' in (stage/(name+'-rtl-sim.log')).read_text()
    check_provider_initializers(args.xls, stage, paths, public)
    (stage/'result.json').write_text(json.dumps({'passed':True, 'source_roles':[n for n, _, _ in cases],
        'witness_clocks_per_role':160, 'reset_positions_per_role':60, 'provider_initializers':['phi_line_cell', 'phi_halo_cell'],
        'evidence':'finite whole-test JIT and RTL witnesses; no general refinement or progress theorem'}, indent=2)+'\n')


if __name__ == '__main__':
    main()
