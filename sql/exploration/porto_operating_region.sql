\echo 'Suggested manual bbox from robust endpoint extent'
SELECT
    41.00 AS south,
    -8.75 AS west,
    41.35 AS north,
    -8.43 AS east;

\echo 'Convex hull of robust endpoints'
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
)
SELECT ST_AsGeoJSON(ST_ConvexHull(ST_Collect(geom))) AS geojson
FROM filtered;

\echo 'Concave hull of robust endpoints'
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
)
SELECT ST_AsGeoJSON(ST_ConcaveHull(ST_Collect(geom), 0.95)) AS geojson
FROM filtered;

