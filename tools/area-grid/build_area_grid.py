#!/usr/bin/env python3
"""Pati Harita: riskli alan ızgarasını (shared/area-tr.bin) üretir ya da var olan bir ızgarayı denetler.

Kaynaklar yalnızca OpenStreetMap Türkiye özü ve özün sınırı (Geofabrik) ile Natural Earth 10 m'dir. Kurallar,
lisanslar, kaynak boyutları ve yeniden üretim politikası: tools/area-grid/README.md.

Üretim (indirme yalnızca --download verilirse yapılır):
    python tools/area-grid/build_area_grid.py --version 20261001 --download \\
        --cache "%LOCALAPPDATA%\\PatiHarita\\area-grid-cache"
Var olan dosyayı denetleme (yalnızca Python yeter, numpy gerekmez):
    python tools/area-grid/build_area_grid.py --verify-bin shared/area-tr.bin
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import importlib.metadata
import json
import math
import os
import struct
import sys
import time
import urllib.parse
import urllib.request
import zipfile
import zlib
from array import array
from dataclasses import dataclass
from pathlib import Path

try:
    import numpy as np
except ImportError:  # --verify-bin numpy olmadan da çalışır
    np = None


# ---------------------------------------------------------------------------
# Dosya biçimi. AnimalKit'teki AreaGrid(data:) ile birebir aynı olmalı.

MAGIC = b"PHAG"
FORMAT_VERSION = 1
CELLS_PER_DEGREE = 240  # 15″: Türkiye'de ~464 m K–G × 345–375 m D–B
ROWS = 1560  # enlem 35.75 … 42.25
COLS = 4680  # boylam 25.50 … 45.00
SOUTH_MICRODEG = 35_750_000
WEST_MICRODEG = 25_500_000
SOUTH = SOUTH_MICRODEG / 1_000_000
WEST = WEST_MICRODEG / 1_000_000
# Güney ve batı kenarı hücre cinsinden (8580.0 ve 6120.0, tam). AreaGrid.areaClass gibi önce çarpılıp sonra
# çıkarılır; (enlem − güney) × 240 hücre kenarlarında başka satır seçebilir, kapı uygulamayla aynı hücreye bakmalı.
SOUTH_CELL = SOUTH_MICRODEG * CELLS_PER_DEGREE / 1_000_000
WEST_CELL = WEST_MICRODEG * CELLS_PER_DEGREE / 1_000_000
NORTH = SOUTH + ROWS / CELLS_PER_DEGREE
EAST = WEST + COLS / CELLS_PER_DEGREE
HEADER = struct.Struct("<4sBBHHHiiI")
PAYLOAD_SIZE = ROWS * COLS // 4
FILE_SIZE = HEADER.size + PAYLOAD_SIZE
assert HEADER.size == 24 and FILE_SIZE == 1_825_224

REMOTE, ALLOWED, WATER, FOREST = 0, 1, 2, 3
CLASS_NAMES = ("remote", "allowed", "water", "forest")
CLASS_LABELS = ("yerleşim dışı", "izinli", "su", "orman")
CLASS_SYMBOLS = (".", "#", "~", "^")

# 3″ alt ızgara: her 15″ hücre tam 5×5 alt hücredir.
SUB = 5
FINE_CPD = CELLS_PER_DEGREE * SUB
FINE_ROWS = ROWS * SUB
FINE_COLS = COLS * SUB

# ---------------------------------------------------------------------------
# Kurallar (README "Kurallar" bölümü).

SETTLED_LANDUSE = frozenset({"residential", "construction", "industrial", "commercial", "retail", "cemetery"})
# place=locality çoğu kez ıssız bir yer adıdır, alınmaz; farm tek bir çiftlik evidir.
SETTLED_PLACES = frozenset({
    "city", "town", "village", "hamlet", "isolated_dwelling", "farm", "suburb", "neighbourhood", "quarter",
})
MIN_BUILDINGS = 3
# Ormanla kaplı hücrede birkaç dağınık bina (piknik alanı, orman tesisi) yerleşim sayılmaz; köy/mahalle düğümü ya da
# yerleşim kullanımı yine yeter.
MIN_BUILDINGS_IN_FOREST = 10
MIN_LANDUSE_SUBCELLS = 2
MIN_FOREST_SUBCELLS = 13  # 25 alt hücrenin en az yarısı
MAX_SETTLED_NEIGHBOURS_FOR_FOREST = 0  # yerleşime değen orman hücresi (vadi köyleri, korular) açık kalır
FRINGE_ITERATIONS = 1  # yerleşimin çevresinde ~0,35–0,45 km; daha genişi köyler arası yolları açıyordu
WATER_EROSION_ITERATIONS = 2  # su, kıyıdan en az ~0,7 km içeride başlar
MAX_BAD_AREA_SHARE = 0.05

TOUCH_STEP = 0.1  # all_touched için kenar örnekleme adımı (hücre)
BAND_ROWS = 600  # 3″ ızgara bellekte bütün durmaz; bantlar hâlinde doldurulur
BATCH_VERTICES = 2_000_000

# ---------------------------------------------------------------------------
# Kaynaklar.

DEFAULT_PBF = "https://download.geofabrik.de/europe/turkey-latest.osm.pbf"
# Geofabrik özü bu sınırla keser; dışında OSM verisi yoktur.
DEFAULT_POLY = "https://download.geofabrik.de/europe/turkey.poly"
DEFAULT_NE = "https://naciscdn.org/naturalearth/10m/physical"
NE_LAND, NE_MINOR_ISLANDS, NE_LAKES = "ne_10m_land", "ne_10m_minor_islands", "ne_10m_lakes"
NE_LAYERS = (NE_LAND, NE_MINOR_ISLANDS, NE_LAKES)
USER_AGENT = "PatiHarita-area-grid/1"

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "shared" / "area-tr.bin"
DEFAULT_GOLDEN = REPO_ROOT / "shared" / "area-golden.json"
IN_REPO_CACHE = REPO_ROOT / "tools" / "area-grid" / "cache"


# ---------------------------------------------------------------------------
# Izgara dosyası (saf Python: denetim numpy'sız da çalışsın).

@dataclass(frozen=True)
class Grid:
    data_version: int
    payload: bytes

    def value(self, row: int, col: int) -> int:
        i = row * COLS + col
        return (self.payload[i >> 2] >> ((i & 3) * 2)) & 3

    def class_at(self, lat: float, lon: float) -> int | None:
        cell = cell_index(lat, lon)
        return None if cell is None else self.value(*cell)


def cell_index(lat: float, lon: float) -> tuple[int, int] | None:
    """AreaGrid.areaClass ile aynı: güney ve batı kenarı dahil, kuzey ve doğu hariç; NaN ve sonsuz dışarıda."""
    y = lat * CELLS_PER_DEGREE - SOUTH_CELL
    x = lon * CELLS_PER_DEGREE - WEST_CELL
    if not (0 <= y < ROWS and 0 <= x < COLS):
        return None
    return math.floor(y), math.floor(x)


def format_data_version(value: int | str) -> str:
    """20261001 → "2026-10-01" (uygulamanın gösterdiği biçim)."""
    text = str(value)
    try:
        if len(text) != 8 or not text.isdigit():
            raise ValueError
        return dt.datetime.strptime(text, "%Y%m%d").strftime("%Y-%m-%d")
    except ValueError:
        raise ValueError(f"veri sürümü geçerli bir YYYYMMDD tarihi değil: {text}") from None


def pack_header(data_version: int) -> bytes:
    return HEADER.pack(MAGIC, FORMAT_VERSION, CELLS_PER_DEGREE, ROWS, COLS, 0,
                       SOUTH_MICRODEG, WEST_MICRODEG, data_version)


def parse_grid(data: bytes) -> Grid:
    """AreaGrid(data:) ile aynı denetimler; bu script tek bir ızgara ürettiği için bütün alanlar sabittir."""
    if len(data) != FILE_SIZE:
        raise ValueError(f"boyut {len(data)} bayt, {FILE_SIZE} olmalı")
    magic, fmt, cpd, rows, cols, reserved, south, west, version = HEADER.unpack_from(data, 0)
    fields = {
        "magic": (magic, MAGIC),
        "formatVersion": (fmt, FORMAT_VERSION),
        "cellsPerDegree": (cpd, CELLS_PER_DEGREE),
        "rows": (rows, ROWS),
        "cols": (cols, COLS),
        "reserved": (reserved, 0),
        "south": (south, SOUTH_MICRODEG),
        "west": (west, WEST_MICRODEG),
    }
    for name, (got, want) in fields.items():
        if got != want:
            raise ValueError(f"başlıkta {name} = {got!r}, {want!r} olmalı")
    format_data_version(version)
    return Grid(version, bytes(data[HEADER.size:]))


def class_counts(payload: bytes) -> list[int]:
    counts = [0, 0, 0, 0]
    for byte, n in collections.Counter(payload).items():
        for k in range(4):
            counts[(byte >> (2 * k)) & 3] += n
    return counts


def print_shares(counts: list[int]) -> None:
    total = sum(counts)
    land = total - counts[WATER]
    print("Sınıf payları (bütün kutu · su dışında kalanlar):")
    for k in range(4):
        line = f"  {CLASS_NAMES[k]:8} {CLASS_LABELS[k]:14} {counts[k]:>10,} hücre  %{100 * counts[k] / total:6.2f}"
        if k != WATER and land:
            line += f"  · %{100 * counts[k] / land:6.2f}"
        print(line)


# ---------------------------------------------------------------------------
# Altın noktalar.

@dataclass(frozen=True)
class GoldenPoint:
    name: str
    lat: float
    lon: float
    expected: tuple[str, ...]


def load_golden(path: Path) -> list[GoldenPoint]:
    """shared/area-golden.json: [{name, lat, lon, expect: [sınıf, …]}] (AreaGridGoldenTests de böyle okur)."""
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise SystemExit(f"{path} okunamadı: {error}")
    items = raw.get("points") if isinstance(raw, dict) else raw
    if not isinstance(items, list) or not items:
        raise SystemExit(f"{path}: nokta listesi yok ya da boş")
    points = []
    for n, item in enumerate(items):
        where = f"{path.name} #{n}"
        if not isinstance(item, dict):
            raise SystemExit(f"{where}: nesne olmalı")
        name = str(item.get("name") or where)
        lat = item.get("lat")
        lon = item.get("lon")
        expected = item.get("expect")
        for value in (lat, lon):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                raise SystemExit(f"{where} ({name}): lat ve lon sayı olmalı")
        if not isinstance(expected, list) or not expected or any(e not in CLASS_NAMES for e in expected):
            raise SystemExit(f"{where} ({name}): expect, {', '.join(CLASS_NAMES)} içinden en az bir sınıf olmalı")
        points.append(GoldenPoint(name, float(lat), float(lon), tuple(expected)))
    return points


def check_golden(grid: Grid, points: list[GoldenPoint]) -> list[tuple[GoldenPoint, str]]:
    failures = []
    for p in points:
        value = grid.class_at(p.lat, p.lon)
        got = "unknown" if value is None else CLASS_NAMES[value]
        if got not in p.expected:
            failures.append((p, got))
    return failures


def neighbourhood(grid: Grid, row: int, col: int, radius: int = 3) -> list[str]:
    lines = []
    for r in range(row + radius, row - radius - 1, -1):  # kuzey üstte
        cells = []
        for c in range(col - radius, col + radius + 1):
            symbol = CLASS_SYMBOLS[grid.value(r, c)] if 0 <= r < ROWS and 0 <= c < COLS else " "
            cells.append(f"[{symbol}]" if (r, c) == (row, col) else f" {symbol} ")
        lines.append("".join(cells))
    return lines


def print_golden_failures(grid: Grid, failures, describe=None) -> None:
    print(f"\nALTIN NOKTA KAPISI GEÇMEDİ: {len(failures)} nokta beklenen sınıfta değil.")
    print("Komşuluk kuzey üstte, [ ] noktanın hücresi:  # izinli  ^ orman  ~ su  . yerleşim dışı")
    for p, got in failures:
        print(f"\n- {p.name} ({p.lat:.5f}, {p.lon:.5f}): {got}; beklenen {' ya da '.join(p.expected)}")
        cell = cell_index(p.lat, p.lon)
        if cell is None:
            continue
        for line in neighbourhood(grid, *cell):
            print("    " + line)
        if describe is not None:
            print("    " + describe(*cell))
    print("\nNoktayı haritada (openstreetmap.org) kontrol edin: koordinat mı yanlış, veri mi eksik?")


# ---------------------------------------------------------------------------
# Önbellek, indirme ve özetler.

def human_size(n: float) -> str:
    for unit in ("B", "KB", "MB"):
        if n < 1024:
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.2f} GB"


def file_digest(path: Path, algorithm: str = "sha256") -> str:
    h = hashlib.new(algorithm)
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def default_cache_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA")
    if base:
        return Path(base) / "PatiHarita" / "area-grid-cache"
    return Path.home() / ".cache" / "pati-harita" / "area-grid"


def prepare_cache(requested: Path | None) -> Path:
    cache = (requested or default_cache_dir()).expanduser().resolve()
    # OneDrive gigabaytlarca ham veriyi eşitlemeye çalışır; depo içi de yanlışlıkla commit'lenebilir.
    onedrive_roots = []
    for variable in ("OneDrive", "OneDriveConsumer", "OneDriveCommercial"):
        value = os.environ.get(variable)
        if value:
            onedrive_roots.append(Path(value).resolve())
    if any("onedrive" in part.lower() for part in cache.parts) or any(cache.is_relative_to(r) for r in onedrive_roots):
        raise SystemExit(f"Önbellek OneDrive içinde olamaz: {cache}\n--cache ile OneDrive dışında bir klasör verin.")
    repo = REPO_ROOT.resolve()
    if cache.is_relative_to(repo) and not cache.is_relative_to(IN_REPO_CACHE.resolve()):
        raise SystemExit(f"Önbellek depo içinde yalnızca tools/area-grid/cache/ olabilir (git'e girmez): {cache}")
    cache.mkdir(parents=True, exist_ok=True)
    return cache


def is_url(spec: str) -> bool:
    return urllib.parse.urlparse(spec).scheme in ("http", "https")


def fetch(url: str, dest: Path, allow_download: bool) -> bool:
    """dest yoksa indirir; yalnızca --download ile. İndirme yapıldıysa True döner."""
    if dest.exists():
        return False
    if not allow_download:
        raise SystemExit(
            f"Eksik kaynak: {dest.name}\n  Adres: {url}\n  Önbellek: {dest.parent}\n"
            "İndirmek için --download ekleyin (boyutlar tools/area-grid/README.md'de) "
            "ya da dosyayı elle indirip bu klasöre koyun.")
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response, open(part, "wb") as out:
        length = response.headers.get("Content-Length")
        total = int(length) if length and length.isdigit() else None
        print(f"  indiriliyor: {url} ({human_size(total) if total else 'boyut bilinmiyor'})", flush=True)
        done, next_note = 0, 100 << 20
        while chunk := response.read(1 << 20):
            out.write(chunk)
            done += len(chunk)
            if done >= next_note:
                print(f"    {human_size(done)}" + (f" / {human_size(total)}" if total else ""), flush=True)
                next_note += 100 << 20
    if total is not None and done != total:
        part.unlink(missing_ok=True)
        raise SystemExit(f"İndirme yarım kaldı: {url} ({done} / {total} bayt)")
    os.replace(part, dest)
    return True


def resolve_pbf(spec: str, cache: Path, allow_download: bool) -> Path:
    if not is_url(spec):
        path = Path(spec).expanduser().resolve()
        if not path.is_file():
            raise SystemExit(f"pbf bulunamadı: {path}")
        return path
    parsed = urllib.parse.urlparse(spec)
    dest = cache / "downloads" / (Path(parsed.path).name or "turkey-latest.osm.pbf")
    downloaded = fetch(spec, dest, allow_download)
    md5_file = dest.with_name(dest.name + ".md5")
    if downloaded and parsed.hostname == "download.geofabrik.de":
        # Geofabrik her dosyanın yanında .md5 yayımlar; "latest" her gün değiştiği için hemen alınır.
        md5_file.unlink(missing_ok=True)
        fetch(spec + ".md5", md5_file, True)
    if md5_file.is_file():
        words = md5_file.read_text(encoding="ascii", errors="replace").split()
        got = file_digest(dest, "md5")
        if not words or got != words[0].lower():
            raise SystemExit(f"{dest.name}: MD5 {got}, {md5_file.name} başka diyor. İkisini silip yeniden indirin.")
        print(f"  {dest.name}: Geofabrik MD5 doğrulandı")
    return dest


def resolve_poly(spec: str, cache: Path, allow_download: bool) -> Path:
    if not is_url(spec):
        path = Path(spec).expanduser().resolve()
        if not path.is_file():
            raise SystemExit(f"Özün sınır dosyası (.poly) bulunamadı: {path}")
        return path
    dest = cache / "downloads" / (Path(urllib.parse.urlparse(spec).path).name or "turkey.poly")
    fetch(spec, dest, allow_download)
    return dest


def extract_shapefile(archive: Path, layer: str, target: Path) -> Path:
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            base = Path(info.filename).name  # yalnızca dosya adı: zip içindeki klasörler yok sayılır
            if info.is_dir() or not base.startswith(layer + "."):
                continue
            (target / base).write_bytes(z.read(info))
    shp = target / f"{layer}.shp"
    if not shp.is_file() or not (target / f"{layer}.shx").is_file():
        raise SystemExit(f"{archive.name} içinde {layer}.shp ve {layer}.shx yok")
    return shp


def resolve_natural_earth(spec: str, cache: Path, allow_download: bool) -> tuple[dict[str, Path], list[Path]]:
    """Katman adı → .shp yolu ve özeti yazılacak girdi dosyaları."""
    local = None if is_url(spec) else Path(spec).expanduser().resolve()
    if local is not None and not local.is_dir():
        raise SystemExit(f"Natural Earth klasörü bulunamadı: {local}")
    shp_paths: dict[str, Path] = {}
    inputs: list[Path] = []
    for layer in NE_LAYERS:
        if local is not None:
            shp = local / f"{layer}.shp"
            if shp.is_file():
                shp_paths[layer] = shp
                inputs.append(shp)
                continue
            archive = local / f"{layer}.zip"
            if not archive.is_file():
                raise SystemExit(f"Natural Earth katmanı yok: {shp} ya da {archive}")
        else:
            archive = cache / "downloads" / f"{layer}.zip"
            fetch(f"{spec.rstrip('/')}/{layer}.zip", archive, allow_download)
        shp_paths[layer] = extract_shapefile(archive, layer, cache / "natural-earth" / layer)
        inputs.append(archive)
    return shp_paths, inputs


def parse_expected_hashes(values: list[str]) -> dict[str, str]:
    expected = {}
    for value in values:
        name, sep, digest = value.partition("=")
        digest = digest.strip().lower()
        if not sep or not name or len(digest) != 64 or any(ch not in "0123456789abcdef" for ch in digest):
            raise SystemExit(f"--expect-sha256 DOSYA=SHA256 biçiminde olmalı: {value!r}")
        expected[name.strip()] = digest
    return expected


def report_inputs(inputs: list[Path], expected: dict[str, str]) -> None:
    print("Girdiler (README'deki tabloya işlenir):")
    seen = set()
    mismatches = []
    for path in inputs:
        digest = file_digest(path)
        seen.add(path.name)
        print(f"  {path.name:28} {human_size(path.stat().st_size):>10}  SHA-256 {digest}")
        if path.name in expected and expected[path.name] != digest:
            mismatches.append(f"{path.name}: {digest}, beklenen {expected[path.name]}")
    unknown = sorted(set(expected) - seen)
    if unknown:
        mismatches.append("--expect-sha256 ile verilen ama girdilerde olmayan dosya: " + ", ".join(unknown))
    if mismatches:
        raise SystemExit("Girdi özetleri tutmuyor:\n  " + "\n  ".join(mismatches))


def print_versions() -> None:
    parts = [f"Python {sys.version.split()[0]}"]
    for dist in ("numpy", "osmium", "pyshp"):
        try:
            parts.append(f"{dist} {importlib.metadata.version(dist)}")
        except importlib.metadata.PackageNotFoundError:
            parts.append(f"{dist} yok")
    print(" · ".join(parts))


def pbf_timestamp(pbf: Path) -> str | None:
    try:
        import osmium

        nothing = getattr(osmium.osm, "NOTHING", None)
        if nothing is None:
            nothing = osmium.osm.osm_entity_bits.NOTHING
        reader = osmium.io.Reader(str(pbf), nothing)
        try:
            return reader.header().get("osmosis_replication_timestamp", "") or None
        finally:
            reader.close()
    except Exception:  # yalnızca bilgi amaçlı; eski ya da yeni pyosmium'da ad farkı olabilir
        return None


# ---------------------------------------------------------------------------
# Tarama çizgisiyle çokgen doldurma (GDAL/rasterio gerekmez).

class SpanRasterizer:
    """Çokgenleri hücre merkezi kuralıyla (merkezi içeride kalan hücre dolu) satır aralıklarına çevirir.

    Bir alanın bütün halkaları (dış ve iç) aynı kimlikle eklenir; çift-tek kuralı delikleri kendiliğinden boş
    bırakır. Aralıklar küçüktür; ızgara en sonda bantlar hâlinde doldurulur, çünkü 3″ ızgara (7800 × 23400)
    bellekte bütün tutulmaz. touch=True, kenarın değdiği hücreleri de işaretler (rasterio'daki all_touched).
    """

    def __init__(self, cells_per_degree: int, rows: int, cols: int, touch: bool = False):
        self.cpd = cells_per_degree
        self.rows = rows
        self.cols = cols
        self.south_cell = SOUTH_MICRODEG * cells_per_degree / 1_000_000
        self.west_cell = WEST_MICRODEG * cells_per_degree / 1_000_000
        self.touched = np.zeros((rows, cols), dtype=bool) if touch else None
        self.polygons = 0
        self._spans: list[tuple] = []
        self._reset_buffers()

    def _reset_buffers(self) -> None:
        self._lon = array("d")
        self._lat = array("d")
        self._ring_len = array("q")
        self._ring_pid = array("q")

    def add_polygon(self, rings) -> None:
        """rings: [(boylamlar, enlemler), …]; halka kapalı olmasa da kapatılır."""
        pid = self.polygons
        added = False
        for lons, lats in rings:
            n = len(lons)
            if n < 3:
                continue
            self._lon.extend(lons)
            self._lat.extend(lats)
            if lons[0] != lons[-1] or lats[0] != lats[-1]:
                self._lon.append(lons[0])
                self._lat.append(lats[0])
                n += 1
            self._ring_len.append(n)
            self._ring_pid.append(pid)
            added = True
        if added:
            self.polygons += 1
            if len(self._lon) >= BATCH_VERTICES:
                self.flush()

    def flush(self) -> None:
        if not self._ring_len:
            return
        lon = np.array(self._lon, dtype=np.float64)
        lat = np.array(self._lat, dtype=np.float64)
        ring_len = np.array(self._ring_len, dtype=np.int64)
        ring_pid = np.array(self._ring_pid, dtype=np.int64)
        self._reset_buffers()
        x = lon * self.cpd - self.west_cell
        y = lat * self.cpd - self.south_cell
        # Kenar i, köşe i ile i+1 arasındadır; bir halkanın son köşesinden sonrakine kenar yoktur.
        valid = np.ones(x.size - 1, dtype=bool)
        valid[np.cumsum(ring_len)[:-1] - 1] = False
        i = np.flatnonzero(valid)
        x0, y0, x1, y1 = x[i], y[i], x[i + 1], y[i + 1]
        pid = np.repeat(ring_pid, ring_len)[i]
        if self.touched is not None:
            self._mark_touched(x0, y0, x1, y1)
        self._add_spans(x0, y0, x1, y1, pid)

    def _add_spans(self, x0, y0, x1, y1, pid) -> None:
        # r. satırın merkezi y = r + 0.5; kenar [ylo, yhi) yarı açık aralığıyla sayılır, köşeler bir kez kesilir.
        ylo = np.minimum(y0, y1)
        yhi = np.maximum(y0, y1)
        r0 = np.clip(np.ceil(ylo - 0.5), 0, self.rows).astype(np.int64)
        r1 = np.clip(np.ceil(yhi - 0.5), 0, self.rows).astype(np.int64)
        count = r1 - r0
        keep = count > 0
        if not keep.any():
            return
        x0, y0, x1, y1, pid, r0, count = (a[keep] for a in (x0, y0, x1, y1, pid, r0, count))
        edge = np.repeat(np.arange(count.size), count)
        first = np.cumsum(count) - count
        row = r0[edge] + (np.arange(edge.size) - first[edge])
        ex0 = x0[edge]
        ey0 = y0[edge]
        xs = ex0 + (row + 0.5 - ey0) * ((x1[edge] - ex0) / (y1[edge] - ey0))
        p = pid[edge]
        order = np.lexsort((xs, row, p))  # önce çokgen, sonra satır, sonra x
        xs, row, p = xs[order], row[order], p[order]
        if xs.size % 2 or np.any(row[0::2] != row[1::2]) or np.any(p[0::2] != p[1::2]):
            raise RuntimeError("tarama çizgisi kesişimleri çift çift eşleşmedi")
        c0 = np.clip(np.ceil(xs[0::2] - 0.5), 0, self.cols).astype(np.int32)
        c1 = np.clip(np.ceil(xs[1::2] - 0.5), 0, self.cols).astype(np.int32)
        r = row[0::2].astype(np.int32)
        ok = c1 > c0
        self._spans.append((r[ok], c0[ok], c1[ok]))

    def _mark_touched(self, x0, y0, x1, y1) -> None:
        near = ((np.maximum(x0, x1) >= -1) & (np.minimum(x0, x1) <= self.cols + 1)
                & (np.maximum(y0, y1) >= -1) & (np.minimum(y0, y1) <= self.rows + 1))
        if not near.any():
            return
        x0, y0, x1, y1 = x0[near], y0[near], x1[near], y1[near]
        steps = np.maximum(np.ceil(np.hypot(x1 - x0, y1 - y0) / TOUCH_STEP).astype(np.int64) + 1, 2)
        edge = np.repeat(np.arange(steps.size), steps)
        first = np.cumsum(steps) - steps
        t = (np.arange(edge.size) - first[edge]) / (steps[edge] - 1)
        px = x0[edge] + t * (x1[edge] - x0[edge])
        py = y0[edge] + t * (y1[edge] - y0[edge])
        inside = (px >= 0) & (px < self.cols) & (py >= 0) & (py < self.rows)
        self.touched[np.floor(py[inside]).astype(np.int64), np.floor(px[inside]).astype(np.int64)] = True

    def reduce(self, sub: int):
        """Her sub×sub blokta dolu hücre sayısı ve blok merkezindeki hücrenin dolu olup olmadığı."""
        self.flush()
        if self._spans:
            rows = np.concatenate([s[0] for s in self._spans])
            c0 = np.concatenate([s[1] for s in self._spans])
            c1 = np.concatenate([s[2] for s in self._spans])
        else:
            rows = c0 = c1 = np.zeros(0, dtype=np.int32)
        order = np.argsort(rows, kind="stable")
        rows, c0, c1 = rows[order], c0[order], c1[order]
        out_cols = self.cols // sub
        counts = np.zeros((self.rows // sub, out_cols), dtype=np.uint8)
        centre = np.zeros((self.rows // sub, out_cols), dtype=bool)
        band = sub * max(1, BAND_ROWS // sub)
        mid = sub // 2
        for top in range(0, self.rows, band):
            bottom = min(top + band, self.rows)
            lo, hi = np.searchsorted(rows, [top, bottom])
            height = bottom - top
            diff = np.zeros((height, self.cols + 1), dtype=np.int32)
            local = rows[lo:hi] - top
            np.add.at(diff, (local, c0[lo:hi]), 1)
            np.add.at(diff, (local, c1[lo:hi]), -1)
            covered = np.cumsum(diff, axis=1, dtype=np.int32)[:, : self.cols] > 0
            blocks = covered.reshape(height // sub, sub, out_cols, sub)
            counts[top // sub: bottom // sub] = blocks.sum(axis=(1, 3), dtype=np.int32)
            centre[top // sub: bottom // sub] = covered[mid::sub, mid::sub]
        return counts, centre


# ---------------------------------------------------------------------------
# Natural Earth (su).

def natural_earth_polygons(shp: Path):
    import shapefile  # pyshp

    polygon_types = {shapefile.POLYGON, shapefile.POLYGONZ, shapefile.POLYGONM}
    reader = shapefile.Reader(str(shp))
    try:
        for shape in reader.iterShapes():
            if shape.shapeType not in polygon_types or not shape.points:
                continue
            xmin, ymin, xmax, ymax = shape.bbox
            if xmax < WEST or xmin > EAST or ymax < SOUTH or ymin > NORTH:
                continue
            points = shape.points
            bounds = list(shape.parts) + [len(points)]
            rings = []
            for a, b in zip(bounds[:-1], bounds[1:]):
                if b - a >= 3:
                    rings.append(([pt[0] for pt in points[a:b]], [pt[1] for pt in points[a:b]]))
            if rings:
                yield rings
    finally:
        reader.close()


def rasterize_natural_earth(shp_paths: dict[str, Path]):
    """land: kara + küçük adalar, değdiği her hücre (all_touched). lake: merkezi gölde kalan hücreler."""
    land = SpanRasterizer(CELLS_PER_DEGREE, ROWS, COLS, touch=True)
    for layer in (NE_LAND, NE_MINOR_ISLANDS):
        for rings in natural_earth_polygons(shp_paths[layer]):
            land.add_polygon(rings)
    land_cover, _ = land.reduce(1)
    lakes = SpanRasterizer(CELLS_PER_DEGREE, ROWS, COLS)
    for rings in natural_earth_polygons(shp_paths[NE_LAKES]):
        lakes.add_polygon(rings)
    lake_cover, _ = lakes.reduce(1)
    print(f"  kara çokgeni {land.polygons}, göl çokgeni {lakes.polygons}")
    return (land_cover > 0) | land.touched, lake_cover > 0


# ---------------------------------------------------------------------------
# Özün sınırı (OSM verisinin olduğu yer).

def read_poly(path: Path) -> list[tuple[list[float], list[float]]]:
    """Osmosis .poly: ilk satır ad; her bölüm bir ad satırı, "boylam enlem" satırları ve END ("!" ile başlayan
    bölüm deliktir); dosya bir END ile biter. Bütün halkalar döner; delikleri çift-tek kuralı boşaltır."""
    lines = [line.strip() for line in path.read_text(encoding="utf-8", errors="replace").splitlines()]
    rings = []
    i = 1  # ilk satır dosyanın adı
    try:
        while i < len(lines):
            header = lines[i]
            i += 1
            if not header:
                continue
            if header == "END":
                break
            lons, lats = [], []
            while i < len(lines) and lines[i] != "END":
                if lines[i]:
                    lon, lat = lines[i].split()[:2]
                    lons.append(float(lon))
                    lats.append(float(lat))
                i += 1
            i += 1  # bölümün END'i
            if len(lons) >= 3:
                rings.append((lons, lats))
    except ValueError as error:
        raise SystemExit(f"{path.name} okunamadı ({i}. satır): {error}")
    if not rings:
        raise SystemExit(f"{path.name}: sınır çokgeni yok")
    return rings


def rasterize_coverage(poly: Path):
    """Bütün 3″ alt hücrelerinin merkezi özün sınırı içinde kalan hücreler: OSM verisi yalnızca bunlar için tamdır."""
    coverage = SpanRasterizer(FINE_CPD, FINE_ROWS, FINE_COLS)
    rings = read_poly(poly)
    coverage.add_polygon(rings)
    count, _ = coverage.reduce(SUB)
    print(f"  özün sınırı: {len(rings)} halka")
    return count == SUB * SUB


# ---------------------------------------------------------------------------
# OpenStreetMap (yerleşim ve orman).

@dataclass
class OsmLayers:
    buildings: object  # hücre başına bina sayısı
    places: object  # hücre başına yer düğümü sayısı
    landuse_count: object  # yerleşim kullanımıyla dolu alt hücre sayısı (0–25)
    landuse_centre: object  # hücre merkezi yerleşim kullanımında mı
    forest_count: object  # ormanla dolu alt hücre sayısı (0–25)
    stats: dict


def ring_coords(ring) -> tuple[array, array]:
    lons = array("d")
    lats = array("d")
    for node in ring:
        location = node.location
        lons.append(location.lon)
        lats.append(location.lat)
    return lons, lats


def area_rings(area) -> list[tuple[array, array]]:
    rings = []
    for outer in area.outer_rings():
        rings.append(ring_coords(outer))
        for inner in area.inner_rings(outer):
            rings.append(ring_coords(inner))
    return rings


def count_points(lons: array, lats: array):
    lon = np.array(lons, dtype=np.float64)
    lat = np.array(lats, dtype=np.float64)
    y = lat * CELLS_PER_DEGREE - SOUTH_CELL
    x = lon * CELLS_PER_DEGREE - WEST_CELL
    ok = (y >= 0) & (y < ROWS) & (x >= 0) & (x < COLS)
    flat = np.floor(y[ok]).astype(np.int64) * COLS + np.floor(x[ok]).astype(np.int64)
    return np.bincount(flat, minlength=ROWS * COLS).astype(np.int32).reshape(ROWS, COLS)


def read_osm(pbf: Path, node_index: str) -> OsmLayers:
    import osmium

    settled = SpanRasterizer(FINE_CPD, FINE_ROWS, FINE_COLS)
    forest = SpanRasterizer(FINE_CPD, FINE_ROWS, FINE_COLS)
    building_lon, building_lat = array("d"), array("d")
    place_lon, place_lat = array("d"), array("d")
    stats = collections.Counter()

    class Handler(osmium.SimpleHandler):
        def node(self, n):
            tags = n.tags
            if len(tags) == 0:
                return
            place = tags.get("place")
            building = tags.get("building")
            if place is None and building is None:
                return
            location = n.location
            if not location.valid():
                return
            if place in SETTLED_PLACES:
                place_lon.append(location.lon)
                place_lat.append(location.lat)
                stats["yer düğümü"] += 1
            if building is not None and building != "no":
                building_lon.append(location.lon)
                building_lat.append(location.lat)
                stats["bina (düğüm)"] += 1

        def area(self, a):
            tags = a.tags
            building = tags.get("building")
            landuse = tags.get("landuse")
            is_building = building is not None and building != "no"
            is_settled = landuse in SETTLED_LANDUSE
            is_forest = landuse == "forest" or tags.get("natural") == "wood"
            if not (is_building or is_settled or is_forest):
                return
            stats["ilgili alan"] += 1
            try:
                rings = area_rings(a)
            except Exception:  # eksik düğüm konumu ya da bozuk alan; sayılır, payı kapıda denetlenir
                rings = []
            if not rings:
                stats["okunamayan alan"] += 1
                return
            if is_building:
                lons, lats = rings[0]  # dış halkanın ortalaması: 15″ hücrede ağırlık merkezi kadar iyi
                building_lon.append(sum(lons) / len(lons))
                building_lat.append(sum(lats) / len(lats))
                stats["bina (alan)"] += 1
            if is_settled:
                settled.add_polygon(rings)
                stats["yerleşim kullanımı çokgeni"] += 1
            if is_forest:
                forest.add_polygon(rings)
                stats["orman çokgeni"] += 1

    Handler().apply_file(str(pbf), locations=True, idx=node_index)
    landuse_count, landuse_centre = settled.reduce(SUB)
    forest_count, _ = forest.reduce(SUB)
    return OsmLayers(
        buildings=count_points(building_lon, building_lat),
        places=count_points(place_lon, place_lat),
        landuse_count=landuse_count,
        landuse_centre=landuse_centre,
        forest_count=forest_count,
        stats=dict(stats),
    )


# OSM okuma kuralları (hangi etiketler, nasıl sayılır) değişince artırılır: önbellekteki katmanlar geçersiz olur.
OSM_RULES_VERSION = 1


def cached_osm_layers(pbf: Path, cache: Path, node_index: str) -> OsmLayers:
    """OSM katmanları pbf'nin özeti ve okuma kuralları sürümüyle önbelleğe yazılır. Sınıflandırma eşiklerini
    denerken Türkiye özünü (~25 dk) yeniden okumak gerekmez."""
    key = f"{file_digest(pbf)[:16]}-r{OSM_RULES_VERSION}"
    path = cache / f"osm-layers-{key}.npz"
    if path.is_file():
        print(f"OSM katmanları önbellekten: {path.name}", flush=True)
        with np.load(path, allow_pickle=False) as saved:
            stats = dict(zip(saved["stat_keys"].tolist(), saved["stat_values"].tolist()))
            return OsmLayers(buildings=saved["buildings"], places=saved["places"],
                             landuse_count=saved["landuse_count"], landuse_centre=saved["landuse_centre"],
                             forest_count=saved["forest_count"], stats=stats)
    print(f"OSM okunuyor: {pbf.name}. Türkiye özü birkaç dakikadan yarım saate kadar sürebilir…", flush=True)
    osm = read_osm(pbf, node_index)
    keys = sorted(osm.stats)
    np.savez_compressed(path, buildings=osm.buildings, places=osm.places, landuse_count=osm.landuse_count,
                        landuse_centre=osm.landuse_centre, forest_count=osm.forest_count,
                        stat_keys=np.array(keys), stat_values=np.array([osm.stats[k] for k in keys]))
    return osm


# ---------------------------------------------------------------------------
# Sınıflandırma.

def dilate(mask, iterations: int):
    """3×3 çekirdekle genişletme; kutunun dışı boş sayılır."""
    height, width = mask.shape
    out = mask
    for _ in range(iterations):
        padded = np.pad(out, 1, mode="constant", constant_values=False)
        grown = np.zeros_like(out)
        for dy in range(3):
            for dx in range(3):
                grown |= padded[dy:dy + height, dx:dx + width]
        out = grown
    return out


def erode(mask, iterations: int):
    """3×3 çekirdekle aşındırma; kutunun dışı kenardaki hücreyle aynı sayılır (kutu kenarı kıyı değildir)."""
    height, width = mask.shape
    out = mask
    for _ in range(iterations):
        padded = np.pad(out, 1, mode="edge")
        shrunk = np.ones_like(out)
        for dy in range(3):
            for dx in range(3):
                shrunk &= padded[dy:dy + height, dx:dx + width]
        out = shrunk
    return out


def neighbour_count(mask):
    height, width = mask.shape
    padded = np.pad(mask, 1, mode="constant", constant_values=False).astype(np.uint8)
    total = np.zeros((height, width), dtype=np.uint8)
    for dy in range(3):
        for dx in range(3):
            if (dy, dx) != (1, 1):
                total += padded[dy:dy + height, dx:dx + width]
    return total


def classify(osm: OsmLayers, land, lake, covered):
    forested = osm.forest_count >= MIN_FOREST_SUBCELLS
    enough_buildings = np.where(forested, osm.buildings >= MIN_BUILDINGS_IN_FOREST, osm.buildings >= MIN_BUILDINGS)
    settled = (enough_buildings | (osm.places > 0) | osm.landuse_centre
               | (osm.landuse_count >= MIN_LANDUSE_SUBCELLS))
    fringe = dilate(settled, FRINGE_ITERATIONS)
    settled_neighbours = neighbour_count(settled)
    forest = ((osm.forest_count >= MIN_FOREST_SUBCELLS) & ~settled
              & (settled_neighbours <= MAX_SETTLED_NEIGHBOURS_FOR_FOREST))
    water = erode(~land | lake, WATER_EROSION_ITERATIONS)
    # Özün dışındaki (ya da sınırına değen) karada OSM verisi yok ya da eksik: yerleşim ve orman bilinmiyor.
    # Bilinmeyen izinlidir (kutunun dışı gibi); yoksa Dedeağaç, Batum, Halep gibi yerler "yerleşim dışı" çıkardı.
    unknown = ~covered & ~water
    classes = np.full((ROWS, COLS), REMOTE, dtype=np.uint8)
    # Sıra önemli: yerleşik her şeyi, orman kuşağı, kuşak da suyu ezer (kıyı, Boğaz ve iskeleler açık kalır).
    classes[water] = WATER
    classes[fringe] = ALLOWED
    classes[forest] = FOREST
    classes[settled] = ALLOWED
    classes[unknown] = ALLOWED
    parts = {"settled": settled, "fringe": fringe, "forest": forest, "water": water, "unknown": unknown,
             "covered": covered, "settled_neighbours": settled_neighbours}
    return classes, parts


def pack_cells(classes) -> bytes:
    flat = np.ascontiguousarray(classes, dtype=np.uint8).reshape(-1)
    if flat.size != ROWS * COLS or int(flat.max()) > 3:
        raise RuntimeError("sınıf dizisi beklenen biçimde değil")
    # Hücre i, i/4. baytın 2*(i%4). bitinden başlar; satır 0 en güneydedir.
    packed = flat[0::4] | (flat[1::4] << 2) | (flat[2::4] << 4) | (flat[3::4] << 6)
    return packed.astype(np.uint8).tobytes()


def unpack_cells(payload: bytes):
    packed = np.frombuffer(payload, dtype=np.uint8)
    flat = np.empty(packed.size * 4, dtype=np.uint8)
    for k in range(4):
        flat[k::4] = (packed >> (2 * k)) & 3
    return flat.reshape(ROWS, COLS)


PREVIEW_PALETTE = bytes([
    232, 228, 218,  # yerleşim dışı
    222, 110, 60,  # izinli
    82, 140, 204,  # su
    46, 112, 62,  # orman
])


def write_preview_png(classes, path: Path) -> None:
    """Gözle kontrol için paletli PNG (kuzey üstte); yalnızca önbelleğe yazılır."""
    image = np.ascontiguousarray(classes[::-1])
    height, width = image.shape
    scanlines = np.zeros((height, width + 1), dtype=np.uint8)  # her satırın başında filtre baytı 0
    scanlines[:, 1:] = image

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0))
        + chunk(b"PLTE", PREVIEW_PALETTE)
        + chunk(b"IDAT", zlib.compress(scanlines.tobytes(), 9))
        + chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# Komutlar.

def build(args) -> int:
    if np is None:
        raise SystemExit("numpy yok. Kurulum: pip install -r tools/area-grid/requirements.txt")
    try:
        import osmium  # noqa: F401  (indirmeden önce eksik bağımlılığı söyle)
        import shapefile  # noqa: F401
    except ImportError as error:
        raise SystemExit(f"{error.name} yok. Kurulum: pip install -r tools/area-grid/requirements.txt")
    try:
        data_version = int(args.version)
        version_text = format_data_version(args.version)
    except ValueError:
        raise SystemExit("--version YYYYMMDD biçiminde geçerli bir tarih olmalı (ör. 20261001)")
    golden = load_golden(args.golden)
    expected_hashes = parse_expected_hashes(args.expect_sha256)
    cache = prepare_cache(args.cache)
    started = time.monotonic()

    print_versions()
    print(f"Önbellek: {cache}")
    print("Kaynaklar:")
    pbf = resolve_pbf(args.pbf, cache, args.download)
    poly = resolve_poly(args.poly, cache, args.download)
    ne_shps, ne_inputs = resolve_natural_earth(args.ne, cache, args.download)
    report_inputs([pbf, poly, *ne_inputs], expected_hashes)
    print(f"  OSM verisinin tarihi: {pbf_timestamp(pbf) or 'başlıkta yok'}")
    for layer, shp in ne_shps.items():
        version_file = shp.with_name(f"{layer}.VERSION.txt")
        if version_file.is_file():
            print(f"  {layer} sürümü: {version_file.read_text(encoding='utf-8', errors='replace').strip()}")

    print("\nNatural Earth kara, küçük ada ve göl katmanları ızgaraya işleniyor…", flush=True)
    land, lake = rasterize_natural_earth(ne_shps)
    covered = rasterize_coverage(poly)
    osm = cached_osm_layers(pbf, cache, args.node_index)
    for key, value in sorted(osm.stats.items()):
        print(f"  {key}: {value:,}")

    classes, parts = classify(osm, land, lake, covered)
    print(f"  yerleşik hücre {int(parts['settled'].sum()):,} · kuşak {int(parts['fringe'].sum()):,}"
          f" · orman {int(parts['forest'].sum()):,} · su {int(parts['water'].sum()):,}"
          f" · özün kapsadığı {int(covered.sum()):,} · öz dışı kara (izinli) {int(parts['unknown'].sum()):,}")

    data = pack_header(data_version) + pack_cells(classes)
    grid = parse_grid(data)
    if not np.array_equal(unpack_cells(grid.payload), classes):
        raise RuntimeError("paketlenen ızgara geri açılınca aynı çıkmadı")
    digest = hashlib.sha256(data).hexdigest()
    preview = cache / f"area-tr-{data_version}-preview.png"
    write_preview_png(classes, preview)

    counts = [int(n) for n in np.bincount(classes.reshape(-1), minlength=4)]
    print(f"\nVeri sürümü {version_text} · {len(data):,} bayt · {time.monotonic() - started:.0f} sn")
    print_shares(counts)
    print(f"SHA-256: {digest}")
    print(f"Önizleme (kuzey üstte): {preview}")

    problems = []
    if counts[FOREST] == 0:
        problems.append("Hiç orman hücresi yok: pbf Türkiye'yi kapsıyor mu, landuse=forest / natural=wood okundu mu?")
    if counts[WATER] == 0:
        problems.append("Hiç su hücresi yok: Natural Earth kara ve göl katmanları okundu mu?")
    if counts[ALLOWED] == 0:
        problems.append("Hiç izinli hücre yok.")
    if not covered.any():
        problems.append("Özün sınırı (.poly) kutuyla kesişmiyor: --poly, --pbf'nin özüne mi ait?")
    if not osm.stats.get("yer düğümü") or not (osm.stats.get("bina (alan)") or osm.stats.get("bina (düğüm)")):
        problems.append("OSM'den yer düğümü ya da bina okunamadı.")
    relevant = osm.stats.get("ilgili alan", 0)
    if relevant and osm.stats.get("okunamayan alan", 0) > MAX_BAD_AREA_SHARE * relevant:
        problems.append(f"Okunamayan alanların payı %{100 * MAX_BAD_AREA_SHARE:.0f}'ten fazla: pbf eksik ya da bozuk mu?")
    if problems:
        print("\nSAĞLIK DENETİMİ GEÇMEDİ:\n  " + "\n  ".join(problems))

    failures = check_golden(grid, golden)
    if failures:
        def describe(row: int, col: int) -> str:
            return (f"hücre ({row}, {col}): bina {osm.buildings[row, col]} · yerleşim kullanımı "
                    f"{osm.landuse_count[row, col]}/25{' (merkez dahil)' if osm.landuse_centre[row, col] else ''}"
                    f" · yer düğümü {osm.places[row, col]} · orman {osm.forest_count[row, col]}/25"
                    f" · yerleşik komşu {parts['settled_neighbours'][row, col]}/8"
                    f" · NE {'kara' if land[row, col] else 'deniz'}{' + göl' if lake[row, col] else ''}"
                    f" · {'özün içinde' if covered[row, col] else 'özün dışında ya da sınırında'}")

        print_golden_failures(grid, failures, describe)
    if problems or failures:
        print("\nHiçbir şey yazılmadı.")
        return 1
    print(f"Altın noktalar: {len(golden)}/{len(golden)} geçti.")

    if args.no_write:
        print("--no-write: çıktı yazılmadı.")
        return 0
    out = args.out.expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    temporary = out.with_name(out.name + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, out)
    print(f"Yazıldı: {out}\nGirdi özetlerini ve bu SHA-256'yı tools/area-grid/README.md'deki tabloya işleyin.")
    return 0


def verify(args) -> int:
    path = args.verify_bin.expanduser().resolve()
    try:
        data = path.read_bytes()
        grid = parse_grid(data)
    except (OSError, ValueError) as error:
        print(f"Geçersiz ızgara: {path}: {error}")
        return 1
    golden = load_golden(args.golden)
    print(f"{path}\nVeri sürümü {format_data_version(grid.data_version)} · {len(data):,} bayt")
    print_shares(class_counts(grid.payload))
    print(f"SHA-256: {hashlib.sha256(data).hexdigest()}")
    failures = check_golden(grid, golden)
    if failures:
        print_golden_failures(grid, failures)
        return 1
    print(f"Altın noktalar: {len(golden)}/{len(golden)} geçti.")
    return 0


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="build_area_grid.py",
        description="Pati Harita riskli alan ızgarasını (shared/area-tr.bin) OSM ve Natural Earth'ten üretir "
                    "ya da var olan bir ızgarayı denetler.",
        epilog="Kurallar, kaynaklar ve lisanslar: tools/area-grid/README.md")
    parser.add_argument("--version", help="veri sürümü YYYYMMDD (ör. 20261001); her yeniden üretimde artar")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="çıktı (varsayılan: shared/area-tr.bin)")
    parser.add_argument("--cache", type=Path,
                        help="ham veri klasörü, OneDrive ve depo dışında "
                             "(varsayılan: %%LOCALAPPDATA%%\\PatiHarita\\area-grid-cache)")
    parser.add_argument("--pbf", default=DEFAULT_PBF,
                        help="OSM Türkiye özü: yerel .osm.pbf yolu ya da adresi (varsayılan: Geofabrik turkey-latest)")
    parser.add_argument("--poly", default=DEFAULT_POLY,
                        help="özün sınırı (Osmosis .poly): yerel yol ya da adres (varsayılan: Geofabrik turkey.poly); "
                             "dışındaki kara bilinmiyor sayılır ve izinlidir")
    parser.add_argument("--ne", default=DEFAULT_NE,
                        help="Natural Earth 10 m fiziksel katmanlar: .zip ya da .shp içeren klasör, "
                             "ya da temel adres (varsayılan: naciscdn.org)")
    parser.add_argument("--download", action="store_true",
                        help="önbellekte olmayan kaynakları indir; bu olmadan hiçbir şey indirilmez")
    parser.add_argument("--expect-sha256", action="append", default=[], metavar="DOSYA=SHA256",
                        help="bu girdi dosyasının SHA-256'sı tutmalı (tekrarlanabilir)")
    parser.add_argument("--golden", type=Path, default=DEFAULT_GOLDEN,
                        help="altın noktalar (varsayılan: shared/area-golden.json)")
    parser.add_argument("--node-index", default="flex_mem",
                        help="pyosmium düğüm konumu deposu (varsayılan: flex_mem)")
    parser.add_argument("--no-write", action="store_true", help="her şeyi yap, kapıları denetle, ama çıktıyı yazma")
    parser.add_argument("--verify-bin", type=Path, metavar="BIN",
                        help="üretmeden, var olan bir ızgarayı başlık ve altın noktalarla denetle")
    args = parser.parse_args(argv)
    if args.verify_bin is None and not args.version:
        parser.error("--version gerekli (ya da denetim için --verify-bin)")
    return args


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    args = parse_args(argv)
    return verify(args) if args.verify_bin is not None else build(args)


if __name__ == "__main__":
    sys.exit(main())
