"""Tests for production taxi velocity validation."""

from __future__ import annotations

import pytest

from road_trajectory_analysis.validate_velocity import (
    find_velocity_rejection,
    maximum_velocity,
)


def test_trip_with_fewer_than_two_points_has_no_velocity() -> None:
    assert maximum_velocity([]) is None
    assert maximum_velocity([[-8.6, 41.1]]) is None


def test_stationary_trip_has_zero_velocity() -> None:
    result = maximum_velocity(
        [
            [-8.618643, 41.141412],
            [-8.618643, 41.141412],
        ]
    )

    assert result is not None
    speed, segment_index = result

    assert speed == pytest.approx(0.0)
    assert segment_index == 0


def test_known_short_segment_is_about_27_kmh() -> None:
    result = maximum_velocity(
        [
            [-8.6, 41.100],
            [-8.6, 41.101],
        ]
    )

    assert result is not None
    speed, segment_index = result

    assert speed == pytest.approx(26.7, rel=0.03)
    assert segment_index == 0


def test_known_long_segment_is_about_267_kmh() -> None:
    result = maximum_velocity(
        [
            [-8.6, 41.100],
            [-8.6, 41.110],
        ]
    )

    assert result is not None
    speed, segment_index = result

    assert speed == pytest.approx(266.9, rel=0.03)
    assert segment_index == 0


def test_maximum_velocity_returns_fastest_segment() -> None:
    result = maximum_velocity(
        [
            [-8.6000, 41.1000],
            [-8.6000, 41.1001],
            [-8.6000, 41.1100],
        ]
    )

    assert result is not None
    _, segment_index = result

    assert segment_index == 1


def test_large_coordinate_jump_is_rejected() -> None:
    rejection = find_velocity_rejection(
        trip_id=123,
        coordinates=[
            [-8.618643, 41.141412],
            [-8.500000, 41.200000],
        ],
        max_speed_kmh=200.0,
        interval_seconds=15.0,
    )

    assert rejection is not None
    assert rejection.trip_id == 123
    assert rejection.max_speed_kmh > 200.0
    assert rejection.segment_index == 0


def test_small_coordinate_change_is_accepted() -> None:
    rejection = find_velocity_rejection(
        trip_id=456,
        coordinates=[
            [-8.618643, 41.141412],
            [-8.618499, 41.141376],
        ],
        max_speed_kmh=200.0,
        interval_seconds=15.0,
    )

    assert rejection is None


def test_non_positive_interval_is_rejected() -> None:
    with pytest.raises(ValueError):
        maximum_velocity(
            [
                [-8.6, 41.1],
                [-8.6, 41.2],
            ],
            interval_seconds=0,
        )


@pytest.mark.parametrize(
    "coordinates",
    [
        [[-8.6]],
        [[-8.6, 41.1, 123.0]],
        [[-8.6, 41.1], [-8.6]],
    ],
)
def test_invalid_coordinate_shape_is_rejected(
    coordinates: list[list[float]],
) -> None:
    with pytest.raises(ValueError, match="shape"):
        maximum_velocity(coordinates)