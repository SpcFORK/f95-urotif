#!/usr/bin/env python3
"""Reference ablations first; the non-equivalent experimental chain is separate.
Run after `make all core95`. No network access or Oak install is needed here.
"""
from pathlib import Path
import hashlib
import json
import random
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'bin/urotif'


def command(args, stdin='', timeout=8):
    return subprocess.run([str(x) for x in args], cwd=ROOT, input=stdin,
                          text=True, capture_output=True, timeout=timeout)


def probe(path, stdin='', repair=False, fuel=200):
    args = [BIN, 'probe', path, '--fuel', str(fuel)]
    if repair:
        args.append('--repair')
    result = command(args, stdin)
    value = json.loads(result.stdout)
    if (result.returncode == 0) != value['ok']:
        raise AssertionError((result.returncode, value, result.stderr))
    return value


class ReferenceFixtures(unittest.TestCase):
    def test_reference_files_unchanged(self):
        manifest = json.loads((ROOT / 'reference/SHA256.json').read_text())
        for name, sha in manifest.items():
            self.assertEqual(hashlib.sha256((ROOT / 'reference' / name).read_bytes()).hexdigest(), sha, name)

    def test_revised_truth_without_repairs_exposes_receiver(self):
        r = probe('examples/truth-revised.utf', '2\n3\n')
        self.assertTrue(r['error'].startswith('P006'))
        self.assertEqual(r['stack'], ['0'])
        self.assertEqual((r['line'], r['column']), (2, 13))

    def test_revised_truth_first_iteration(self):
        r = probe('examples/truth-revised.utf', '2\n3\n', repair=True, fuel=21)
        self.assertEqual(r['output'], '0')
        self.assertEqual(r['stack'], [])
        self.assertTrue(r['error'].startswith('P008'))
        # The next PC is the first [, NOT the initial 0.
        self.assertEqual((r['line'], r['column']), (2, 2))

    def test_revised_truth_second_iteration(self):
        for stdin in ['2\n3\n', '0\n3\n']:
            r = probe('examples/truth-revised.utf', stdin, repair=True)
            self.assertEqual(r['output'], '0')
            self.assertTrue(r['error'].startswith('P001'))
            self.assertEqual(r['steps'], 38)
            self.assertEqual((r['line'], r['column']), (2, 18))

    def test_revised_truth_restart_column_comparison(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / 'restart.utf'
            source = (ROOT / 'examples/truth-revised.utf').read_text()
            path.write_text(source.replace('$21^', '$20^'))
            r = probe(path, '2\n3\n', repair=True, fuel=42)
            self.assertEqual(r['output'], '00')
            self.assertTrue(r['error'].startswith('P008'))
            self.assertEqual((r['line'], r['column']), (2, 1))

    def test_original_hello(self):
        r = probe('reference/smp/hello.utf')
        self.assertTrue(r['ok'])
        self.assertEqual(r['output'], 'Hello, World!\n')
        self.assertEqual(r['stack'], [])

    def test_original_anb_is_text_not_numeric(self):
        r = probe('reference/smp/anb.utf', '2\n3\n')
        self.assertTrue(r['ok'])
        self.assertEqual(r['output'], '32')  # Empirically observed from Oak.

    def test_original_bin_is_headerless_character_data(self):
        r = probe('reference/smp/bin.uru')
        self.assertTrue(r['ok'])
        self.assertEqual(r['output'], '')
        self.assertEqual(r['stack'], list('fcda123ad'))

    def test_original_fib_source_bug_is_not_hidden(self):
        r = probe('reference/smp/fib.utf')
        self.assertFalse(r['ok'])
        self.assertTrue(r['error'].startswith('P005'))
        self.assertEqual((r['line'], r['column']), (2, 7))

    def test_original_fib_with_explicit_index_repair(self):
        r = probe('reference/smp/fib.utf', repair=True)
        self.assertTrue(r['ok'])
        self.assertEqual(r['output'], '')  # This fixture is NOT a sequence printer.
        self.assertEqual(r['stack'], [['0', '1'], '0'])

    def test_original_truth_exposes_call_receiver_bug(self):
        r = probe('reference/smp/truth.utf', '2\n3\n')
        self.assertTrue(r['error'].startswith('P006'))
        self.assertEqual((r['line'], r['column']), (2, 12))

    def test_original_truth_after_repairs_still_underflows(self):
        for input_text in ['0\n', '2\n']:
            r = probe('reference/smp/truth.utf', input_text, repair=True)
            self.assertFalse(r['ok'])
            self.assertTrue(r['error'].startswith('P001'))
            self.assertEqual((r['line'], r['column']), (2, 17))

    def test_original_urb_raw_dispatch_is_not_a_bytecode_loader(self):
        r = probe('reference/smp/hello.urb')
        self.assertTrue(r['ok'])
        self.assertEqual(r['output'], '<')
        self.assertEqual(r['stack'], list(' prarr Hello, World'))

    def test_strict_f95_entrypoint(self):
        r = command([ROOT / 'bin/urotif95'], 'run\nreference/smp/hello.utf\n')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, 'Hello, World!\n')

    def test_reference_wasm_is_not_silently_reinterpreted(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td) / 'bad.wasm'
            r = command([BIN, 'wasm', 'reference/smp/anb.utf', '-o', output])
            self.assertNotEqual(r.returncode, 0)
            self.assertIn('not yet ported', r.stderr)
            self.assertFalse(output.exists())

    def test_input_without_final_newline(self):
        r = probe('reference/smp/anb.utf', '2\n3')
        self.assertTrue(r['ok'])
        self.assertEqual(r['output'], '32')

    def test_source_macro_table_ignores_unescaped_non_ascii(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / 'unicode.utf'
            path.write_text('=) urotif\n[caf\u00e9  ]P@')
            r = probe(path)
            self.assertTrue(r['ok'])
            self.assertEqual(r['output'], 'caf  \n')  # Source only installs ASCII push macros.

    def test_bounded_random_character_programs_do_not_crash(self):
        rng = random.Random(9471)
        alphabet = 'abc0123[]{}%_$+-*|~:;@^=#!\\`\n '
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / 'fuzz.utf'
            for _ in range(100):
                path.write_text('=) urotif\n' + ''.join(rng.choice(alphabet) for _ in range(80)))
                result = probe(path, '2\n3\n', repair=bool(rng.randrange(2)), fuel=100)
                self.assertLessEqual(result['steps'], 100)


class Ablations(unittest.TestCase):
    pass


def make_ablation(case):
    def test(self):
        result = probe(case['path'], case['stdin'], case['repair'], case['fuel'])
        self.assertEqual(result['output'], case['output'])
        if 'stack' in case:
            self.assertEqual(result['stack'], case['stack'])
        if case.get('error'):
            self.assertFalse(result['ok'])
            self.assertTrue(result['error'].startswith(case['error']), result)
        else:
            self.assertTrue(result['ok'], result)
    return test


for case in json.loads((ROOT / 'tests/ablation-cases.json').read_text()):
    setattr(Ablations, 'test_' + case['name'].replace('-', '_'), make_ablation(case))


# This suite is deliberately separate: it tests linking/lowering, NOT Oak parity.
CORE_CASES = [
    ('hello', '[Hello, World\\!]P@', 'Hello, World!\n', '', 0),
    ('add', '{2}{3}+println', '5\n', '', 0),
    ('sub', '{8}{3}-println', '5\n', '', 0),
    ('div', '{6}{4}|println', '1.500000000000000E+000\n', '', 0),
    ('mod', '{8}{3}mod println', '2\n', '', 0),
    ('neg', '{8}~println', '-8\n', '', 0),
    ('swap_over_rot', '{1}{2}over rot swap println println println', '1\n1\n2\n', '', 0),
    ('drop_dup', '{3}%_println', '3\n', '', 0),
    ('text_register', '[abc]store x load x println', 'abc\n', '', 0),
    ('read_numbers', 'read read add println', '5\n', '2\n3\n', 0),
    ('equal_text', '[a][a]eq println [a][b]ne println', '1\n1\n', '', 0),
    ('typed_equality', '[1]{1}eq println', '0\n', '', 0),
    ('order', '{1}{2}lt println {2}{2}le println {3}{2}gt println {3}{3}ge println', '1\n1\n1\n1\n', '', 0),
    ('ifz', '{0}ifz yes [bad]println :yes [ok]println', 'ok\n', '', 0),
    ('ifnz', '{1}ifnz yes [bad]println :yes [ok]println', 'ok\n', '', 0),
    ('goto', 'goto done [bad]println :done [ok]println', 'ok\n', '', 0),
    ('underflow', '+', '', '', 1),
    ('bad_type', '[text]{1}+', '', '', 3),
    ('zero_div', '{1}{0}|', '', '', 4),
    ('uninitialized', 'load missing', '', '', 6),
    ('no_input', 'read', '', '', 9),
    ('bad_input', 'read', '', '1,2\n', 9),
    ('nonfinite', '{1e308}{1e308}*', '', '', 10),
    ('loop_fuel', ':again goto again', '', '', 8),
    ('stack_bound', ':again {1}goto again', '', '', 2),
    ('empty', '', '', '', 0),
    ('unicode', '[h\u00e9llo]println', 'h\u00e9llo\n', '', 0),
]


class ExperimentalChain(unittest.TestCase):
    def compare(self, body, expected, stdin='', expected_status=0, whole=False):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / 'program with space.utf'
            wasm = Path(td) / 'program.wasm'
            path.write_text(body if whole else '=) urotif\n' + body)
            fuel = 10000 if expected_status != 8 else 30
            native = command([BIN, 'run', path, '--core', '--fuel', str(fuel)], stdin)
            compile_result = command([BIN, 'wasm', path, '--core', '-o', wasm])
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            machine = command(['node', ROOT / 'tools/wasm-run.mjs', wasm, '--json', '--fuel', str(fuel), '--repeat', '2'], stdin)
            results = json.loads(machine.stdout)
            self.assertIsInstance(results, list, results)
            self.assertEqual(results[0], results[1], 'WASM must reset its state on each run')
            result = results[0]
            self.assertEqual(result['status'], expected_status, result)
            self.assertEqual(result['output'], expected)
            self.assertEqual(native.stdout, expected)
            self.assertEqual(native.returncode == 0, expected_status == 0, native.stderr)
            if expected_status:
                self.assertIn('runtime E' + str(expected_status) + ':', native.stderr)
                self.assertIn(f":{result['line']}:{result['column']}:", native.stderr)

    def test_recursive_subroutine(self):
        self.compare('''=) urotif
=) fact
  dup {1}le ifnz base
  dup {1}- call fact * return
:base
  drop {1}
end
=) main
  {6}call fact println
end
''', '720\n', whole=True)

    def test_return_stack_limit(self):
        self.compare('=) urotif\n=) main\ncall main\nend', '', expected_status=5, whole=True)

    def test_goto_cannot_cross_routines(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / 'bad.utf'
            p.write_text('=) urotif\n=) a\n:other return\nend\n=) main\ngoto other\nend')
            r = command([BIN, 'check', p, '--core'])
            self.assertNotEqual(r.returncode, 0)
            self.assertIn('unknown local label', r.stderr)

    def test_core_parser_rejects_malformed_source(self):
        cases = ['=) urotif\n[unterminated', '=) urotif\n{1,2}', '=) urotif\n{1e999}',
                 '=) urotif\n=) main\n', '=) urotif\ngoto absent', '=) urotif\n@',
                 '=) urotif\n:a :a', '=) urotif\n=) x\nend', '', '=) wrong']
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / 'bad.utf'
            for source in cases:
                p.write_text(source)
                r = command([BIN, 'check', p, '--core'])
                self.assertNotEqual(r.returncode, 0, source)
                self.assertNotIn('Fortran runtime error', r.stderr)


def make_core(case):
    def test(self):
        _, body, expected, stdin, status = case
        self.compare(body, expected, stdin, status)
    return test


for case in CORE_CASES:
    setattr(ExperimentalChain, 'test_' + case[0], make_core(case))


if __name__ == '__main__':
    unittest.main(verbosity=2)
