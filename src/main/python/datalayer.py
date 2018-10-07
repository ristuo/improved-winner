import psycopg2
import pandas as pd
import os
import math

def _load_conf_from_env():
    username = os.environ["DB_USER"]
    password = os.environ["DB_PASSWORD"]
    host = os.environ["DB_HOST"]
    dbname = os.environ["DB_NAME"]
    port = int(os.environ['DB_PORT'])
    return {
        'user': username,
        'password': password,
        'host': host,
        'database': dbname,
        'port': port
    }

def _get_db_connection():
    conf = _load_conf_from_env()
    conn = psycopg2.connect(**conf)
    return conn

def _get_as_df(qs):
    conn = _get_db_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(qs)
        res = cursor.fetchall()
        colnames = [desc[0] for desc in cursor.description]
    finally:
        if cursor is not None:
            cursor.close()
        conn.close()
    return pd.DataFrame(res, columns=colnames)

def load_games(sport_name, tournament):
    qs = '''
        SELECT
            *
        FROM
            games
        WHERE
            sport_name='{}' AND
            tournament='{}'
        ORDER BY game_date
    '''.format(sport_name, tournament)
    res = _get_as_df(qs)
    res['home_team'] = res['home_team'].apply(lambda s: s.strip())
    res['away_team'] = res['away_team'].apply(lambda s: s.strip())
    games = res[res['home_team_goals'].apply(lambda a: not math.isnan(a))]
    oos = res[res['home_team_goals'].apply(lambda a: math.isnan(a))]
    return games, oos

def load_lineups(tournament):
    qs = '''
        SELECT 
            team,
            game_id,
            player_id,
            season,
            team_type,
            game_set
        FROM
            lineups 
        WHERE
            league='{}'
        '''.format(tournament)
    return _get_as_df(qs)

def _load_liiga_player_stats():
    qs = '''
    SELECT
      sum(shots) as shots,
      sum(goals) as goals,
      sum(games) as games,
      player_name as nimi,
      player_id
    FROM
      liiga_player_stats
    WHERE
      season > '2015'
    GROUP BY
      nimi,
      player_id
    '''
    return _get_as_df(qs)


def load_player_stats(tournament):
    if tournament == "Veikkausliiga":
        return _load_vl_player_stats()
    elif tournament == "Liiga":
        return _load_liiga_player_stats()
    else:
        raise RuntimeError("Unknown tournament " + tournament)

def _load_vl_player_stats():
  qs = '''
    SELECT
      sum(shots) as shots,
      sum(goals) as goals,
      sum(games) as games,
      nimi,
      player_id
    FROM veikkausliiga_player_stats
    WHERE
      season > '2015'
    GROUP BY
      nimi,
      player_id
  '''
  return _get_as_df(qs)


