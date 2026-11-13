"""Real fnm/Node checks; opt in with FNM_TEST_BIN and FNM_TEST_DIR.

FNM_TEST_DIR must contain prepared node-versions/v22.* and v24.* installations.
These tests never download or install tools. All configuration is temporary.
"""
import concurrent.futures
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FNM = os.environ.get('FNM_TEST_BIN')
INSTALLS = os.environ.get('FNM_TEST_DIR')


@unittest.skipUnless(FNM and INSTALLS, 'Set FNM_TEST_BIN and FNM_TEST_DIR for real runtime checks')
class NodeRuntime(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.fnm_dir = self.home / '.local/share/fnm'
        self.fnm_dir.mkdir(parents=True)
        (self.fnm_dir / 'fnm').symlink_to(Path(FNM).resolve())
        versions = self.fnm_dir / 'node-versions'
        versions.mkdir()
        self.versions = {}
        for major in (22, 24):
            source = sorted((Path(INSTALLS) / 'node-versions').glob(f'v{major}.*'))[-1]
            (versions / source.name).symlink_to(source.resolve(), target_is_directory=True)
            self.versions[major] = source.name
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(('FNM_', 'WSL_FNM_', '_wsl_'))
                    and k not in ('BASH_ENV', 'ZDOTDIR', 'COREPACK_INTEGRITY_KEYS', 'NODE_OPTIONS')}
        self.env.update(HOME=str(self.home), ZDOTDIR=str(self.home), FNM_DIR=str(self.fnm_dir),
                        BASH_ENV='', COREPACK_ENABLE_NETWORK='0',
                        PATH=str(self.fnm_dir) + ':' + os.environ['PATH'])
        subprocess.run([FNM, 'default', '24'], env=self.env, check=True, capture_output=True)
        subprocess.run(['bash', '-c', 'source ./install.sh; write_node_helpers; '
                        'configure_zshenv; configure_zshrc; configure_bash'],
                       cwd=ROOT, env=self.env, check=True, capture_output=True)
        pnpm_cache = os.environ.get('FNM_TEST_PNPM_CACHE')
        if pnpm_cache:
            cache = self.home / '.cache/node/corepack'
            cache.parent.mkdir(parents=True)
            cache.symlink_to(Path(pnpm_cache).resolve(), target_is_directory=True)
        self.projects = {}
        for major in (22, 24):
            project = self.home / f'project{major}'
            (project / 'src').mkdir(parents=True)
            (project / ('.nvmrc' if major == 22 else '.node-version')).write_text(str(major) + '\n')
            self.projects[major] = project

    def run_shell(self, script, cwd=None, shell='zsh', flags='-c', success=True):
        env = dict(self.env)
        if shell == 'bash':
            env['BASH_ENV'] = str(self.home / '.local/lib/wsl-dev/node-env.sh')
        result = subprocess.run([shell, flags, script], cwd=cwd or self.home, env=env,
                                text=True, capture_output=True, timeout=20)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_project_versions_in_new_shells_and_children(self):
        for major, project in self.projects.items():
            for shell, flags in [('zsh', '-c'), ('zsh', '-lc'), ('zsh', '-ic'),
                                 ('zsh', '-lic'), ('bash', '-c'), ('bash', '-lc')]:
                with self.subTest(major=major, shell=shell, flags=flags):
                    result = self.run_shell('node --version', project / 'src', shell, flags)
                    self.assertEqual(result.stdout.strip(), self.versions[major])
            child = self.run_shell('zsh -c "node --version"; bash -c "node --version"', project)
            self.assertEqual(child.stdout.splitlines(), [self.versions[major]] * 2)

    def test_default_and_native_manual_use_exec(self):
        result = self.run_shell('node --version; fnm use 22 >/dev/null; node --version; '
                                'fnm exec --using 24 node --version; '
                                'whence -w fnm cd pushd popd')
        lines = result.stdout.splitlines()
        self.assertEqual(lines[:3], [self.versions[24], self.versions[22], self.versions[24]])
        self.assertIn('fnm: command', lines)
        for name in ('cd', 'pushd', 'popd'):
            self.assertIn(name + ': builtin', lines)

    def test_official_interactive_zsh_directory_hook(self):
        result = self.run_shell('cd ' + shlex.quote(str(self.projects[22])) + '; node --version; '
                                'cd ' + shlex.quote(str(self.projects[24] / 'src')) + '; node --version',
                                flags='-ic')
        self.assertEqual(result.stdout.splitlines()[-1], self.versions[24])
        noninteractive = self.run_shell('cd ' + shlex.quote(str(self.projects[22])) + '; node --version')
        self.assertEqual(noninteractive.stdout.strip(), self.versions[22])
        self.assertIn(self.versions[22], result.stdout)

    def test_missing_version_does_not_execute_task_or_install(self):
        project = self.home / 'missing'
        project.mkdir()
        (project / '.node-version').write_text('99.0.0\n')
        for shell in ('zsh', 'bash'):
            result = self.run_shell('echo TASK_EXECUTED', project, shell, success=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('TASK_EXECUTED', result.stdout)
            self.assertIn('not currently installed', result.stderr)
        self.assertFalse((self.fnm_dir / 'node-versions/v99.0.0').exists())

    def test_project_through_symlink(self):
        link = self.home / 'linked-src'
        link.symlink_to(self.projects[22] / 'src', target_is_directory=True)
        self.assertEqual(self.run_shell('node --version', link).stdout.strip(), self.versions[22])

    def test_read_only_home_for_prepared_node(self):
        # fnm's per-shell state is in /tmp, not HOME.
        directories = [p for p in self.home.rglob('*') if p.is_dir() and not p.is_symlink()]
        directories.append(self.home)
        for directory in directories:
            directory.chmod(0o555)
        try:
            result = self.run_shell('node --version; git --version', self.projects[22])
            self.assertEqual(result.stdout.splitlines()[0], self.versions[22])
        finally:
            for directory in directories:
                directory.chmod(0o755)

    def test_concurrent_project_shells(self):
        majors = [22, 24] * 4
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda m: self.run_shell('node --version', self.projects[m]), majors))
        for major, result in zip(majors, results):
            self.assertEqual(result.stdout.strip(), self.versions[major])

    def test_git_startup_does_not_run_node_or_package_tools(self):
        # Real fnm, but trap every runtime/package executable. Git must still run.
        version = self.fnm_dir / 'node-versions' / self.versions[24]
        version.unlink()
        bin_dir = version / 'installation/bin'
        bin_dir.mkdir(parents=True)
        for command in ('node', 'npm', 'npx', 'corepack', 'pnpm', 'curl', 'flock'):
            trap = bin_dir / command
            trap.write_text('#!/bin/sh\necho unexpected-tool >&2\nexit 93\n')
            trap.chmod(0o755)
        result = self.run_shell('git --version; printf "ok\\n"', self.projects[24])
        self.assertNotIn('unexpected-tool', result.stderr)
        self.assertTrue(result.stdout.endswith('ok\n'))

    @unittest.skipUnless(os.environ.get('FNM_TEST_PNPM_CACHE'), 'Set FNM_TEST_PNPM_CACHE to a warmed Corepack cache')
    def test_prepared_package_tools(self):
        result = self.run_shell('npm --version; corepack --version; pnpm --version', self.projects[24])
        versions = result.stdout.splitlines()
        self.assertEqual(len(versions), 3)
        (self.projects[24] / 'package.json').write_text(
            '{"packageManager":"pnpm@' + versions[-1] + '"}\n')
        pinned = self.run_shell('pnpm exec node --version', self.projects[24])
        self.assertEqual(pinned.stdout.splitlines()[-1], self.versions[24])


if __name__ == '__main__':
    unittest.main()
