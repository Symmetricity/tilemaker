#!/usr/bin/env python3

import gzip
import hashlib
import json
import pathlib
import sqlite3
import struct
import subprocess
import sys
import zlib


COMPRESSION_NONE = 1
COMPRESSION_GZIP = 2


status = 0


def error(path, message):
    global status
    print(f"::error title={archive_label(path)}::{message}")
    status = 1


def archive_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def build_label(path):
    artifact = path.parent.name
    if artifact == "tile-outputs-github-action":
        return "GitHub Action"
    if not artifact.startswith("tile-outputs-"):
        return str(path.parent)

    label = artifact.removeprefix("tile-outputs-")
    if label.endswith("-cmake"):
        return f"{runner_label(label.removesuffix('-cmake'))} (CMake)"
    if label.endswith("-makefile"):
        return f"{runner_label(label.removesuffix('-makefile'))} (Makefile)"
    return artifact


def runner_label(label):
    if label == "windows":
        return "Windows"
    if label.startswith("ubuntu-"):
        return "Ubuntu " + label.removeprefix("ubuntu-")
    if label.startswith("macos-"):
        return "macOS " + label.removeprefix("macos-")
    return label.replace("-", " ")


def archive_label(path):
    return f"{build_label(path)} {path.name}"


def decompress_payload(data):
    for wbits in (16 + zlib.MAX_WBITS, zlib.MAX_WBITS):
        try:
            return zlib.decompress(data, wbits)
        except zlib.error:
            pass
    return data


def decompress_pmtiles(data, compression):
    if compression == COMPRESSION_NONE:
        return data
    if compression == COMPRESSION_GZIP:
        return gzip.decompress(data)
    raise RuntimeError(f"unsupported PMTiles compression {compression}")


def tileid_to_zxy(tileid):
    acc = 0
    for z in range(32):
        num_tiles = (1 << z) * (1 << z)
        if acc + num_tiles > tileid:
            return t_on_level(z, tileid - acc)
        acc += num_tiles
    raise RuntimeError("tile zoom exceeds 64-bit limit")


def t_on_level(z, pos):
    n = 1 << z
    t = pos
    x = 0
    y = 0
    s = 1
    while s < n:
        rx = 1 & (t // 2)
        ry = 1 & (t ^ rx)
        if ry == 0:
            if rx == 1:
                x = s - 1 - x
                y = s - 1 - y
            x, y = y, x
        x += s * rx
        y += s * ry
        t //= 4
        s *= 2
    return z, x, y


def decode_varint(data, pos):
    value = 0
    shift = 0
    for _ in range(10):
        if pos >= len(data):
            raise RuntimeError("end of buffer while reading varint")
        byte = data[pos]
        pos += 1
        value |= (byte & 0x7f) << shift
        if byte < 0x80:
            return value, pos
        shift += 7
    raise RuntimeError("varint too long")


def deserialize_directory(data):
    pos = 0
    count, pos = decode_varint(data, pos)
    entries = [{"tile_id": 0, "run_length": 0, "length": 0, "offset": 0} for _ in range(count)]
    last_id = 0
    for entry in entries:
        value, pos = decode_varint(data, pos)
        entry["tile_id"] = last_id + value
        last_id = entry["tile_id"]
    for entry in entries:
        entry["run_length"], pos = decode_varint(data, pos)
    for entry in entries:
        entry["length"], pos = decode_varint(data, pos)
    for index, entry in enumerate(entries):
        value, pos = decode_varint(data, pos)
        if index > 0 and value == 0:
            prev = entries[index - 1]
            entry["offset"] = prev["offset"] + prev["length"]
        else:
            entry["offset"] = value - 1
    if pos != len(data):
        raise RuntimeError("trailing bytes in PMTiles directory")
    return entries


def mbtiles_fingerprint(path):
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    cur = con.cursor()
    tables = {row[0] for row in cur.execute("select name from sqlite_master where type = 'table'")}
    missing = {"metadata", "tiles"} - tables
    if missing:
        raise RuntimeError("missing tables: " + ", ".join(sorted(missing)))
    tile_count = cur.execute("select count(*) from tiles").fetchone()[0]
    if tile_count == 0:
        raise RuntimeError("tiles table is empty")
    empty_tiles = cur.execute("select count(*) from tiles where tile_data is null or length(tile_data) = 0").fetchone()[0]
    if empty_tiles:
        raise RuntimeError(f"{empty_tiles} empty tile blobs")
    minzoom, maxzoom = cur.execute("select min(zoom_level), max(zoom_level) from tiles").fetchone()
    metadata_rows = list(cur.execute("select name, value from metadata order by name, value"))
    if not metadata_rows:
        raise RuntimeError("metadata table is empty")

    digest = hashlib.sha256()
    for name, value in metadata_rows:
        digest.update(f"M\t{name}\t{canonical_metadata_value(value)}\n".encode("utf-8", "surrogateescape"))
    for z, x, y, tile_data in cur.execute("select zoom_level, tile_column, tile_row, tile_data from tiles order by zoom_level, tile_column, tile_row"):
        payload = decompress_payload(bytes(tile_data))
        digest.update(f"T\t{z}\t{x}\t{y}\t{len(payload)}\t".encode())
        digest.update(hashlib.sha256(payload).hexdigest().encode())
        digest.update(b"\n")
    con.close()

    fingerprint = digest.hexdigest()
    print(f"{archive_label(path)}: {tile_count} tiles, zoom {minzoom}-{maxzoom}, {len(metadata_rows)} metadata rows, content {fingerprint}")
    return fingerprint


def canonical_metadata_value(value):
    if value is None:
        return ""
    try:
        return json.dumps(json.loads(value), sort_keys=True, separators=(",", ":"))
    except (TypeError, json.JSONDecodeError):
        return str(value)


def verify_pmtiles(path):
    print(f"{archive_label(path)}: verifying PMTiles archive")
    result = subprocess.run(
        ["pmtiles", "verify", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    if result.returncode != 0:
        raise RuntimeError("pmtiles verify failed")


def pmtiles_header(data):
    if len(data) < 127:
        raise RuntimeError("PMTiles header is truncated")
    if data[:7] != b"PMTiles" or data[7] != 3:
        raise RuntimeError("not a PMTiles v3 archive")
    values = struct.unpack_from("<QQQQQQQQQQQBBBBBBiiiiBii", data, 8)
    return {
        "root_dir_offset": values[0],
        "root_dir_bytes": values[1],
        "json_metadata_offset": values[2],
        "json_metadata_bytes": values[3],
        "leaf_dirs_offset": values[4],
        "leaf_dirs_bytes": values[5],
        "tile_data_offset": values[6],
        "tile_data_bytes": values[7],
        "addressed_tiles_count": values[8],
        "tile_entries_count": values[9],
        "tile_contents_count": values[10],
        "internal_compression": values[12],
        "tile_compression": values[13],
    }


def collect_pmtiles_entries(data, header, offset, length, result):
    directory = decompress_pmtiles(data[offset:offset + length], header["internal_compression"])
    for entry in deserialize_directory(directory):
        if entry["run_length"] == 0:
            collect_pmtiles_entries(data, header, header["leaf_dirs_offset"] + entry["offset"], entry["length"], result)
        else:
            for tileid in range(entry["tile_id"], entry["tile_id"] + entry["run_length"]):
                z, x, y = tileid_to_zxy(tileid)
                result.append((z, x, y, header["tile_data_offset"] + entry["offset"], entry["length"]))


def pmtiles_fingerprint(path):
    verify_pmtiles(path)
    data = path.read_bytes()
    header = pmtiles_header(data)
    metadata = decompress_pmtiles(
        data[header["json_metadata_offset"]:header["json_metadata_offset"] + header["json_metadata_bytes"]],
        header["internal_compression"],
    )
    try:
        metadata = json.dumps(json.loads(metadata), sort_keys=True, separators=(",", ":")).encode()
    except json.JSONDecodeError:
        pass

    entries = []
    collect_pmtiles_entries(data, header, header["root_dir_offset"], header["root_dir_bytes"], entries)
    digest = hashlib.sha256()
    digest.update(b"M\t")
    digest.update(hashlib.sha256(metadata).hexdigest().encode())
    digest.update(b"\n")
    for z, x, y, offset, length in sorted(entries):
        payload = decompress_pmtiles(data[offset:offset + length], header["tile_compression"])
        digest.update(f"T\t{z}\t{x}\t{y}\t{len(payload)}\t".encode())
        digest.update(hashlib.sha256(payload).hexdigest().encode())
        digest.update(b"\n")

    fingerprint = digest.hexdigest()
    print(f"{archive_label(path)}: {len(entries)} addressed tiles, content {fingerprint}")
    return fingerprint


def fingerprint_archives(paths, fingerprint, failure_message):
    cache = {}
    fingerprints = {}
    archive_hashes = {}

    for path in paths:
        archive_hashes[path] = archive_sha256(path)
        print(f"{archive_hashes[path]}  {archive_label(path)}")

    for path in paths:
        archive_hash = archive_hashes[path]
        if archive_hash not in cache:
            try:
                cache[archive_hash] = (path, fingerprint(path), None)
            except Exception as err:
                cache[archive_hash] = (path, None, str(err))

        source_path, content_hash, failure = cache[archive_hash]
        if failure is not None:
            error(path, f"{failure_message}: {failure}")
            continue

        fingerprints[path] = content_hash
        if source_path != path:
            print(f"{archive_label(path)}: same archive as {archive_label(source_path)}; content {content_hash}")

    return fingerprints


def check_repeat(fingerprints, suffix):
    for path, fingerprint in sorted(fingerprints.items()):
        if path.name.endswith(f"-repeat.{suffix}"):
            continue
        repeat = path.with_name(f"{path.stem}-repeat.{suffix}")
        if repeat not in fingerprints:
            error(path, f"missing repeat output {archive_label(repeat)}")
        elif fingerprints[repeat] != fingerprint:
            error(path, f"content differs from repeat output {archive_label(repeat)}")


def check_cross_runner(fingerprints, suffix):
    groups = {}
    for path, fingerprint in fingerprints.items():
        if path.name.endswith(f"-repeat.{suffix}"):
            continue
        groups.setdefault(path.name, []).append((path, fingerprint))
    for name, values in sorted(groups.items()):
        reference_path, reference = values[0]
        for path, fingerprint in values[1:]:
            if fingerprint != reference:
                error(path, f"content differs from {archive_label(reference_path)}")


def main():
    root = pathlib.Path(sys.argv[1])
    mbtiles_paths = sorted(root.glob("**/*.mbtiles"))
    pmtiles_paths = sorted(root.glob("**/*.pmtiles"))

    print("Archive SHA-256")
    mbtiles = fingerprint_archives(
        mbtiles_paths,
        mbtiles_fingerprint,
        "MBTiles archive failed verification",
    )

    pmtiles = fingerprint_archives(
        pmtiles_paths,
        pmtiles_fingerprint,
        "PMTiles archive failed verification",
    )

    check_repeat(mbtiles, "mbtiles")
    check_repeat(pmtiles, "pmtiles")
    check_cross_runner(mbtiles, "mbtiles")
    check_cross_runner(pmtiles, "pmtiles")
    return status


if __name__ == "__main__":
    sys.exit(main())
