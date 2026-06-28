"""Equivalence tests for retained velocity implementations."""

from __future__ import annotations

import csv
import json
from pathlib import Path

import numpy as np
import pytest

from road_trajectory_analysis.validate_velocity import maximum_velocity
from scripts.velocity_experiments import (
    consecutive_speeds_numpy,
    consecutive_speeds_scalar_helper,
    consecutive_speeds_scalar_inlined,
)


def test_experimental_implementations_agree() -> None:
    coordinates = [
        [-8.618643, 41.141412],
        [-8.618499, 41.141376],
        [-8.618326, 41.141214],
        [-8.618112, 41.141052],
    ]

    helper_speeds = consecutive_speeds_scalar_helper(coordinates)
    inlined_speeds = consecutive_speeds_scalar_inlined(coordinates)
    numpy_speeds = consecutive_speeds_numpy(coordinates)

    np.testing.assert_allclose(
        helper_speeds,
        inlined_speeds,
        rtol=1e-12,
        atol=1e-12,
    )
    np.testing.assert_allclose(
        numpy_speeds,
        inlined_speeds,
        rtol=1e-12,
        atol=1e-12,
    )


def test_production_maximum_matches_reference_implementations() -> None:
    coordinates = [
        [-8.618643, 41.141412],
        [-8.618499, 41.141376],
        [-8.500000, 41.200000],
    ]

    expected_speeds = consecutive_speeds_scalar_inlined(coordinates)
    expected_segment = max(
        range(len(expected_speeds)),
        key=expected_speeds.__getitem__,
    )

    production_result = maximum_velocity(coordinates)

    assert production_result is not None
    production_speed, production_segment = production_result

    assert production_speed == pytest.approx(
        expected_speeds[expected_segment],
        rel=1e-12,
        abs=1e-12,
    )
    assert production_segment == expected_segment


def test_production_matches_scalar_reference_on_real_sample() -> None:
    sample_path = Path("data/interim/taxi_trips_sample.csv")

    if not sample_path.exists():
        pytest.skip("Taxi sample has not been generated")

    with sample_path.open(newline="", encoding="utf-8") as input_file:
        reader = csv.DictReader(input_file)

        for row in reader:
            coordinates = json.loads(row["POLYLINE"])
            reference_speeds = consecutive_speeds_scalar_inlined(
                coordinates
            )
            production_result = maximum_velocity(coordinates)

            if not reference_speeds:
                assert production_result is None
                continue

            expected_segment = max(
                range(len(reference_speeds)),
                key=reference_speeds.__getitem__,
            )

            assert production_result is not None
            production_speed, production_segment = production_result

            assert production_speed == pytest.approx(
                reference_speeds[expected_segment],
                rel=1e-12,
                abs=1e-12,
            )
            assert production_segment == expected_segment