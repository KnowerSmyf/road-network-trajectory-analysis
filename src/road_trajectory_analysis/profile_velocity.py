from __future__ import annotations

import argparse
import csv
import json
import statistics
from pathlib import Path

import numpy as np

from road_trajectory_analysis.validate_velocity import (
    consecutive_speeds_numpy,
)


DEFAULT_THRESHOLDS = [100.0, 150.0, 200.0, 250.0, 300.0]


def percentile(
    sorted_values: list[float],
    probability: float,
) -> float:
    """Return a nearest-rank-style percentile from sorted values."""

    if not sorted_values:
        raise ValueError("Cannot calculate a percentile of empty data")

    index = round((len(sorted_values) - 1) * probability)
    return sorted_values[index]


def profile_velocities(
    input_path: Path,
    limit: int | None = None,
) -> list[float]:
    """Return the maximum observed speed for every usable trajectory."""

    maximum_speeds: list[float] = []

    with input_path.open(newline="", encoding="utf-8") as input_file:
        reader = csv.DictReader(input_file)

        for row_number, row in enumerate(reader):
            if limit is not None and row_number >= limit:
                break

            try:
                coordinates = json.loads(row["POLYLINE"])
            except (TypeError, json.JSONDecodeError):
                continue

            speeds = consecutive_speeds_numpy(coordinates)

            if speeds.size == 0:
                continue

            maximum_speeds.append(float(np.max(speeds)))

    return maximum_speeds


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input",
        required=True,
        type=Path,
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()

    maximum_speeds = profile_velocities(
        input_path=arguments.input,
        limit=arguments.limit,
    )

    if not maximum_speeds:
        raise RuntimeError("No valid trip velocities were calculated")

    maximum_speeds.sort()
    total = len(maximum_speeds)

    print(f"Trips profiled: {total:,}")
    print()
    print("Maximum-speed distribution:")
    print(f"  Minimum:          {min(maximum_speeds):.2f} km/h")
    print(f"  Median:           {statistics.median(maximum_speeds):.2f} km/h")
    print(f"  90th percentile:  {percentile(maximum_speeds, 0.90):.2f} km/h")
    print(f"  95th percentile:  {percentile(maximum_speeds, 0.95):.2f} km/h")
    print(f"  99th percentile:  {percentile(maximum_speeds, 0.99):.2f} km/h")
    print(f"  Maximum:          {max(maximum_speeds):.2f} km/h")
    print()
    print("Threshold sensitivity:")

    for threshold in DEFAULT_THRESHOLDS:
        rejected = sum(
            speed > threshold
            for speed in maximum_speeds
        )
        rate = rejected / total

        print(
            f"  > {threshold:>5.0f} km/h: "
            f"{rejected:>8,} trips ({rate:>7.2%})"
        )


if __name__ == "__main__":
    main()