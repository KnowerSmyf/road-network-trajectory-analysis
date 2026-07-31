DO $$
DECLARE
    loaded_rows integer;
    invalid_trip_ids integer;
    invalid_taxi_ids integer;
    invalid_timestamps integer;
    invalid_json integer;
BEGIN
    SELECT count(*)
    INTO loaded_rows
    FROM staging.taxi_trips_raw;

    IF loaded_rows <> 1000 THEN
        RAISE EXCEPTION
            'Expected 1000 staged trips, found %',
            loaded_rows;
    END IF;

    SELECT count(*)
    INTO invalid_trip_ids
    FROM staging.taxi_trips_raw
    WHERE trip_id IS NULL;

    IF invalid_trip_ids > 0 THEN
        RAISE EXCEPTION
            'Found % rows with null trip_id',
            invalid_trip_ids;
    END IF;

    SELECT count(*)
    INTO invalid_taxi_ids
    FROM staging.taxi_trips_raw
    WHERE taxi_id IS NULL;

    IF invalid_taxi_ids > 0 THEN
        RAISE EXCEPTION
            'Found % rows with null taxi_id',
            invalid_taxi_ids;
    END IF;

    SELECT count(*)
    INTO invalid_timestamps
    FROM staging.taxi_trips_raw
    WHERE source_timestamp IS NULL;

    IF invalid_timestamps > 0 THEN
        RAISE EXCEPTION
            'Found % rows with null source_timestamp',
            invalid_timestamps;
    END IF;

    SELECT count(*)
    INTO invalid_json
    FROM staging.taxi_trips_raw
    WHERE jsonb_typeof(polyline_raw::jsonb) <> 'array';

    IF invalid_json > 0 THEN
        RAISE EXCEPTION
            'Found % rows with non-array polylines',
            invalid_json;
    END IF;
END
$$;