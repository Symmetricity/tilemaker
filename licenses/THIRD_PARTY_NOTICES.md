# Third-party notices

This distribution includes tilemaker plus third-party code and assets used by
tilemaker, tilemaker-server, and the packaged example resources.

The tilemaker project license is in `LICENCE.txt`. Third-party notices are in
`licenses/third_party/`.

## Vendored code compiled into tilemaker

- kaguya: Boost Software License 1.0
  - `licenses/third_party/kaguya-LICENSE_1_0.txt`
- libdeflate: MIT
  - `licenses/third_party/libdeflate-COPYING.txt`
- libpopcnt: BSD 2-Clause
  - `licenses/third_party/libpopcnt-LICENSE.txt`
- minunit: MIT
  - `licenses/third_party/minunit-LICENSE.txt`
- PMTiles reference implementation: BSD 3-Clause
  - `licenses/third_party/pmtiles-LICENSE.txt`
- polylabel: ISC
  - `licenses/third_party/polylabel-LICENSE.txt`
- protozero: BSD 2-Clause, with Apache 2.0 notice for code derived from Folly
  - `licenses/third_party/protozero-LICENSE.md`
  - `licenses/third_party/protozero-LICENSE.from_folly.txt`
- sqlite_modern_cpp: MIT
  - `licenses/third_party/sqlite_modern_cpp-LICENSE.txt`
- streamvbyte: Apache 2.0
  - `licenses/third_party/streamvbyte-LICENSE.txt`
- visvalingam.cpp: MIT
  - `licenses/third_party/visvalingam-LICENSE.txt`
- vtzero: BSD 2-Clause
  - `licenses/third_party/vtzero-LICENSE.txt`

## Vendored code compiled into tilemaker-server

- Simple-Web-Server: MIT
  - `licenses/third_party/Simple-Web-Server-LICENSE.txt`

## Packaged example resources

- OpenMapTiles processing profile and OSM Bright-derived style resources:
  BSD 3-Clause and Creative Commons Attribution 4.0 notices
  - `licenses/third_party/osm-bright-gl-style-LICENSE.md`
  - `licenses/third_party/CC-BY-4.0.txt`
- KlokanTech Noto glyph resources and Noto font software: SIL Open Font
  License 1.1 and attribution notice
  - `licenses/third_party/klokantech-gl-fonts-README.md`
  - `licenses/third_party/noto-OFL-LICENSE.txt`

## Static package dependencies

Windows release packages are built with vcpkg and static dependency linking.
When vcpkg copyright files are available at package time, they are copied into
`licenses/vcpkg/` in the release package.
