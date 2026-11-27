from __future__ import annotations

from typing import TYPE_CHECKING

import executable_shell_installer as shell_installer

if TYPE_CHECKING:
    import pytest


def test_shared_dependency_installs_once(monkeypatch: pytest.MonkeyPatch) -> None:
    commands: list[str] = []
    monkeypatch.setattr(shell_installer, "run_shell_command", commands.append)
    monkeypatch.setattr(shell_installer, "load_all_tools", lambda: [{"name": "mise", "method": "binary"}])
    monkeypatch.setattr(shell_installer, "_installed_dependencies", set())

    shell_installer.shell_installer(
        [
            {"name": "claude", "dependencies": ["mise"]},
            {"name": "csvkit", "dependencies": ["mise"]},
        ]
    )

    assert commands == ["FLAG_INSTALL_NOT_EXISTS_ONLY=true tep_binary -t mise"]
