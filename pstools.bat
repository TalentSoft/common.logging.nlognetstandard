@rem This file is owned by TalentSoft.BuildTools NuGet packages
@echo off
pushd %~dp0
@powershell -NoExit -ExecutionPolicy Bypass -C Import-Module .\ci.ps1; %*
popd