DO $$
DECLARE
    staged_rows integer;
    rejected_rows integer;
    accepted_rows integer;
    invalid_geometries integer;
    invalid_srids integer;
    count_mismatches integer;
BEGIN
    SELECT count(*)
    INTO staged_rows
    FROM staging.taxi_trips_raw;

    SELECT count(DISTINCT ingestion_id)
    INTO rejected_rows
    FROM staging.trip_rejections;

    SELECT count(*)
    INTO accepted_rows
    FROM core.trips;

    IF accepted_rows <> staged_rows - rejected_rows THEN
        RAISE EXCEPTION
            'Row reconciliation failed: staged %, rejected %, core %',
            staged_rows,
            rejected_rows,
            accepted_rows;
    END IF;

    SELECT count(*)
    INTO invalid_geometries
    FROM core.trips
    WHERE geom IS NULL
       OR ST_GeometryType(geom) <> 'ST_LineString'
       OR NOT ST_IsValid(geom)
       OR ST_IsEmpty(geom);

    IF invalid_geometries > 0 THEN
        RAISE EXCEPTION
            'Found % invalid core trip geometries',
            invalid_geometries;
    END IF;

    SELECT count(*)
    INTO invalid_srids
    FROM core.trips
    WHERE ST_SRID(geom) <> 4326;

    IF invalid_srids > 0 THEN
        RAISE EXCEPTION
            'Found % geometries with an unexpected SRID',
            invalid_srids;
    END IF;

    SELECT count(*)
    INTO count_mismatches
    FROM core.trips
    WHERE ST_NPoints(geom) <> point_count;

    IF count_mismatches > 0 THEN
        RAISE EXCEPTION
            'Found % point-count mismatches',
            count_mismatches;
    END IF;
END
$$;