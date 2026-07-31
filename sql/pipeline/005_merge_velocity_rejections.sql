BEGIN;

DELETE FROM staging.trip_rejections
WHERE reason = 'implausible_velocity';

WITH velocity_by_trip AS (
    SELECT DISTINCT ON (trip_id)
        trip_id,
        max_speed_kmh,
        segment_index
    FROM staging.velocity_rejections_raw
    ORDER BY
        trip_id,
        max_speed_kmh DESC
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
    'implausible_velocity',
    jsonb_build_object(
        'max_speed_kmh', velocity.max_speed_kmh,
        'segment_index', velocity.segment_index,
        'sampling_interval_seconds', 15,
        'threshold_kmh', 200
    )
FROM staging.taxi_trips_raw AS raw
JOIN velocity_by_trip AS velocity
    ON velocity.trip_id = raw.trip_id
ON CONFLICT (ingestion_id, reason)
DO UPDATE SET
    trip_id = EXCLUDED.trip_id,
    details = EXCLUDED.details,
    rejected_at = now();

DROP TABLE staging.velocity_rejections_raw;

COMMIT;