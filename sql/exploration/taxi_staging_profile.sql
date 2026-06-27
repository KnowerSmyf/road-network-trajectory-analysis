SELECT
    count(*) AS total_rows,
    count(*) FILTER (WHERE trip_id IS NULL) AS null_trip_ids,
    count(*) FILTER (WHERE taxi_id IS NULL) AS null_taxi_ids,
    count(*) FILTER (WHERE source_timestamp IS NULL) AS null_timestamps,
    count(*) FILTER (WHERE origin_call IS NULL) AS null_origin_calls,
    count(*) FILTER (WHERE origin_stand IS NULL) AS null_origin_stands,
    count(*) FILTER (WHERE polyline_raw IS NULL) AS null_polylines
FROM staging.taxi_trips_raw;

SELECT
    call_type,
    count(*) AS trip_count
FROM staging.taxi_trips_raw
GROUP BY call_type
ORDER BY call_type;

SELECT
    day_type,
    count(*) AS trip_count
FROM staging.taxi_trips_raw
GROUP BY day_type
ORDER BY day_type;

SELECT
    missing_data,
    count(*) AS trip_count
FROM staging.taxi_trips_raw
GROUP BY missing_data
ORDER BY missing_data;

SELECT
    min(jsonb_array_length(polyline_raw::jsonb)) AS minimum_points,
    round(avg(jsonb_array_length(polyline_raw::jsonb)), 2) AS average_points,
    max(jsonb_array_length(polyline_raw::jsonb)) AS maximum_points
FROM staging.taxi_trips_raw;

SELECT
    ingestion_id,
    trip_id,
    taxi_id,
    to_timestamp(source_timestamp) AS started_at,
    call_type,
    missing_data,
    left(polyline_raw, 100) AS polyline_preview
FROM staging.taxi_trips_raw
ORDER BY ingestion_id
LIMIT 10;