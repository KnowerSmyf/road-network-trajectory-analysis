"""Identify taxi trips containing implausible consecutive-point velocities."""

from __future__ import annotations

import argparse
import csv
import json
import math
import numpy as np
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

EARTH_RADIUS_KM = 6_371.0088
DEFAULT_INTERVAL_SECONDS = 15.0
DEFAULT_MAX_SPEED_KMH = 200.0


@dataclass(frozen=True)
class VelocityRejection:
    """Details of a trip rejected because of an implausible velocity."""
    trip_id: int
    max_speed_kmh: float
    segment_index: int


def maximum_velocity(
    coordinates: Sequence[Sequence[float]],
    interval_seconds: float = DEFAULT_INTERVAL_SECONDS,
) -> tuple[float, int] | None:
    """Return the maximum consecutive-point velocity and its segment index."""

    if interval_seconds <= 0:
        raise ValueError("interval_seconds must be positive")

    points = np.asarray(coordinates, dtype=np.float64)

    if points.size == 0:
        return None

    if points.ndim != 2 or points.shape[1] != 2:
        raise ValueError("coordinates must have shape (n, 2)")

    if points.shape[0] < 2:
        return None

    longitudes = np.radians(points[:, 0])
    latitudes = np.radians(points[:, 1])

    delta_longitudes = np.diff(longitudes)
    delta_latitudes = np.diff(latitudes)

    haversine = (
        np.sin(delta_latitudes / 2.0) ** 2
        + np.cos(latitudes[:-1])
        * np.cos(latitudes[1:])
        * np.sin(delta_longitudes / 2.0) ** 2
    )

    angular_distances = 2.0 * np.arcsin(
        np.minimum(1.0, np.sqrt(haversine))
    )

    speeds_kmh = (
        EARTH_RADIUS_KM
        * angular_distances
        * (3_600.0 / interval_seconds)
    )

    maximum_segment = int(np.argmax(speeds_kmh))

    return (
        float(speeds_kmh[maximum_segment]),
        maximum_segment,
    )


def find_velocity_rejection(
    trip_id: int,
    coordinates: Sequence[Sequence[float]],
    max_speed_kmh: float = DEFAULT_MAX_SPEED_KMH,
    interval_seconds: float = DEFAULT_INTERVAL_SECONDS,
) -> VelocityRejection | None:
    """Return rejection details when a trip exceeds the speed threshold."""

    result = maximum_velocity(coordinates, interval_seconds)

    if result is None:
        return None

    observed_speed, segment_index = result

    if observed_speed <= max_speed_kmh:
        return None

    return VelocityRejection(
        trip_id=trip_id,
        max_speed_kmh=observed_speed,
        segment_index=segment_index,
    )


def iter_velocity_rejections(
    input_path: Path,
    max_speed_kmh: float = DEFAULT_MAX_SPEED_KMH,
    interval_seconds: float = DEFAULT_INTERVAL_SECONDS,
) -> Iterable[VelocityRejection]:
    """Stream the source CSV and yield trips exceeding the velocity limit."""

    with input_path.open(newline="", encoding="utf-8") as input_file:
        reader = csv.DictReader(input_file)

        required_columns = {"TRIP_ID", "POLYLINE"}
        missing_columns = required_columns.difference(reader.fieldnames or [])

        if missing_columns:
            missing = ", ".join(sorted(missing_columns))
            raise ValueError(f"Input CSV is missing required columns: {missing}")

        for line_number, row in enumerate(reader, start=2):
            try:
                trip_id = int(row["TRIP_ID"])
                coordinates = json.loads(row["POLYLINE"])
            except (TypeError, ValueError, json.JSONDecodeError) as error:
                # Structural validation belongs to the SQL validation stage.
                print(
                    f"Skipping malformed row {line_number}: {error}",
                    flush=True,
                )
                continue

            rejection = find_velocity_rejection(
                trip_id=trip_id,
                coordinates=coordinates,
                max_speed_kmh=max_speed_kmh,
                interval_seconds=interval_seconds,
            )

            if rejection is not None:
                yield rejection


def write_rejections(
    rejections: Iterable[VelocityRejection],
    output_path: Path,
) -> int:
    """Write velocity rejection records and return the number written."""

    output_path.parent.mkdir(parents=True, exist_ok=True)

    count = 0

    with output_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(
            output_file,
            fieldnames=[
                "trip_id",
                "max_speed_kmh",
                "segment_index",
            ],
        )
        writer.writeheader()

        for rejection in rejections:
            writer.writerow(
                {
                    "trip_id": rejection.trip_id,
                    "max_speed_kmh": f"{rejection.max_speed_kmh:.6f}",
                    "segment_index": rejection.segment_index,
                }
            )
            count += 1

    return count


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Identify taxi trips containing consecutive GPS observations "
            "that imply an implausible velocity."
        )
    )
    parser.add_argument(
        "--input",
        required=True,
        type=Path,
        help="Path to the source taxi CSV.",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Path for the generated velocity rejection CSV.",
    )
    parser.add_argument(
        "--max-speed-kmh",
        type=float,
        default=DEFAULT_MAX_SPEED_KMH,
        help=f"Maximum permitted velocity (default: {DEFAULT_MAX_SPEED_KMH}).",
    )
    parser.add_argument(
        "--interval-seconds",
        type=float,
        default=DEFAULT_INTERVAL_SECONDS,
        help=(
            "Seconds between consecutive GPS observations "
            f"(default: {DEFAULT_INTERVAL_SECONDS})."
        ),
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()

    if arguments.max_speed_kmh <= 0:
        raise ValueError("max-speed-kmh must be positive")

    rejections = iter_velocity_rejections(
        input_path=arguments.input,
        max_speed_kmh=arguments.max_speed_kmh,
        interval_seconds=arguments.interval_seconds,
    )

    count = write_rejections(rejections, arguments.output)

    print(
        f"Wrote {count} velocity rejection(s) to {arguments.output}",
        flush=True,
    )


if __name__ == "__main__":
    main()
