from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any

import geopandas as gpd
import osmnx as ox
from shapely import make_valid
from shapely.geometry import GeometryCollection, MultiPolygon, Polygon, shape
from shapely.geometry.base import BaseGeometry
from shapely.ops import unary_union


DEFAULT_REGION_PATH = Path("config/porto_region.geojson")
DEFAULT_OUTPUT_DIR = Path("data/interim/osm")
DEFAULT_REGION_NAME = "porto"

WGS84_CRS = "EPSG:4326"
SUPPORTED_NETWORK_TYPES = ("drive", "drive_service")


def read_geojson(path: Path) -> dict[str, Any]:
    """Read a GeoJSON file and return its top-level object."""
    if not path.exists():
        raise FileNotFoundError(
            f"Region file not found: {path}. "
            "Create the region GeoJSON file first or pass --region."
        )

    if not path.is_file():
        raise ValueError(f"Region path is not a file: {path}")

    try:
        with path.open("r", encoding="utf-8") as file:
            geojson = json.load(file)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"Region file is not valid JSON: {path}. "
            f"Error at line {exc.lineno}, column {exc.colno}: {exc.msg}"
        ) from exc
    except OSError as exc:
        raise OSError(f"Could not read region file {path}: {exc}") from exc

    if not isinstance(geojson, dict):
        raise ValueError(
            f"GeoJSON root must be an object, got {type(geojson).__name__}: {path}"
        )

    return geojson


def geometry_from_geojson(geojson: dict[str, Any], path: Path) -> BaseGeometry:
    """
    Extract a geometry from a GeoJSON object.

    For a FeatureCollection, all non-null feature geometries are combined.
    """
    geojson_type = geojson.get("type")

    try:
        if geojson_type == "FeatureCollection":
            features = geojson.get("features")

            if not isinstance(features, list):
                raise ValueError(
                    f"GeoJSON FeatureCollection 'features' must be a list: {path}"
                )

            if not features:
                raise ValueError(
                    f"GeoJSON FeatureCollection has no features: {path}"
                )

            geometries: list[BaseGeometry] = []

            for index, feature in enumerate(features):
                if not isinstance(feature, dict):
                    raise ValueError(
                        f"Feature {index} is not a GeoJSON object: {path}"
                    )

                feature_geometry = feature.get("geometry")
                if feature_geometry is None:
                    continue

                geometries.append(shape(feature_geometry))

            if not geometries:
                raise ValueError(
                    f"GeoJSON FeatureCollection contains no non-null geometries: "
                    f"{path}"
                )

            return unary_union(geometries)

        if geojson_type == "Feature":
            feature_geometry = geojson.get("geometry")
            if feature_geometry is None:
                raise ValueError(f"GeoJSON Feature has a null geometry: {path}")

            return shape(feature_geometry)

        # Treat a top-level GeoJSON geometry object directly.
        return shape(geojson)

    except (KeyError, TypeError, ValueError) as exc:
        if isinstance(exc, ValueError) and str(exc).endswith(str(path)):
            raise

        raise ValueError(
            f"Could not parse geometry from GeoJSON file {path}: {exc}"
        ) from exc


def extract_polygonal_geometry(geometry: BaseGeometry) -> BaseGeometry:
    """
    Extract Polygon components from a geometry.

    Geometry repair can produce a GeometryCollection containing polygons,
    lines, and points. Only polygonal parts are valid for OSMnx polygon
    downloads.
    """
    if isinstance(geometry, Polygon):
        return geometry

    if isinstance(geometry, MultiPolygon):
        return geometry

    if isinstance(geometry, GeometryCollection):
        polygon_parts: list[Polygon] = []

        for part in geometry.geoms:
            polygonal_part = extract_polygonal_geometry(part)

            if isinstance(polygonal_part, Polygon):
                polygon_parts.append(polygonal_part)
            elif isinstance(polygonal_part, MultiPolygon):
                polygon_parts.extend(polygonal_part.geoms)

        if not polygon_parts:
            raise ValueError(
                "GeometryCollection contains no Polygon or MultiPolygon parts."
            )

        return unary_union(polygon_parts)

    raise ValueError(
        "Region must contain Polygon or MultiPolygon geometry, "
        f"not {geometry.geom_type}."
    )


def validate_wgs84_bounds(geometry: BaseGeometry) -> None:
    """
    Perform a basic sanity check that coordinates could be WGS84 lon/lat.

    GeoJSON coordinates are interpreted as EPSG:4326 by this script.
    """
    min_x, min_y, max_x, max_y = geometry.bounds

    bounds = (min_x, min_y, max_x, max_y)
    if not all(math.isfinite(value) for value in bounds):
        raise ValueError(f"Region has non-finite coordinate bounds: {bounds}")

    if min_x < -180 or max_x > 180:
        raise ValueError(
            "Region longitude coordinates fall outside [-180, 180]. "
            "The input must use WGS84 longitude/latitude coordinates."
        )

    if min_y < -90 or max_y > 90:
        raise ValueError(
            "Region latitude coordinates fall outside [-90, 90]. "
            "The input must use WGS84 longitude/latitude coordinates."
        )


def load_region_geometry(path: Path) -> BaseGeometry:
    """
    Load, combine, repair, and validate polygonal geometry from GeoJSON.

    The input coordinates are assumed to use EPSG:4326, as required by
    standard GeoJSON and OSMnx polygon download functions.
    """
    geojson = read_geojson(path)
    geometry = geometry_from_geojson(geojson, path)

    if geometry.is_empty:
        raise ValueError(f"Region geometry is empty: {path}")

    if not geometry.is_valid:
        geometry = make_valid(geometry)

    geometry = extract_polygonal_geometry(geometry)

    if geometry.is_empty:
        raise ValueError(
            f"Region geometry became empty after validation and repair: {path}"
        )

    if not geometry.is_valid:
        raise ValueError(
            f"Region geometry remains invalid after repair: {path}"
        )

    if geometry.area <= 0:
        raise ValueError(f"Region geometry has no positive area: {path}")

    validate_wgs84_bounds(geometry)

    return geometry


def buffer_geometry_meters(
    geometry: BaseGeometry,
    meters: float,
) -> BaseGeometry:
    """Buffer a WGS84 geometry in metres using a locally estimated UTM CRS."""
    if not math.isfinite(meters):
        raise ValueError("Buffer distance must be a finite number.")

    if meters < 0:
        raise ValueError("Buffer distance cannot be negative.")

    if meters == 0:
        return geometry

    region_gdf = gpd.GeoDataFrame(
        {"geometry": [geometry]},
        crs=WGS84_CRS,
    )

    projected_crs = region_gdf.estimate_utm_crs()
    if projected_crs is None:
        raise ValueError(
            "Could not estimate a projected CRS for metric buffering."
        )

    projected = region_gdf.to_crs(projected_crs)
    buffered_geometry = projected.geometry.buffer(meters).iloc[0]

    if buffered_geometry.is_empty:
        raise ValueError("Buffered region geometry is empty.")

    buffered_wgs84 = (
        gpd.GeoSeries([buffered_geometry], crs=projected_crs)
        .to_crs(WGS84_CRS)
        .iloc[0]
    )

    buffered_wgs84 = extract_polygonal_geometry(buffered_wgs84)

    if buffered_wgs84.is_empty or not buffered_wgs84.is_valid:
        raise ValueError(
            "Buffered region geometry is empty or invalid after reprojection."
        )

    validate_wgs84_bounds(buffered_wgs84)

    return buffered_wgs84


def safe_filename_component(value: str) -> str:
    """Convert a user-provided label into a safe filename component."""
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", value.strip())
    cleaned = cleaned.strip("._-")

    if not cleaned:
        raise ValueError(
            "Region name must contain at least one letter or number."
        )

    return cleaned.lower()


def build_output_paths(
    output_dir: Path,
    region_name: str,
    network_type: str,
) -> dict[str, Path]:
    """Build all generated output paths."""
    prefix = safe_filename_component(region_name)

    return {
        "graphml": output_dir / f"{prefix}_{network_type}.graphml",
        "gpkg": output_dir / f"{prefix}_{network_type}.gpkg",
        "fuel": output_dir / f"{prefix}_fuel_stations.geojson",
        "metadata": output_dir / f"{prefix}_{network_type}_metadata.json",
    }


def check_output_paths(
    paths: dict[str, Path],
    overwrite: bool,
) -> None:
    """Refuse to overwrite existing output files unless explicitly allowed."""
    existing = [path for path in paths.values() if path.exists()]

    if existing and not overwrite:
        formatted = "\n".join(f"  - {path}" for path in existing)
        raise FileExistsError(
            "The following output files already exist:\n"
            f"{formatted}\n"
            "Use --overwrite to replace them."
        )

    for path in existing:
        if path.is_dir():
            raise IsADirectoryError(
                f"Expected an output file but found a directory: {path}"
            )


def remove_existing_outputs(paths: dict[str, Path]) -> None:
    """Remove existing files before writing replacement outputs."""
    for path in paths.values():
        if path.exists():
            path.unlink()


def write_empty_geojson(path: Path) -> None:
    """Write a valid empty GeoJSON FeatureCollection."""
    empty_collection = {
        "type": "FeatureCollection",
        "features": [],
    }

    with path.open("w", encoding="utf-8") as file:
        json.dump(empty_collection, file, indent=2)
        file.write("\n")


def write_metadata(
    path: Path,
    *,
    region_source: Path,
    region_name: str,
    network_type: str,
    buffer_meters: float,
    node_count: int,
    edge_count: int,
    fuel_count: int,
) -> None:
    """Write basic provenance and output summary metadata."""
    metadata = {
        "region_source": str(region_source),
        "region_name": region_name,
        "network_type": network_type,
        "buffer_meters": buffer_meters,
        "intersection_consolidation": False,
        "graph_simplification": True,
        "node_count": node_count,
        "edge_count": edge_count,
        "fuel_feature_count": fuel_count,
        "osmnx_version": ox.__version__,
    }

    with path.open("w", encoding="utf-8") as file:
        json.dump(metadata, file, indent=2)
        file.write("\n")


def fetch_network(
    region: BaseGeometry,
    *,
    region_source: Path,
    region_name: str,
    output_dir: Path,
    network_type: str,
    buffer_meters: float,
    overwrite: bool,
) -> None:
    """Fetch an OSM road graph and fuel stations, then save the outputs."""
    output_dir.mkdir(parents=True, exist_ok=True)

    if not output_dir.is_dir():
        raise NotADirectoryError(
            f"Output path is not a directory: {output_dir}"
        )

    output_paths = build_output_paths(
        output_dir=output_dir,
        region_name=region_name,
        network_type=network_type,
    )

    check_output_paths(output_paths, overwrite=overwrite)

    print(f"Fetching OSM road graph with network_type={network_type!r}...")

    # simplify=True performs topological graph simplification.
    # It does not perform intersection consolidation.
    graph = ox.graph.graph_from_polygon(
        region,
        network_type=network_type,
        simplify=True,
        retain_all=False,
        truncate_by_edge=True,
    )

    if graph.number_of_nodes() == 0:
        raise RuntimeError("OSMnx returned a graph with no nodes.")

    if graph.number_of_edges() == 0:
        raise RuntimeError("OSMnx returned a graph with no edges.")

    print("Adding OSMnx speed and travel-time estimates...")
    graph = ox.routing.add_edge_speeds(graph)
    graph = ox.routing.add_edge_travel_times(graph)

    nodes, edges = ox.convert.graph_to_gdfs(graph)

    print("Fetching fuel stations...")
    fuel = ox.features.features_from_polygon(
        region,
        tags={"amenity": "fuel"},
    )

    # Do not delete previous outputs until all remote fetches and graph
    # calculations have succeeded.
    if overwrite:
        remove_existing_outputs(output_paths)

    print(f"Saving GraphML: {output_paths['graphml']}")
    ox.io.save_graphml(
        graph,
        filepath=output_paths["graphml"],
    )

    print(f"Saving GeoPackage: {output_paths['gpkg']}")
    ox.io.save_graph_geopackage(
        graph,
        filepath=output_paths["gpkg"],
        directed=True,
    )

    print(f"Saving fuel stations: {output_paths['fuel']}")
    if fuel.empty:
        write_empty_geojson(output_paths["fuel"])
    else:
        fuel.to_file(
            output_paths["fuel"],
            driver="GeoJSON",
            index=True,
        )

    print(f"Saving metadata: {output_paths['metadata']}")
    write_metadata(
        output_paths["metadata"],
        region_source=region_source,
        region_name=region_name,
        network_type=network_type,
        buffer_meters=buffer_meters,
        node_count=len(nodes),
        edge_count=len(edges),
        fuel_count=len(fuel),
    )

    print()
    print("OSM fetch summary")
    print("-----------------")
    print(f"Nodes:                     {len(nodes):,}")
    print(f"Edges:                     {len(edges):,}")
    print(f"Fuel features:             {len(fuel):,}")
    print("Graph simplification:      yes")
    print("Intersection consolidation: no")
    print(f"Output directory:          {output_dir}")


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description=(
            "Fetch a road network and fuel stations from OpenStreetMap "
            "using OSMnx."
        )
    )

    parser.add_argument(
        "--region",
        type=Path,
        default=DEFAULT_REGION_PATH,
        help=(
            "Path to a GeoJSON Polygon, MultiPolygon, Feature, or "
            "FeatureCollection defining the operating region."
        ),
    )

    parser.add_argument(
        "--region-name",
        default=DEFAULT_REGION_NAME,
        help="Region label used in generated filenames.",
    )

    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Directory for generated OSM outputs.",
    )

    parser.add_argument(
        "--buffer-meters",
        type=float,
        default=1500.0,
        help=(
            "Non-negative distance in metres by which to buffer the region "
            "before downloading OSM data."
        ),
    )

    parser.add_argument(
        "--network-type",
        default="drive_service",
        choices=SUPPORTED_NETWORK_TYPES,
        help="OSMnx network type to fetch.",
    )

    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace existing output files.",
    )

    return parser.parse_args()


def main() -> None:
    """Run the OSM data-fetching workflow."""
    args = parse_args()

    region_name = safe_filename_component(args.region_name)
    region = load_region_geometry(args.region)
    buffered_region = buffer_geometry_meters(
        region,
        args.buffer_meters,
    )

    print(f"Region source:              {args.region}")
    print(f"Region name:                {region_name}")
    print(f"Buffer metres:              {args.buffer_meters:,.0f}")
    print(f"Network type:               {args.network_type}")
    print("Graph simplification:       yes")
    print("Intersection consolidation: no")
    print(f"Output directory:           {args.output_dir}")
    print()

    fetch_network(
        region=buffered_region,
        region_source=args.region,
        region_name=region_name,
        output_dir=args.output_dir,
        network_type=args.network_type,
        buffer_meters=args.buffer_meters,
        overwrite=args.overwrite,
    )


if __name__ == "__main__":
    main()