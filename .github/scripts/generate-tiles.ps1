param(
	[Parameter(Mandatory = $true)]
	[string] $Tilemaker,

	[Parameter(Mandatory = $true)]
	[string] $Area,

	[Parameter(Mandatory = $true)]
	[string] $OutputSuffix,

	[Parameter(Mandatory = $true)]
	[string] $StoreRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Tilemaker {
	param(
		[Parameter(Mandatory = $true)]
		[string] $Output,

		[Parameter(Mandatory = $true)]
		[string[]] $Arguments
	)

	Write-Host "::group::Build $Output"
	& $Tilemaker @Arguments
	$status = $LASTEXITCODE
	Write-Host "::endgroup::"
	if ($status -ne 0) {
		Write-Error "tilemaker failed while writing $Output with exit code $status"
		exit $status
	}
	if (!(Test-Path -LiteralPath $Output) -or (Get-Item -LiteralPath $Output).Length -eq 0) {
		Write-Error "tilemaker did not create $Output"
		exit 1
	}
}

$inputPbf = "${Area}.osm.pbf"
$common = @(
	$inputPbf,
	"--config=resources/config-openmaptiles.json",
	"--process=resources/process-openmaptiles.lua"
)

Invoke-Tilemaker "${Area}${OutputSuffix}.pmtiles" `
	($common + @("--output=${Area}${OutputSuffix}.pmtiles", "--verbose"))

Invoke-Tilemaker "${Area}${OutputSuffix}-repeat.pmtiles" `
	($common + @("--output=${Area}${OutputSuffix}-repeat.pmtiles", "--verbose"))

Invoke-Tilemaker "${Area}${OutputSuffix}.mbtiles" `
	($common + @(
		"--output=${Area}${OutputSuffix}.mbtiles",
		"--store",
		(Join-Path $StoreRoot "store${OutputSuffix}"),
		"--verbose"
	))

Invoke-Tilemaker "${Area}${OutputSuffix}-repeat.mbtiles" `
	($common + @(
		"--output=${Area}${OutputSuffix}-repeat.mbtiles",
		"--store",
		(Join-Path $StoreRoot "store${OutputSuffix}-repeat"),
		"--verbose"
	))
