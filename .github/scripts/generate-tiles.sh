#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
	echo "usage: $0 <tilemaker> <area> <output-suffix> <store-root>" >&2
	exit 2
fi

tilemaker="$1"
area="$2"
suffix="$3"
store_root="$4"

run_tilemaker() {
	output="$1"
	shift
	echo "::group::Build ${output}"
	if "$@"; then
		echo "::endgroup::"
	else
		status="$?"
		echo "::endgroup::"
		echo "::error title=Tile generation failed::tilemaker failed while writing ${output} with exit code ${status}"
		exit "${status}"
	fi
	if [ ! -s "${output}" ]; then
		echo "::error title=Tile output missing::tilemaker did not create ${output}"
		exit 1
	fi
}

common=(
	"${area}.osm.pbf"
	--config=resources/config-openmaptiles.json
	--process=resources/process-openmaptiles.lua
)

run_tilemaker "${area}${suffix}.pmtiles" \
	"${tilemaker}" "${common[@]}" \
	--output="${area}${suffix}.pmtiles" --verbose

run_tilemaker "${area}${suffix}-repeat.pmtiles" \
	"${tilemaker}" "${common[@]}" \
	--output="${area}${suffix}-repeat.pmtiles" --verbose

run_tilemaker "${area}${suffix}.mbtiles" \
	"${tilemaker}" "${common[@]}" \
	--output="${area}${suffix}.mbtiles" \
	--verbose --store "${store_root}/store${suffix}"

run_tilemaker "${area}${suffix}-repeat.mbtiles" \
	"${tilemaker}" "${common[@]}" \
	--output="${area}${suffix}-repeat.mbtiles" \
	--verbose --store "${store_root}/store${suffix}-repeat"
