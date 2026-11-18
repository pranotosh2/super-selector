# Load CSV data into PostgreSQL for Cricket Pressure Analytics
# Requires: psycopg2-binary

import psycopg2
import csv
from pathlib import Path

# ==== Connection parameters (edit as needed) ====
HOST = "localhost"
PORT = 5432
DBNAME = "cricket_analytics"
USER = "your_username"
PASSWORD = "your_password"
# ===========================================

# Path to the folder containing exported CSVs (as per previous steps)
CSV_ROOT = Path(r"D:\Data Pack\powerbi_export")

TABLES = [
    ("dim_players", "player_id,player_name"),
    ("dim_matches", "match_id,comp_id,match_date,venue,team1_id,team2_id,result"),
    ("dim_competitions", "comp_id,comp_name,comp_tier"),
    ("fact_deliveries_pressure", "match_id,innings,overid,over_ball_num,innings_ball_num,batting_team_id,bowling_team_id,striker_id,striker_name,non_striker_id,non_striker_name,bowler_id,bowler_name,batting_type,bowling_type,batting_order,runs_off_bat,extras1_runs,extras_2_runs,extras_type,is_four,is_six,is_wicket,dismissal_type,dismissed_player_id,comp_id,comp_name,comp_tier,knock_out,target_runs,scheduled_balls,curr_runs_before,curr_wkts_before,legal_balls_before,under_pressure")
]


def copy_csv(cur, table, columns, csv_path):
    """Copy a CSV file into a PostgreSQL table using COPY FROM STDIN."""
    with open(csv_path, "r", newline="", encoding="utf-8") as f:
        # Skip header row
        next(csv.reader(f))
        sql = f"COPY {table} ({columns}) FROM STDIN WITH CSV"
        cur.copy_expert(sql, f)


def main():
    conn = psycopg2.connect(
        host=HOST,
        port=PORT,
        dbname=DBNAME,
        user=USER,
        password=PASSWORD,
    )
    cur = conn.cursor()
    # Optionally truncate before load (if re‑running)
    for tbl, cols in TABLES:
        print(f"Loading {tbl}...")
        cur.execute(f"TRUNCATE TABLE {tbl} RESTART IDENTITY CASCADE;")
        csv_file = CSV_ROOT / f"{tbl}.csv"
        if not csv_file.exists():
            raise FileNotFoundError(f"CSV not found: {csv_file}")
        copy_csv(cur, tbl, cols, csv_file)
        conn.commit()
        print(f"Loaded {tbl} from {csv_file}")
    cur.close()
    conn.close()
    print("All tables loaded successfully.")

if __name__ == "__main__":
    main()
