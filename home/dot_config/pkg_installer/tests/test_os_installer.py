from __future__ import annotations

from types import SimpleNamespace

import pytest

import executable_os_installer as os_installer


def test_ubuntu_installs_apt_packages_before_flatpak_bootstrap(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[list[str]] = []

    def fake_run(cmd: list[str], **_kwargs: object) -> SimpleNamespace:
        calls.append(cmd)
        if cmd[:2] == ["dpkg", "-s"]:
            return SimpleNamespace(returncode=1)
        if cmd[:2] == ["flatpak", "info"]:
            return SimpleNamespace(returncode=1)
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(os_installer.subprocess, "run", fake_run)

    os_installer.install_packages_ubuntu(
        [
            {"name": "apt-package"},
            {"name": "org.example.App", "manager": "flatpak"},
        ],
        hooks=None,
    )

    assert calls == [
        ["dpkg", "-s", "apt-package"],
        ["flatpak", "info", "org.example.App"],
        ["sudo", "apt", "install", "-y", "apt-package"],
        ["dpkg", "-s", "flatpak"],
        ["sudo", "apt", "install", "-y", "flatpak"],
        [
            "sudo",
            "flatpak",
            "remote-add",
            "--if-not-exists",
            "flathub",
            "https://dl.flathub.org/repo/flathub.flatpakrepo",
        ],
        ["sudo", "flatpak", "install", "-y", "flathub", "org.example.App"],
    ]


def test_ubuntu_adds_flathub_remote_when_flatpak_package_is_pending(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[list[str]] = []

    def fake_run(cmd: list[str], **_kwargs: object) -> SimpleNamespace:
        calls.append(cmd)
        if cmd[:2] == ["flatpak", "info"]:
            return SimpleNamespace(returncode=1)
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(os_installer.subprocess, "run", fake_run)

    os_installer.install_packages_ubuntu(
        [{"name": "org.example.App", "manager": "flatpak"}],
        hooks=None,
    )

    assert [
        "sudo",
        "flatpak",
        "remote-add",
        "--if-not-exists",
        "flathub",
        "https://dl.flathub.org/repo/flathub.flatpakrepo",
    ] in calls
    assert ["sudo", "flatpak", "install", "-y", "flathub", "org.example.App"] in calls


def test_ubuntu_skips_hooks_and_bootstrap_when_flatpak_package_is_installed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[list[str]] = []
    hooks_run: list[str] = []

    def fake_run(cmd: list[str], **_kwargs: object) -> SimpleNamespace:
        calls.append(cmd)
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(os_installer.subprocess, "run", fake_run)
    monkeypatch.setattr(os_installer, "run_hook", hooks_run.append)

    os_installer.install_packages_ubuntu(
        [{"name": "org.example.App", "manager": "flatpak"}],
        hooks={"before": "before-hook", "after": "after-hook"},
    )

    assert calls == [["flatpak", "info", "org.example.App"]]
    assert hooks_run == []


def test_ubuntu_rejects_unknown_package_manager(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[list[str]] = []

    def fake_run(cmd: list[str], **_kwargs: object) -> SimpleNamespace:
        calls.append(cmd)
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(os_installer.subprocess, "run", fake_run)

    with pytest.raises(ValueError, match="Unsupported Ubuntu package manager"):
        os_installer.install_packages_ubuntu(
            [{"name": "org.example.App", "manager": "flatpack"}],
            hooks=None,
        )

    assert calls == []
