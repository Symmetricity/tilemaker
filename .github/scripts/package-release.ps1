param(
	[Parameter(Mandatory=$true)]
	[string]$PackageName,

	[Parameter(Mandatory=$true)]
	[string]$Tilemaker,

	[Parameter(Mandatory=$true)]
	[string]$TilemakerServer,

	[Parameter(Mandatory=$true)]
	[string]$OutputDir
)

$ErrorActionPreference = "Stop"

$stageDir = Join-Path $OutputDir $PackageName
$binDir = Join-Path $stageDir "bin"

if (Test-Path -LiteralPath $stageDir) {
	Remove-Item -LiteralPath $stageDir -Recurse -Force
}
New-Item -ItemType Directory -Path $binDir | Out-Null

Copy-Item -LiteralPath $Tilemaker -Destination $binDir
Copy-Item -LiteralPath $TilemakerServer -Destination $binDir
Copy-Item -LiteralPath "resources" -Destination (Join-Path $stageDir "resources") -Recurse
New-Item -ItemType Directory -Path (Join-Path $stageDir "server") | Out-Null
Copy-Item -LiteralPath "server\static" -Destination (Join-Path $stageDir "server\static") -Recurse
Copy-Item -LiteralPath "docs" -Destination (Join-Path $stageDir "docs") -Recurse
Copy-Item -LiteralPath "licenses" -Destination (Join-Path $stageDir "licenses") -Recurse
Copy-Item -LiteralPath "README.md", "CHANGELOG.md", "LICENCE.txt", "VERSION" -Destination $stageDir

$vcpkgDir = if ($env:VCPKG_INSTALLED_DIR) { $env:VCPKG_INSTALLED_DIR } else { Join-Path (Get-Location) "vcpkg_installed" }
if (Test-Path -LiteralPath $vcpkgDir) {
	$vcpkgLicenseDir = Join-Path $stageDir "licenses\vcpkg"
	Get-ChildItem -LiteralPath $vcpkgDir -Recurse -File -Filter "copyright" |
		Where-Object { $_.FullName -match "[\\/]+share[\\/]+[^\\/]+[\\/]+copyright$" } |
		ForEach-Object {
			$portName = Split-Path -Leaf (Split-Path -Parent $_.FullName)
			$targetDir = Join-Path $vcpkgLicenseDir $portName
			New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
			Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $targetDir "copyright")
		}
}

$zipPath = Join-Path $OutputDir "$PackageName.zip"
if (Test-Path -LiteralPath $zipPath) {
	Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path $stageDir -DestinationPath $zipPath

$symbolFiles = @()
$tilemakerPdb = [System.IO.Path]::ChangeExtension($Tilemaker, ".pdb")
$serverPdb = [System.IO.Path]::ChangeExtension($TilemakerServer, ".pdb")
foreach ($file in @($tilemakerPdb, $serverPdb)) {
	if (Test-Path -LiteralPath $file) {
		$symbolFiles += $file
	}
}

if ($symbolFiles.Count -gt 0) {
	$symbolsDir = Join-Path $OutputDir "$PackageName-symbols"
	if (Test-Path -LiteralPath $symbolsDir) {
		Remove-Item -LiteralPath $symbolsDir -Recurse -Force
	}
	New-Item -ItemType Directory -Path $symbolsDir | Out-Null
	foreach ($file in $symbolFiles) {
		Copy-Item -LiteralPath $file -Destination $symbolsDir
	}

	$symbolsZip = Join-Path $OutputDir "$PackageName-symbols.zip"
	if (Test-Path -LiteralPath $symbolsZip) {
		Remove-Item -LiteralPath $symbolsZip -Force
	}
	Compress-Archive -Path $symbolsDir -DestinationPath $symbolsZip
}
