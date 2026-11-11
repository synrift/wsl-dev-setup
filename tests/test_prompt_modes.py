"""Isolated installer checks; no system installation or real agent execution."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PromptModes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.home), BASH_ENV='', ZDOTDIR=str(self.home))
        self.env.pop('PROMPT_MODE', None)

    def bash(self, body, mode=None, success=True):
        env = dict(self.env)
        if mode is not None:
            env['PROMPT_MODE'] = mode
        result = subprocess.run(['bash', '-c', 'source ./install.sh\n' + body],
                                cwd=ROOT, env=env, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def generate(self, mode):
        self.bash('validate_prompt_mode; write_node_helpers; configure_zshenv; '
                  'configure_zshrc; configure_bash', mode)

    def test_default_and_valid_modes(self):
        self.assertEqual(self.bash('validate_prompt_mode; printf "%s" "$PROMPT_MODE"').stdout,
                         'starship')
        for mode in ('warp', 'starship'):
            with self.subTest(mode=mode):
                self.bash('validate_prompt_mode', mode)

    def test_invalid_modes_fail_before_installation(self):
        for mode in ('', 'Warp', 'other', 'warp; echo injected'):
            with self.subTest(mode=mode):
                result = self.bash('main', mode, success=False)
                self.assertIn('PROMPT_MODE must be', result.stderr)
                self.assertNotIn('Updating apt', result.stdout)

    def test_package_selection(self):
        for mode in ('warp', 'starship'):
            with self.subTest(mode=mode):
                result = self.bash('sudo() { printf "%s\\n" "$*"; }; install_system_packages', mode)
                install = next(line for line in result.stdout.splitlines() if line.startswith('apt install'))
                for common in ('zsh', 'zenity', 'bubblewrap', 'systemd', 'python3'):
                    self.assertIn(common, install.split())
                self.assertNotIn('zoxide', install.split())
                for plugin in ('zsh-autosuggestions', 'zsh-syntax-highlighting'):
                    self.assertEqual(plugin in install.split(), mode == 'starship')

    def test_warp_skips_starship_network_and_configuration(self):
        self.bash('curl() { return 97; }; install_starship', 'warp')
        self.assertFalse((self.home / '.config/starship.toml').exists())

    def test_generated_configuration_and_syntax(self):
        for mode in ('warp', 'starship'):
            with self.subTest(mode=mode):
                self.generate(mode)
                rc = (self.home / '.zshrc').read_text()
                self.assertIn('compinit', rc)
                self.assertNotIn('zoxide', rc)
                self.assertEqual('starship init zsh' in rc, mode == 'starship')
                self.assertEqual('source /usr/share/zsh-autosuggestions/' in rc, mode == 'starship')
                self.assertEqual('source /usr/share/zsh-syntax-highlighting/' in rc, mode == 'starship')
                self.assertNotIn('PROMPT_MODE', rc)  # No inherited variable needed at startup.
                for name in ('.zshrc', '.zshenv', '.local/lib/wsl-dev/node-env.sh'):
                    subprocess.run(['zsh', '-n', str(self.home / name)], check=True)
                subprocess.run(['bash', '-n', str(self.home / '.local/lib/wsl-dev/prepare-node')], check=True)

    def test_runtime_outputs_identical_between_modes(self):
        files = ('.zshenv', '.bashrc', '.profile', '.local/lib/wsl-dev/node-env.sh',
                 '.local/lib/wsl-dev/prepare-node')
        self.generate('warp')
        first = {name: (self.home / name).read_bytes() for name in files}
        # Fresh installation fixtures, not a repeat-installation test.
        for name in files + ('.zshrc',):
            (self.home / name).unlink()
        self.generate('starship')
        for name in files:
            self.assertEqual(first[name], (self.home / name).read_bytes(), name)

    def test_real_zsh_loading_with_simulated_runtime(self):
        # Isolate prompt loading from fnm downloads. This does NOT validate fnm.
        bin_dir = self.home / 'bin'
        bin_dir.mkdir()
        starship = bin_dir / 'starship'
        starship.write_text("#!/bin/sh\nprintf '%s\\n' 'typeset -g STARSHIP_TEST_LOADED=yes'\n")
        starship.chmod(0o755)
        for mode in ('warp', 'starship'):
            self.generate(mode)
            (self.home / '.local/lib/wsl-dev/node-env.sh').write_text(
                'export RUNTIME_TEST_LOADED=yes\n')
            for flags in ('-c', '-lc', '-ic', '-lic'):
                with self.subTest(mode=mode, flags=flags):
                    env = dict(self.env, PATH=str(bin_dir) + ':' + os.environ['PATH'])
                    env.pop('PROMPT_MODE', None)
                    result = subprocess.run(['zsh', flags,
                        '[[ $RUNTIME_TEST_LOADED == yes ]] || exit 31; '
                        'if [[ -o interactive ]]; then '
                        'print -r -- "${STARSHIP_TEST_LOADED:-no}"; '
                        '(( $+functions[compdef] )) || exit 32; '
                        'else print -r -- "${STARSHIP_TEST_LOADED:-no}"; fi'],
                        cwd=self.home, env=env, text=True, capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    expected = 'yes' if mode == 'starship' and 'i' in flags else 'no'
                    self.assertEqual(result.stdout.strip(), expected)


if __name__ == '__main__':
    unittest.main()
