#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
	echo "usage: $0 <package-name> <tilemaker> <tilemaker-server> <output-dir>" >&2
	exit 2
fi

package_name="$1"
tilemaker="$2"
tilemaker_server="$3"
output_dir="$4"
stage_dir="${output_dir}/${package_name}"

is_glibc_runtime_library() {
	case "$(basename "$1")" in
		ld-linux*.so*|libBrokenLocale.so*|libanl.so*|libc.so*|libdl.so*|libm.so*|libmvec.so*|libnsl.so*|libnss_*.so*|libpthread.so*|libresolv.so*|librt.so*|libthread_db.so*|libutil.so*)
			return 0
			;;
	esac
	return 1
}

copy_linux_library() {
	local library="$1"
	local lib_dir="$2"
	local target
	target="${lib_dir}/$(basename "${library}")"

	if is_glibc_runtime_library "${library}"; then
		return
	fi
	if [ -e "${target}" ]; then
		return
	fi

	cp "${library}" "${target}"
	chmod 0755 "${target}"
}

bundle_linux_libraries() {
	if ! command -v ldd >/dev/null || ! command -v patchelf >/dev/null; then
		echo "ldd and patchelf are required to build portable Linux packages" >&2
		exit 1
	fi

	local lib_dir="${stage_dir}/lib"
	mkdir -p "${lib_dir}"

	local scan_queue="${stage_dir}/.library-scan-queue"
	local scanned="${stage_dir}/.library-scan-done"
	: > "${scan_queue}"
	: > "${scanned}"
	printf '%s\n' "${stage_dir}/bin/$(basename "${tilemaker}")" "${stage_dir}/bin/$(basename "${tilemaker_server}")" >> "${scan_queue}"

	while IFS= read -r scan_path; do
		if grep -Fxq "${scan_path}" "${scanned}"; then
			continue
		fi
		printf '%s\n' "${scan_path}" >> "${scanned}"

		while IFS= read -r library; do
			copy_linux_library "${library}" "${lib_dir}"
			if [ -e "${lib_dir}/$(basename "${library}")" ]; then
				printf '%s\n' "${lib_dir}/$(basename "${library}")" >> "${scan_queue}"
			fi
		done < <(ldd "${scan_path}" | awk '
			/=> \// { print $3; next }
			/^\t\// { print $1; next }
		')
	done < "${scan_queue}"

	find "${lib_dir}" -type f -exec patchelf --set-rpath "\$ORIGIN" {} +
	patchelf --set-rpath "\$ORIGIN/../lib" "${stage_dir}/bin/$(basename "${tilemaker}")"
	patchelf --set-rpath "\$ORIGIN/../lib" "${stage_dir}/bin/$(basename "${tilemaker_server}")"

	rm -f "${scan_queue}" "${scanned}"
}

is_macos_system_library() {
	case "$1" in
		/System/Library/*|/usr/lib/*)
			return 0
			;;
	esac
	return 1
}

copy_macos_library() {
	local library="$1"
	local lib_dir="$2"
	local target
	target="${lib_dir}/$(basename "${library}")"

	if is_macos_system_library "${library}"; then
		return
	fi
	if [ -e "${target}" ]; then
		return
	fi

	cp -L "${library}" "${target}"
	chmod 0755 "${target}"
}

rewrite_macos_dependencies() {
	local target="$1"
	local lib_dir="$2"
	local rpath="$3"

	while IFS= read -r library; do
		if is_macos_system_library "${library}"; then
			continue
		fi
		install_name_tool -change "${library}" "@rpath/$(basename "${library}")" "${target}"
	done < <(otool -L "${target}" | awk 'NR > 1 { print $1 }')

	install_name_tool -add_rpath "${rpath}" "${target}" 2>/dev/null || true
	if [ "${target}" != "${stage_dir}/bin/$(basename "${tilemaker}")" ] &&
		[ "${target}" != "${stage_dir}/bin/$(basename "${tilemaker_server}")" ]; then
		install_name_tool -id "@rpath/$(basename "${target}")" "${target}" 2>/dev/null || true
	fi
	if command -v codesign >/dev/null; then
		codesign --force --sign - "${target}" >/dev/null 2>&1 || true
	fi
}

bundle_macos_libraries() {
	if ! command -v otool >/dev/null || ! command -v install_name_tool >/dev/null; then
		echo "otool and install_name_tool are required to build portable macOS packages" >&2
		exit 1
	fi

	local lib_dir="${stage_dir}/lib"
	mkdir -p "${lib_dir}"

	local scan_queue="${stage_dir}/.library-scan-queue"
	local scanned="${stage_dir}/.library-scan-done"
	: > "${scan_queue}"
	: > "${scanned}"
	printf '%s\n' "${stage_dir}/bin/$(basename "${tilemaker}")" "${stage_dir}/bin/$(basename "${tilemaker_server}")" >> "${scan_queue}"

	while IFS= read -r scan_path; do
		if grep -Fxq "${scan_path}" "${scanned}"; then
			continue
		fi
		printf '%s\n' "${scan_path}" >> "${scanned}"

		while IFS= read -r library; do
			copy_macos_library "${library}" "${lib_dir}"
			if [ -e "${lib_dir}/$(basename "${library}")" ]; then
				printf '%s\n' "${lib_dir}/$(basename "${library}")" >> "${scan_queue}"
			fi
		done < <(otool -L "${scan_path}" | awk 'NR > 1 { print $1 }')
	done < "${scan_queue}"

	rewrite_macos_dependencies "${stage_dir}/bin/$(basename "${tilemaker}")" "${lib_dir}" "@executable_path/../lib"
	rewrite_macos_dependencies "${stage_dir}/bin/$(basename "${tilemaker_server}")" "${lib_dir}" "@executable_path/../lib"
	find "${lib_dir}" -type f -name '*.dylib' -print0 |
		while IFS= read -r -d '' library; do
			rewrite_macos_dependencies "${library}" "${lib_dir}" "@loader_path"
		done

	rm -f "${scan_queue}" "${scanned}"
}

rm -rf "${stage_dir}"
mkdir -p "${stage_dir}/bin"

cp "${tilemaker}" "${stage_dir}/bin/"
cp "${tilemaker_server}" "${stage_dir}/bin/"
cp -R resources "${stage_dir}/resources"
mkdir -p "${stage_dir}/server"
cp -R server/static "${stage_dir}/server/static"
cp -R docs "${stage_dir}/docs"
cp -R licenses "${stage_dir}/licenses"
cp README.md CHANGELOG.md LICENCE.txt VERSION "${stage_dir}/"

vcpkg_dir="${VCPKG_INSTALLED_DIR:-vcpkg_installed}"
if [ -d "${vcpkg_dir}" ]; then
	while IFS= read -r -d '' copyright_file; do
		port_name="$(basename "$(dirname "${copyright_file}")")"
		mkdir -p "${stage_dir}/licenses/vcpkg/${port_name}"
		cp "${copyright_file}" "${stage_dir}/licenses/vcpkg/${port_name}/copyright"
	done < <(find "${vcpkg_dir}" -path '*/share/*/copyright' -type f -print0)
fi

case "$(uname -s)" in
	Linux)
		bundle_linux_libraries
		;;
	Darwin)
		bundle_macos_libraries
		;;
esac

(
	cd "${output_dir}"
	rm -f "${package_name}.zip"
	zip -qr "${package_name}.zip" "${package_name}"
)
