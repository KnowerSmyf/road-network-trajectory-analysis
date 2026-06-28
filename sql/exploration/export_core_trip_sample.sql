COPY (
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'type', 'Feature',
                    'geometry', ST_AsGeoJSON(geom)::jsonb,
                    'properties', jsonb_build_object(
                        'trip_id', trip_id,
                        'taxi_id', taxi_id,
                        'started_at', started_at,
                        'point_count', point_count
                    )
                )
            ),
            '[]'::jsonb
        )
    )::text
    FROM (
        SELECT
            trip_id,
            taxi_id,
            started_at,
            point_count,
            geom
        FROM core.trips
        ORDER BY started_at
        LIMIT 20
    ) AS sample
) TO STDOUT;