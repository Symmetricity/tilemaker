#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
	echo "usage: $0 <version> <tilemaker> <tilemaker-server> <output-dir>" >&2
	exit 2
fi

version="$1"
tilemaker="$2"
tilemaker_server="$3"
output_dir="$4"

ubuntu_release="${TILEMAKER_DEB_RELEASE:-}"
if [ -z "${ubuntu_release}" ]; then
	os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')"
	os_version_id="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')"
	if [ "${os_id}" != "ubuntu" ] || [ -z "${os_version_id}" ]; then
		echo "could not determine Ubuntu release from /etc/os-release" >&2
		exit 1
	fi
	ubuntu_release="ubuntu${os_version_id}"
fi
case "${ubuntu_release}" in
	ubuntu[0-9]*.[0-9]*) ;;
	*)
		echo "Ubuntu release label must look like ubuntu22.04, got ${ubuntu_release}" >&2
		exit 1
		;;
esac

package_version="${version}-0${ubuntu_release}"
arch="$(dpkg --print-architecture)"
work_dir="${output_dir}/tilemaker-deb"
package_dir="${work_dir}/debian/tilemaker"
deb_path="${output_dir}/tilemaker_${package_version}_${arch}.deb"

rm -rf "${work_dir}"
mkdir -p "${package_dir}/DEBIAN"
mkdir -p "${package_dir}/usr/bin"
mkdir -p "${package_dir}/usr/share/tilemaker"
mkdir -p "${package_dir}/usr/share/doc/tilemaker"
mkdir -p "${package_dir}/usr/share/man/man1"

install -m 0755 "${tilemaker}" "${package_dir}/usr/bin/tilemaker"
install -m 0755 "${tilemaker_server}" "${package_dir}/usr/bin/tilemaker-server"
cp -R resources "${package_dir}/usr/share/tilemaker/resources"
mkdir -p "${package_dir}/usr/share/tilemaker/server"
cp -R server/static "${package_dir}/usr/share/tilemaker/server/static"

cp README.md CHANGELOG.md LICENCE.txt VERSION "${package_dir}/usr/share/doc/tilemaker/"
cp -R docs "${package_dir}/usr/share/doc/tilemaker/docs"
cp -R licenses "${package_dir}/usr/share/doc/tilemaker/licenses"
cp LICENCE.txt "${package_dir}/usr/share/doc/tilemaker/copyright"
gzip -n -9 -c CHANGELOG.md > "${package_dir}/usr/share/doc/tilemaker/changelog.gz"
gzip -n -9 -c docs/man/tilemaker.1 > "${package_dir}/usr/share/man/man1/tilemaker.1.gz"

cat > "${work_dir}/debian/control" <<'EOF'
Source: tilemaker
Section: utils
Priority: optional
Maintainer: tilemaker contributors <tilemaker@example.invalid>
Standards-Version: 4.6.2
Homepage: https://tilemaker.org
Package: tilemaker
Architecture: any
Depends: ${shlibs:Depends}, ${misc:Depends}
Description: Convert OpenStreetMap PBF files into vector tiles
 tilemaker creates vector tiles from OpenStreetMap PBF input without
 requiring a database.
EOF

depends="$(
	cd "${work_dir}"
	dpkg-shlibdeps -O -Tsubstvars \
		debian/tilemaker/usr/bin/tilemaker \
		debian/tilemaker/usr/bin/tilemaker-server |
		sed -n 's/^shlibs:Depends=//p'
)"
if [ -z "${depends}" ]; then
	echo "could not determine package dependencies" >&2
	exit 1
fi

installed_size="$(du -sk "${package_dir}" | cut -f1)"
cat > "${package_dir}/DEBIAN/control" <<EOF
Package: tilemaker
Version: ${package_version}
Section: utils
Priority: optional
Architecture: ${arch}
Maintainer: tilemaker contributors <tilemaker@example.invalid>
Depends: ${depends}
Installed-Size: ${installed_size}
Homepage: https://tilemaker.org
Description: Convert OpenStreetMap PBF files into vector tiles
 tilemaker creates vector tiles from OpenStreetMap PBF input without
 requiring a database.
EOF

find "${package_dir}" -type d -exec chmod 0755 {} +
find "${package_dir}/usr/share" -type f -exec chmod 0644 {} +
chmod 0644 "${package_dir}/DEBIAN/control"
chmod 0755 "${package_dir}/usr/bin/tilemaker" "${package_dir}/usr/bin/tilemaker-server"

rm -f "${deb_path}"
dpkg-deb --build --root-owner-group "${package_dir}" "${deb_path}"
