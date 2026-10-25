"""Isolated external-tool fixtures for compiler and embedding-project tests."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from . import compile_xls as compiler


STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, sys, time
p = pathlib.Path
stage = {'ir_converter_main': 'ir', 'opt_main': 'opt', 'codegen_main': 'codegen'}[p(sys.argv[0]).name]
with open(os.environ['XLS_TEST_CALLS'], 'a') as log:
    log.write(stage + '\n')
if os.environ.get('XLS_TEST_PAUSE') == stage:
    p(os.environ['XLS_TEST_READY']).write_text(str(os.getpid()))
    time.sleep(float(os.environ.get("XLS_TEST_SLEEP", "1")))
if os.environ.get('XLS_TEST_FAIL') == stage:
    print('partial output')
    print('injected failure', file=sys.stderr)
    sys.exit(7)
if stage == 'ir':
    inputs = {str(f): f.read_text() for pattern in ['*.x', '_stdlib/**/*.x'] for f in sorted(p('.').glob(pattern))}
else:
    inputs = p(sys.argv[-1]).read_text()
result = {'stage': stage, 'args': sys.argv[1:], 'inputs': inputs}
if os.environ.get('XLS_TEST_NONDETERMINISTIC') == stage:
    result['node_id'] = os.getpid()
print(json.dumps(result, sort_keys=True))
'''


class BuildFixture(unittest.TestCase):
    """Isolated tool stubs and publication directories for compiler-runner tests."""
    def setUp(self) -> None:
        """Create isolated fake XLS commands and restore their environment after each test."""
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.inputs = self.root / 'input with spaces'
        self.inputs.mkdir()
        self.source = self.inputs / 'counter.x'
        self.source.write_text('import helper;\n')
        (self.inputs / 'helper.x').write_text('pub const VALUE = u32:1;\n')
        self.xls = self.root / 'xls'
        self.xls.mkdir()
        for tool in compiler.TOOLS:
            path = self.xls / tool
            path.write_text(STUB)
            path.chmod(0o755)
        stdlib = self.xls / 'xls/dslx/stdlib'
        stdlib.mkdir(parents=True)
        (stdlib / 'std.x').write_text('// test standard library\n')
        self.calls = self.root / 'calls'
        environment = patch.dict(os.environ, {'XLS_TEST_CALLS': str(self.calls)})
        environment.start()
        self.addCleanup(environment.stop)
        self.output = self.root / 'published'
        self.cache = self.root / 'cache'

    def build(self, **options) -> Path:
        """Compile the fixture with stub commands using the requested runner options."""
        return compiler.build(self.source, self.xls, self.output, cache=self.cache, **options)

    def statuses(self, output: Path | None = None) -> dict[str, bool]:
        """Read whether each recorded compiler stage reused a cached result."""
        report = json.loads((output or self.output).with_suffix('.run.json').read_text())
        return {name: row['reused'] for name, row in report['stages'].items()}
