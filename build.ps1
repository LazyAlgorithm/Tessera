# Run from an x64 Visual Studio developer shell. See docs/building-from-source.md.
$ErrorActionPreference = 'Stop'
& python (Join-Path $PSScriptRoot 'tools/build.py') @args
exit $LASTEXITCODE
