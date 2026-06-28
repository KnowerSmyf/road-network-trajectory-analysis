from __future__ import annotations

import argparse
import csv
import json
import statistics
import time
from collections.abc import Callable, Sequence
from pathlib import Path

import numpy as np

from scripts.velocity_experiments import (
    consecutive_speeds_numpy,
    consecutive_speeds_scalar_helper,
    consecutive_speeds_scalar_inlined,
)


Coordinates = list[list[float]]
SpeedFunction = Callable[
    [Sequence[Sequence[float]], float],
    Sequence[float] | np.ndarray,
]


def load_polylines(
    input_path: Path,
    limit: int,
) -> list[Coordinates]:
    """Load valid polylines for repeatable in-memory benchmarking."""

    polylines: list[Coordinates] = []

    with input_path.open(newline="", encoding="utf-8") as input_file:
        reader = csv.DictReader(input_file)

        for row in reader:
            if len(polylines) >= limit:
                break

            try:
                coordinates = json.loads(row["POLYLINE"])
            except (TypeError, json.JSONDecodeError):
                continue

            if len(coordinates) >= 2:
                polylines.append(coordinates)

    return polylines


def benchmark(
    function: SpeedFunction,
    polylines: list[Coordinates],
    repeats: int,
) -> list[float]:
    """Return elapsed times over repeated runs."""

    elapsed_times: list[float] = []

    for _ in range(repeats):
        started_at = time.perf_counter()

        for coordinates in polylines:
            function(coordinates, 15.0)

        elapsed_times.append(time.perf_counter() - started_at)

    return elapsed_times


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input",
        type=Path,
        required=True,
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=50_000,
    )
    parser.add_argument(
        "--repeats",
        type=int,
        default=3,
    )
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()

    polylines = load_polylines(
        input_path=arguments.input,
        limit=arguments.limit,
    )

    if not polylines:
        raise RuntimeError("No usable trajectories were loaded")

    point_counts = [len(polyline) for polyline in polylines]

    print(f"Trajectories: {len(polylines):,}")
    print(f"Total points: {sum(point_counts):,}")
    print(f"Median points per trip: {statistics.median(point_counts):.1f}")
    print()

    helper_times = benchmark(
        consecutive_speeds_scalar_helper,
        polylines,
        arguments.repeats,
    )

    inlined_times = benchmark(
        consecutive_speeds_scalar_inlined,
        polylines,
        arguments.repeats,
    )

    numpy_times = benchmark(
        consecutive_speeds_numpy,
        polylines,
        arguments.repeats,
    )
        
    helper_median = statistics.median(helper_times)
    inlined_median = statistics.median(inlined_times)
    numpy_median = statistics.median(numpy_times)

    print(f"Scalar helper runs:  {[round(value, 3) for value in helper_times]}")
    print(f"Scalar inlined runs: {[round(value, 3) for value in inlined_times]}")
    print(f"NumPy runs:          {[round(value, 3) for value in numpy_times]}")
    print()
    print(f"Scalar helper median:  {helper_median:.3f}s")
    print(f"Scalar inlined median: {inlined_median:.3f}s")
    print(f"NumPy median:          {numpy_median:.3f}s")
    print()
    print(
        "Inlining speed-up:     "
        f"{helper_median / inlined_median:.2f}x"
    )
    print(
        "NumPy vs inlined:      "
        f"{inlined_median / numpy_median:.2f}x"
    )
    print(
        "NumPy vs helper:       "
        f"{helper_median / numpy_median:.2f}x"
    )

if __name__ == "__main__":
    main()