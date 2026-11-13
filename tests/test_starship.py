"""Isolated installer checks; no system installation or real agent execution."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class StarshipConfiguration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.home), BASH_ENV='', ZDOTDIR=str(self.home))

    def bash(self, body, success=True):
        env = dict(self.env)
        result = subprocess.run(['bash', '-c', 'source ./install.sh\n' + body],
                                cwd=ROOT, env=env, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def generate(self):
        self.bash('write_node_helpers; configure_zshenv; '
                  'configure_zshrc; configure_bash')

    def test_package_selection(self):
        result = self.bash('sudo() { printf "%s\\n" "$*"; }; install_system_packages')
        install = next(line for line in result.stdout.splitlines() if line.startswith('apt install'))
        for package in ('zsh', 'zenity', 'bubblewrap', 'systemd', 'python3',
                        'zsh-autosuggestions', 'zsh-syntax-highlighting'):
            self.assertIn(package, install.split())
        self.assertNotIn('zoxide', install.split())

    def test_generated_configuration_and_syntax(self):
        self.generate()
        rc = (self.home / '.zshrc').read_text()
        self.assertIn('compinit', rc)
        self.assertNotIn('zoxide', rc)
        self.assertIn('starship init zsh', rc)
        self.assertIn('source /usr/share/zsh-autosuggestions/', rc)
        self.assertIn('source /usr/share/zsh-syntax-highlighting/', rc)
        self.assertNotIn('PROMPT_MODE', rc)  # No inherited variable needed at startup.
        for name in ('.zshrc', '.zshenv', '.local/lib/wsl-dev/node-env.sh'):
            subprocess.run(['zsh', '-n', str(self.home / name)], check=True)
        subprocess.run(['bash', '-n', str(self.home / '.local/lib/wsl-dev/node-env.sh')], check=True)

    def test_installation_verifies_starship_and_noninteractive_zsh(self):
        bin_dir = self.home / '.local/bin'
        bin_dir.mkdir(parents=True)
        starship = bin_dir / 'starship'
        starship.write_text('#!/bin/sh\nprintf "starship %s\\n" "$*"\n')
        starship.chmod(0o755)
        result = self.bash('''
zsh() { printf 'zsh %s\\n' "$1"; }
bash() { printf 'bash %s\\n' "$1"; }
sudo() { :; }
docker() { :; }
npm() { :; }
node() { cat >/dev/null; }
verify_installation
''')
        self.assertIn('starship --version', result.stdout)
        for flag in ('-c', '-lc', '-ic'):
            self.assertIn('zsh ' + flag + '\n', result.stdout)
        self.assertIn('bash -c\n', result.stdout)

    def test_real_zsh_loading_with_simulated_runtime(self):
        # Isolate prompt loading from fnm downloads. This does NOT validate fnm.
        bin_dir = self.home / 'bin'
        bin_dir.mkdir()
        starship = bin_dir / 'starship'
        starship.write_text("#!/bin/sh\nprintf '%s\\n' 'typeset -g STARSHIP_TEST_LOADED=yes'\n")
        starship.chmod(0o755)
        self.generate()
        (self.home / '.local/lib/wsl-dev/node-env.sh').write_text(
            'export RUNTIME_TEST_LOADED=yes\n')
        for flags in ('-c', '-lc', '-ic', '-lic'):
            with self.subTest(flags=flags):
                env = dict(self.env, PATH=str(bin_dir) + ':' + os.environ['PATH'])
                result = subprocess.run(['zsh', flags,
                    '[[ $RUNTIME_TEST_LOADED == yes ]] || exit 31; '
                    'if [[ -o interactive ]]; then '
                    'print -r -- "${STARSHIP_TEST_LOADED:-no}"; '
                    '(( $+functions[compdef] )) || exit 32; '
                    'else print -r -- "${STARSHIP_TEST_LOADED:-no}"; fi'],
                    cwd=self.home, env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = 'yes' if 'i' in flags else 'no'
                self.assertEqual(result.stdout.strip(), expected)


if __name__ == '__main__':
    unittest.main()
