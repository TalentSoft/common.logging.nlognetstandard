# This file is owned by TalentSoft.BuildTools NuGet packages
# 
# It allow to expose your solution to standard continuous integration process.
# It is based on the following conventions :
# * You must have only one solution file in your repository.
# * The solution file must be at the root of the repository.
# * All assemblies must have the same version number.
# * That version number must be specified by:
#   - a .\Properties\{SolutionName}.AssemblyInfo.cs file that should be include as link in required msbuild2003 projects of the solution.
#   - or a .\Properties\{SolutionName}.props file that should be imported in required net sdk projects of the solution.
# * Msbuild2003 projects that output NuGet or Chocolatey packages must reference the TalentSoft.NuGetPackager package (>=3.0.0)
#   - For net sdk projects NuGet packaging is natively supported which means that TalentSoft.NuGetPackager is useless.
#     However producing chocolatey packages from a net sdk projects is not yet working well with that standard script.
# * Unit tests must be written with NUnit, in projects names *.nunit.csproj
#   * Nunit.ConsoleRunner and NUnit.Extension.NUnitV2ResultWriter packages must be installed at solution level to support execution of NUnit
#   * If some tests projects are still based on NUnit 2.x, NUnit.Extension.NUnitV2Driver must be installed at solution level to support them.
#     however you are encourged to upgrade the projects to a more recent version of NUnit instead of adding this package. 
#
# If your project can't follow those conventions you can modify this file.
# In that case change the first comment line of the file to avoid auto update
# of the file and indicate that you forked the original template.
# But, after each update of the package, you will have to check changes from
# packages\Talentsoft.BuildTools.*\SolutionContent\ci.ps1 and merge them
# manually with your script.
# Except for really particular cases and big solutions (Career, Recruitment,
# Hello Talent, etc.), fork of this file should be temporary, just the time
# to validate new behaviours and improve the package to support more scenarios
# by conventions. 
#
Param(
    [Parameter(Position = 0)]
    [ValidateSet("", "Build", "Test", "Publish")]
    [string]$target
)

# =============================================================================
# setup PowerShell environment
# =============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

cd $PSScriptRoot
[io.Directory]::SetCurrentDirectory($PSScriptRoot)

# =============================================================================
# setup global variables by conventions.
# =============================================================================
$Configuration = "Release"
$Solution = (Get-Item "*.sln")[-1].Name
$SolutionName = [IO.Path]::GetFileNameWithoutExtension(${Solution})

# =============================================================================
# restore and import modules
# only solution level packages are restored
# =============================================================================
nuget restore .\.nuget\packages.config -SolutionDirectory .\
if ($LastExitCode -ne 0) {
    throw "Error ($LastExitCode) during NuGet execution"
}

# =============================================================================
# import shared PowerShell command that should helps to write our targets.
# =============================================================================
$env:PSModulePath = ($env:PSModulePath + ";" + (Join-Path $PSScriptRoot Powershell) + ";" + ((Get-Item "packages/Talentsoft.BuildTools.*/Powershell")[-1].FullName))
Import-Module TsBuild

# =============================================================================
# write targets
# =============================================================================
Function Build() {
    # restore the remaining packages
    Restore-Nuget $Solution

    # run structural checks
    Invoke-ProjectValidator

    # run the build command
    Invoke-MsBuild $Solution ReBuild -parameters @{
        "Configuration" = $Configuration;
        "GeneratePackageOnBuild" = "true";
        "PackageOutputPath" = (Get-NuGetBuildDirectory);
        "ChocoOutputPath" = (Get-ChocolateyBuildDirectory);
        "IncludeSource" = "true"
    }

    # delete unnecessary packages to avoid to store too many things on the CI servers
    Remove-DuplicateNugetPackages -strategy KeepSymbols
}

function Test() {
    # run unit tests
    $visualStudioVersion = Get-VisualStudioVersion $Solution
    $assemblies = Get-ChildItem -Recurse -Path . -Filter "*.nunit.csproj" | ForEach { Select-AssemblyFromCsProj $_ -configuration $Configuration } | Where { Test-Path $_ }
    if ($null -ne $assemblies) {
        # test if CodeCoverage.exe is installed
        # if not fall back on a run without code coverage
        if (Test-Path (Get-CodeCoverageExe -visualStudioVersion $visualStudioVersion)) {
            Invoke-NUnitWithCoverage $assemblies -visualStudioVersion $visualStudioVersion
        }
        else {
            Write-Warning "CodeCoverage.exe is not installed. Fall back on a run without code coverage."
            Invoke-NUnit $assemblies
        }
    }

    # do a blank publish execution to validate that the publication can succeed
    Get-SolutionVersion -solutionName $SolutionName | Out-Null
    $nugetPackages = Get-NugetPackages
    $chocolateyPackages = Get-NugetPackages -packagesPath (Get-ChocolateyBuildDirectory)
    if ($null -eq $nugetPackages -and $null -eq $chocolateyPackages) {
        throw "Error: no package found to publish"
    }
}

function Publish() {
    $publishedPackages = @()

    # start to read the version before trying any publication
    # If this fail because conventions are not respected
    # at least we won't publish anything.
    $version = Get-SolutionVersion -solutionName $SolutionName

    $nugetPackages = Get-NugetPackages
    if ($null -ne $nugetPackages) {
        Publish-NugetPackages $nugetPackages -sourceName Talentsoft
        $publishedPackages += $nugetPackages
    }

    $chocolateyPackages = Get-NugetPackages -packagesPath (Get-ChocolateyBuildDirectory)
    if ($null -ne $chocolateyPackages) {
        Publish-NugetPackages $chocolateyPackages -sourceName TalentsoftChoco
        $publishedPackages += $chocolateyPackages
    }

    if ($publishedPackages.Count -gt 0) {
        New-TagPropertiesFile $publishedPackages -version $version
    }
    else {
        throw "Error: no package found to publish"
    }
}

# =============================================================================
# Execute the requested target
# =============================================================================
if ($target -ne "") {
    & $target
}