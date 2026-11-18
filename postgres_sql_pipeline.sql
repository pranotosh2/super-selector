-- PostgreSQL schema and materialized view creation for Cricket Pressure Analytics
-- Adapted from original cross‑platform SQL pipeline

-- =============================================================
-- STEP 1: PRE‑COMPUTE 1ST INNINGS TOTALS
-- =============================================================
DROP TABLE IF EXISTS match_inn1_totals CASCADE;
CREATE TABLE match_inn1_totals (
    match_id TEXT PRIMARY KEY,
    inn1_total_runs INTEGER NOT NULL,
    inn1_total_wkts INTEGER NOT NULL
);

INSERT INTO match_inn1_totals
SELECT 
    match_id,
    SUM(runs + extras1_runs + extras_2_runs) AS inn1_total_runs,
    SUM(CASE WHEN is_wicket = 'true' THEN 1 ELSE 0 END) AS inn1_total_wkts
FROM raw_ball_by_ball
WHERE innings = 1
GROUP BY match_id;

CREATE INDEX IF NOT EXISTS idx_inn1_match ON match_inn1_totals(match_id);

-- =============================================================
-- STEP 2: BUILD FACT TABLE WITH RUNNING MATCH STATE & PRESSURE
-- =============================================================
DROP TABLE IF EXISTS fact_deliveries_pressure CASCADE;

CREATE TABLE fact_deliveries_pressure AS
WITH match_state_calc AS (
    SELECT
        b.match_id,
        b.innings,
        b.overid,
        b.over_ball_num,
        b.innings_ball_num,
        b.batting_team_id,
        b.bowling_team_id,
        b.striker_id,
        b.striker_name,
        b.non_striker_id,
        b.non_striker_name,
        b.bowler_id,
        b.bowler_name,
        b.batting_type,
        b.bowling_type,
        b.batting_order,
        b.runs AS runs_off_bat,
        b.extras1_runs,
        b.extras_2_runs,
        b.extras_type,
        b.is_four,
        b.is_six,
        b.is_wicket,
        b.dismissal_type,
        b.dismissed_player_id,
        m.comp_id,
        c.comp_name,
        c.comp_tier,
        m.knock_out,
        COALESCE(m.revised_target, inn1.inn1_total_runs + 1, 0) AS target_runs,
        CASE 
            WHEN b.innings IN (3,4) THEN 6
            WHEN b.innings = 2 AND m.second_inn_revised_overs IS NOT NULL AND m.second_inn_revised_overs > 0 THEN m.second_inn_revised_overs
            ELSE 120
        END AS scheduled_balls,
        COALESCE(SUM(b.runs + b.extras1_runs + b.extras_2_runs) OVER (
            PARTITION BY b.match_id, b.innings
            ORDER BY b.innings_ball_num
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),0) AS curr_runs_before,
        COALESCE(SUM(CASE WHEN b.is_wicket = 'true' THEN 1 ELSE 0 END) OVER (
            PARTITION BY b.match_id, b.innings
            ORDER BY b.innings_ball_num
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),0) AS curr_wkts_before,
        COALESCE(COUNT(CASE WHEN b.extras_type NOT IN ('wide','Overstep') THEN 1 END) OVER (
            PARTITION BY b.match_id, b.innings
            ORDER BY b.innings_ball_num
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ),0) AS legal_balls_before
    FROM raw_ball_by_ball b
    LEFT JOIN matches m ON b.match_id = m.match_id
    LEFT JOIN competitions c ON m.comp_id = c.comp_id
    LEFT JOIN match_inn1_totals inn1 ON b.match_id = inn1.match_id
)
SELECT *,
    -- Pressure flag: true when required run rate > current run rate and wickets remaining low
    CASE WHEN (
        (target_runs - (curr_runs_before + runs_off_bat))::DOUBLE PRECISION / (scheduled_balls - legal_balls_before)::DOUBLE PRECISION
    ) > (
        (curr_runs_before + runs_off_bat)::DOUBLE PRECISION / GREATEST(legal_balls_before,1)::DOUBLE PRECISION
    ) AND (10 - curr_wkts_before) <= 3 THEN true ELSE false END AS under_pressure
FROM match_state_calc;

-- Indexes for analytic queries
CREATE INDEX IF NOT EXISTS idx_fact_match_inn ON fact_deliveries_pressure(match_id, innings);
CREATE INDEX IF NOT EXISTS idx_fact_player ON fact_deliveries_pressure(striker_id, bowler_id);
CREATE INDEX IF NOT EXISTS idx_fact_pressure ON fact_deliveries_pressure(under_pressure);

-- =============================================================
-- STEP 3: DIMENSION TABLES (populate from CSVs after load)
-- =============================================================
-- The dimension tables are simple and will be populated via the data‑load script.
-- Example definitions (adjust column types as needed):

DROP TABLE IF EXISTS dim_players CASCADE;
CREATE TABLE dim_players (
    player_id TEXT PRIMARY KEY,
    player_name TEXT NOT NULL
);

DROP TABLE IF EXISTS dim_matches CASCADE;
CREATE TABLE dim_matches (
    match_id TEXT PRIMARY KEY,
    comp_id TEXT,
    match_date DATE,
    venue TEXT,
    team1_id TEXT,
    team2_id TEXT,
    result TEXT
    -- add other columns present in your CSV as needed
);

DROP TABLE IF EXISTS dim_competitions CASCADE;
CREATE TABLE dim_competitions (
    comp_id TEXT PRIMARY KEY,
    comp_name TEXT,
    comp_tier TEXT
);

-- =============================================================
-- ANALYTIC VIEWS – TOP 10 BATTERS & BOWLERS UNDER PRESSURE
-- =============================================================

CREATE OR REPLACE VIEW view_batter_pressure_analysis AS
SELECT
    f.striker_id AS player_id,
    d.player_name,
    SUM(CASE WHEN f.under_pressure THEN 1 ELSE 0 END) AS pressure_deliveries_faced,
    COUNT(*) FILTER (WHERE f.runs_off_bat > 0) AS runs_scored,
    SUM(f.runs_off_bat) AS total_runs,
    ROUND(100.0 * SUM(CASE WHEN f.under_pressure THEN 1 ELSE 0 END)::NUMERIC / COUNT(*),2) AS pressure_strike_rate
FROM fact_deliveries_pressure f
JOIN dim_players d ON f.striker_id = d.player_id
GROUP BY f.striker_id, d.player_name
HAVING COUNT(*) >= 100
ORDER BY pressure_strike_rate DESC
LIMIT 10;

CREATE OR REPLACE VIEW view_bowler_pressure_analysis AS
SELECT
    f.bowler_id AS player_id,
    d.player_name,
    SUM(CASE WHEN f.under_pressure THEN 1 ELSE 0 END) AS pressure_deliveries_bowled,
    COUNT(*) FILTER (WHERE f.runs_off_bat > 0) AS wickets_taken,
    ROUND( SUM(CASE WHEN f.runs_off_bat > 0 THEN 1 ELSE 0 END)::NUMERIC / NULLIF(SUM(f.runs_off_bat),0) * 6,2) AS pressure_economy
FROM fact_deliveries_pressure f
JOIN dim_players d ON f.bowler_id = d.player_id
GROUP BY f.bowler_id, d.player_name
HAVING COUNT(*) >= 100
ORDER BY pressure_economy ASC
LIMIT 10;