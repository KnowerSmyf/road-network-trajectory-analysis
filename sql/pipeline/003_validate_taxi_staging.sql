BEGIN;

TRUNCATE TABLE staging.trip_rejections
RESTART IDENTITY;

-- The source dataset explicitly flags incomplete trajectories.
INSERT INTO staging.trip_rejections (
    ingestion_id,
    trip_id,
    reason,
    details
)
SELECT
    ingestion_id,
    trip_id,
    'missing_data',
    jsonb_build_object(
        'missing_data', missing_data
    )
FROM staging.taxi_trips_raw
WHERE missing_data IS TRUE
ON CONFLICT (ingestion_id, reason) DO NOTHING;

-- Required source identifiers must be present.
INSERT INTO staging.trip_rejections (
    ingestion_id,
    trip_id,
    reason,
    details
)
SELECT
    ingestion_id,
    trip_id,
    'missing_required_value',
    jsonb_strip_nulls(
        jsonb_build_object(
            'trip_id_missing', trip_id IS NULL,
            'taxi_id_missing', taxi_id IS NULL,
            'timestamp_missing', source_timestamp IS NULL,
            'polyline_missing', polyline_raw IS NULL
        )
    )
FROM staging.taxi_trips_raw
WHERE trip_id IS NULL
   OR taxi_id IS NULL
   OR source_timestamp IS NULL
   OR polyline_raw IS NULL
ON CONFLICT (ingestion_id, reason) DO NOTHING;

-- Validate source categories.
INSERT INTO staging.trip_rejections (
    ingestion_id,
    trip_id,
    reason,
    details
)
SELECT
    ingestion_id,
    trip_id,
    'invalid_category',
    jsonb_build_object(
        'call_type', call_type,
        'day_type', day_type
    )
FROM staging.taxi_trips_raw
WHERE call_type NOT IN ('A', 'B', 'C')
   OR day_type NOT IN ('A', 'B', 'C')
   OR call_type IS NULL
   OR day_type IS NULL
ON CONFLICT (ingestion_id, reason) DO NOTHING;

-- Polylines must contain at least two coordinates.
INSERT INTO staging.trip_rejections (
    ingestion_id,
    trip_id,
    reason,
    details
)
SELECT
    ingestion_id,
    trip_id,
    'insufficient_points',
    jsonb_build_object(
        'point_count',
        jsonb_array_length(polyline_raw::jsonb)
    )
FROM staging.taxi_trips_raw
WHERE polyline_raw IS NOT NULL
  AND jsonb_array_length(polyline_raw::jsonb) < 2
ON CONFLICT (ingestion_id, reason) DO NOTHING;

-- Duplicate source trip IDs are rejected as ambiguous.
WITH duplicate_ids AS (
    SELECT
        trip_id,
        count(*) AS occurrence_count
    FROM staging.taxi_trips_raw
    WHERE trip_id IS NOT NULL
    GROUP BY trip_id
    HAVING count(*) > 1
)
INSERT INTO staging.trip_rejections (
    ingestion_id,
    trip_id,
    reason,
    details
)
SELECT
    raw.ingestion_id,
    raw.trip_id,
    'duplicate_trip_id',
    jsonb_build_object(
        'occurrence_count', duplicates.occurrence_count
    )
FROM staging.taxi_trips_raw AS raw
JOIN duplicate_ids AS duplicates
    USING (trip_id)
ON CONFLICT (ingestion_id, reason) DO NOTHING;

COMMIT;