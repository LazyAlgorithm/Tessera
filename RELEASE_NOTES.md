# Tessera v0.1.0-beta.1

Early beta of the Tessera engine, project launcher, and editor for Linux x64 and Windows x64.

- Portable folders with a launcher at the top level, engine assets, project templates, shader compiler, and the source/native libraries required to compile game scripts.
- Cross-platform Python packaging, also available through the editor's Build window.
- Windows process hardening preserves the original process access list and restores it during shutdown. Ringfall/Steam compatibility still needs testing with hardening enabled.

Start `Tessera` on Linux or `Tessera.exe` on Windows. BeefBuild and Python 3.11+ are required to edit/build projects. Windows also needs Microsoft C++ Build Tools. Graphics drivers and normal operating-system libraries are prerequisites.

Since v0.1.0-beta.1: scripts reload while the editor runs on Windows as they do on Linux (tested under Wine; not yet on a Windows machine).

Known limitations: macOS and browser exports are not supported. This is an early beta; back up projects before use.

Validation: Linux package creates a project and that project compiles using the packaged engine/editor and native archives. Windows packages require a native Windows launch/create/build smoke test before release validation can be claimed.
