# Velocity validation

Taxi trajectories are represented as ordered GPS coordinates sampled at 15-second intervals. A trip is rejected when any pair of consecutive observations implies a speed greater than 200 km/h.

## Validation rule

For each consecutive pair of coordinates:

1. calculate the great-circle distance using the Haversine formula;
2. divide by the 15-second sampling interval;
3. convert the result to kilometres per hour;
4. record the maximum observed segment speed for the trip.

Trips whose maximum segment speed exceeds 200 km/h are written to the velocity-rejection output.

The threshold is intended to identify implausible GPS jumps rather than model normal driving behaviour.

## Algorithmic improvement

The original assignment implementation constructed a full pairwise distance matrix for every trajectory, even though only distances between consecutive observations were required.

For a trajectory containing (n) points:

* the original approach calculated approximately (n^2) distances;
* the revised approach calculates only (n - 1) consecutive distances.

This reduces the per-trajectory time complexity from (O(n^2)) to (O(n)).

On the full Porto taxi dataset, the revised validator completed in roughly 40 seconds, compared with approximately 30 minutes for the original quadratic implementation.

## Implementation exploration

Three linear implementations were benchmarked:

1. scalar Python using a reusable Haversine helper;
2. scalar Python with the Haversine calculation inlined;
3. vectorised NumPy.

The benchmark used:

* 100,000 trajectories;
* 4,843,796 GPS points;
* a median trajectory length of 41 points;
* five repeated runs per implementation.

| Implementation                         | Median runtime |
| -------------------------------------- | -------------: |
| Scalar Python with Haversine helper    |        1.772 s |
| Scalar Python with inlined calculation |        1.273 s |
| Vectorised NumPy                       |        1.218 s |

Inlining reduced scalar runtime by approximately 28%. This showed that repeated Python function calls were a meaningful source of overhead across millions of trajectory segments.

NumPy reduced runtime by a further 4% relative to the optimised scalar implementation and achieved approximately 1.45 times the throughput of the original helper-based implementation.

The production validator therefore uses the NumPy implementation. The scalar implementations are retained under `scripts/` for reproducibility and benchmarking, but are not part of the production validation path.

## Correctness checks

The production implementation was validated using:

* stationary-coordinate cases;
* known-distance synthetic segments;
* insufficient-point cases;
* malformed coordinate-shape cases;
* threshold acceptance and rejection cases;
* identification of the correct maximum-speed segment;
* numerical equivalence between scalar and NumPy implementations;
* equivalence across a real 1,000-trip sample;
* comparison of generated rejection CSV files;
* visual inspection of rejected trajectories as GeoJSON.

The production and scalar reference implementations produced equivalent results on the real sample.

## Speed distribution

A profile of the first 100,000 source rows produced 98,445 trips with at least two coordinates.

| Statistic       | Maximum segment speed |
| --------------- | --------------------: |
| Minimum         |             0.00 km/h |
| Median          |            66.74 km/h |
| 90th percentile |           179.59 km/h |
| 95th percentile |           211.43 km/h |
| 99th percentile |         1,241.59 km/h |
| Maximum         |       137,950.28 km/h |

Threshold sensitivity for the same sample was:

| Threshold | Rejected trips | Rejection rate |
| --------- | -------------: | -------------: |
| 100 km/h  |         27,629 |         28.07% |
| 150 km/h  |         13,828 |         14.05% |
| 200 km/h  |          5,494 |          5.58% |
| 250 km/h  |          4,363 |          4.43% |
| 300 km/h  |          3,981 |          4.04% |

The extreme upper tail, including speeds above 1,000 km/h, is consistent with severe GPS-coordinate jumps. Visual inspection of rejected trajectories confirmed that many contained clearly implausible geometry segments.

The 200 km/h threshold was retained as a conservative quality-control rule. It removes implausible movements while avoiding the much larger rejection rates produced by lower thresholds.

## Full-dataset result

The full velocity scan identified 38,216 trips whose maximum consecutive-point speed exceeded 200 km/h.

The validator only generates rejection records. These records are subsequently merged into the PostgreSQL staging rejection table before canonical trajectories are built.
