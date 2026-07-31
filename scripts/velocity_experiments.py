"""Reference velocity implementations retained for performance experiments."""

from __future__ import annotations

import math
from collections.abc import Sequence

import numpy as np


EARTH_RADIUS_KM = 6_371.0088
DEFAULT_INTERVAL_SECONDS = 15.0


def haversine_distance_km(
    first: Sequence[float],
    second: Sequence[float],
) -> float:
    """Calculate distance using a reusable scalar helper."""

    lon1, lat1 = map(math.radians, first)
    lon2, lat2 = map(math.radians, second)

    delta_lon = lon2 - lon1
    delta_lat = lat2 - lat1

    haversine = (
        math.sin(delta_lat / 2.0) ** 2
        + math.cos(lat1)
        * math.cos(lat2)
        * math.sin(delta_lon / 2.0) ** 2
    )

    angular_distance = 2.0 * math.asin(
        min(1.0, math.sqrt(haversine))
    )

    return EARTH_RADIUS_KM * angular_distance


def consecutive_speeds_scalar_helper(
    coordinates: Sequence[Sequence[float]],
    interval_seconds: float = DEFAULT_INTERVAL_SECONDS,
) -> list[float]:
    """Scalar implementation that delegates distance calculation to a helper."""

    if interval_seconds <= 0:
        raise ValueError("interval_seconds must be positive")

    speed_multiplier = 3_600.0 / interval_seconds

    return [
        haversine_distance_km(first, second) * speed_multiplier
        for first, second in zip(coordinates, coordinates[1:])
    ]


def consecutive_speeds_scalar_inlined(
    coordinates: Sequence[Sequence[float]],
    interval_seconds: float = DEFAULT_INTERVAL_SECONDS,
) -> list[float]:
    """Scalar implementation with the Haversine calculation inlined."""

    if interval_seconds <= 0:
        raise ValueError("interval_seconds must be positive")

    speed_multiplier = 3_600.0 / interval_seconds
    speeds: list[float] = []

    for first, second in zip(coordinates, coordinates[1:]):
        lon1 = math.radians(first[0])
        lat1 = math.radians(first[1])
        lon2 = math.radians(second[0])
        lat2 = math.radians(second[1])

        delta_lon = lon2 - lon1
        delta_lat = lat2 - lat1

        haversine = (
            math.sin(delta_lat / 2.0) ** 2
            + math.cos(lat1)
            * math.cos(lat2)
            * math.sin(delta_lon / 2.0) ** 2
        )

        angular_distance = 2.0 * math.asin(
            min(1.0, math.sqrt(haversine))
        )

        speeds.append(
            EARTH_RADIUS_KM
            * angular_distance
            * speed_multiplier
        )

    return speeds


def consecutive_speeds_numpy(
    coordinates: Sequence[Sequence[float]],
    interval_seconds: float = DEFAULT_INTERVAL_SECONDS,
) -> np.ndarray:
    """Vectorised NumPy implementation."""

    if interval_seconds <= 0:
        raise ValueError("interval_seconds must be positive")

    points = np.asarray(coordinates, dtype=np.float64)

    if points.size == 0:
        return np.empty(0, dtype=np.float64)

    if points.ndim != 2 or points.shape[1] != 2:
        raise ValueError("coordinates must have shape (n, 2)")

    if points.shape[0] < 2:
        return np.empty(0, dtype=np.float64)

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

    return (
        EARTH_RADIUS_KM
        * angular_distances
        * (3_600.0 / interval_seconds)
    )