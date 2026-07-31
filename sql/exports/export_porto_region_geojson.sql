WITH endpoints AS (
    SELECT ST_StartPoint(geom) AS geom FROM core.trips
    UNION ALL
    SELECT ST_EndPoint(geom) AS geom FROM core.trips
),
bounds AS (
    SELECT
        percentile_cont(0.001) WITHIN GROUP (ORDER BY ST_X(geom)) AS min_lon,
        percentile_cont(0.999) WITHIN GROUP (ORDER BY ST_X(geom)) AS max_lon,
        percentile_cont(0.001) WITHIN GROUP (ORDER BY ST_Y(geom)) AS min_lat,
        percentile_cont(0.999) WITHIN GROUP (ORDER BY ST_Y(geom)) AS max_lat
    FROM endpoints
),
filtered AS (
    SELECT endpoints.geom
    FROM endpoints, bounds
    WHERE ST_X(endpoints.geom) BETWEEN bounds.min_lon AND bounds.max_lon
      AND ST_Y(endpoints.geom) BETWEEN bounds.min_lat AND bounds.max_lat
),
region AS (
    SELECT ST_ConvexHull(ST_Collect(geom)) AS geom
    FROM filtered
)
SELECT jsonb_build_object(
    'type', 'FeatureCollection',
    'features', jsonb_build_array(
        jsonb_build_object(
            'type', 'Feature',
            'properties', jsonb_build_object(
                'name', 'porto_operating_region_convex_hull_v1',
                'source', 'Convex hull of robust taxi trip start/end points',
                'endpoint_percentile_min', 0.001,
                'endpoint_percentile_max', 0.999
            ),
            'geometry', ST_AsGeoJSON(geom)::jsonb
        )
    )
)::text
FROM region;

-- To run the file, execute the following
-- docker compose exec -T db \
--   psql \
--   -qAt \
--   -U road_user \
--   -d road_analysis \
--   < sql/exports/export_porto_region_geojson.sql \
--   > config/porto_region.geojson