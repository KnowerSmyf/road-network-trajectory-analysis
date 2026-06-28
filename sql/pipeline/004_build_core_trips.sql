BEGIN;

CREATE TABLE IF NOT EXISTS core.trips (
    trip_id bigint PRIMARY KEY,
    taxi_id integer NOT NULL,
    call_type text NOT NULL,
    origin_call bigint,
    origin_stand integer,
    started_at timestamptz NOT NULL,
    day_type text NOT NULL,
    point_count integer NOT NULL,
    geom geometry(LineString, 4326) NOT NULL,

    CONSTRAINT trips_call_type_check
        CHECK (call_type IN ('A', 'B', 'C')),

    CONSTRAINT trips_day_type_check
        CHECK (day_type IN ('A', 'B', 'C')),

    CONSTRAINT trips_point_count_check
        CHECK (point_count >= 2)
);

TRUNCATE TABLE core.trips;

WITH accepted_trips AS (
    SELECT raw.*
    FROM staging.taxi_trips_raw AS raw
    WHERE NOT EXISTS (
        SELECT 1
        FROM staging.trip_rejections AS rejection
        WHERE rejection.ingestion_id = raw.ingestion_id
    )
),
parsed_trips AS (
    SELECT
        trip_id,
        taxi_id,
        call_type,
        origin_call,
        origin_stand,
        to_timestamp(source_timestamp) AS started_at,
        day_type,
        polyline_raw::jsonb AS polyline,
        jsonb_array_length(polyline_raw::jsonb) AS point_count
    FROM accepted_trips
),
trip_geometries AS (
    SELECT
        parsed.trip_id,
        parsed.taxi_id,
        parsed.call_type,
        parsed.origin_call,
        parsed.origin_stand,
        parsed.started_at,
        parsed.day_type,
        parsed.point_count,
        ST_MakeLine(
            ST_SetSRID(
                ST_MakePoint(
                    (coordinate.value ->> 0)::double precision,
                    (coordinate.value ->> 1)::double precision
                ),
                4326
            )
            ORDER BY coordinate.ordinality
        ) AS geom
    FROM parsed_trips AS parsed
    CROSS JOIN LATERAL jsonb_array_elements(parsed.polyline)
        WITH ORDINALITY AS coordinate(value, ordinality)
    GROUP BY
        parsed.trip_id,
        parsed.taxi_id,
        parsed.call_type,
        parsed.origin_call,
        parsed.origin_stand,
        parsed.started_at,
        parsed.day_type,
        parsed.point_count
)
INSERT INTO core.trips (
    trip_id,
    taxi_id,
    call_type,
    origin_call,
    origin_stand,
    started_at,
    day_type,
    point_count,
    geom
)
SELECT
    trip_id,
    taxi_id,
    call_type,
    origin_call,
    origin_stand,
    started_at,
    day_type,
    point_count,
    geom
FROM trip_geometries;

CREATE INDEX IF NOT EXISTS trips_geom_gix
    ON core.trips
    USING gist (geom);

COMMIT;