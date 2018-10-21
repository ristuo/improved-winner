import psycopg2
import pgutil.db
import pandas as pd
import os
import logging
import math
import numpy as np

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
    res = _get_as_df(qs)
    if tournament == 'Liiga':
       _set_liiga_game_id(res)
    return res

def _load_liiga_player_stats():
    qs = '''
    SELECT
      sum(shots) as shots,
      sum(goals) as goals,
      sum(games) as games,
      player_id
    FROM
      liiga_player_stats
    WHERE
      season > '2015'
    GROUP BY
      player_id
    '''
    res = _get_as_df(qs)
    return res


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


def find_index(row_id, ids_list):
    try:
        return ids_list.index(row_id)
    except ValueError:
        return None


def set_indices(df, index_col, ids_list = None, logger = None):
    if logger is None:
        logger = logging.getLogger()
    if ids_list is None:
        ids_list = list(set(df[index_col]))
    result_col_name = index_col + '_index'
    df.loc[:, result_col_name] = df[index_col].apply(lambda a: find_index(a, ids_list))
    nrow_before_filtering, _ = df.shape
    df = df[df[result_col_name].apply(lambda a: not math.isnan(a))]
    nrow_after_filtering, _ = df.shape
    if nrow_before_filtering != nrow_after_filtering:
        logger.warning('Trouble with setting index ' + index_col + ' using ' +
                        ', '.join(ids_list[0:10]) + ' ..., namely ' +
                       ' could not find index for ' + str(nrow_before_filtering - nrow_after_filtering) + ' rows!' +
                       ' They were filtered out.')
    df[result_col_name] = df[result_col_name].astype(int)
    return df


def make_players_vector(players, expected_length):
    def paddy(x):
        res = np.repeat(-1, expected_length)
        res[0:x.shape[0]] = x
        return res
    home_players = paddy(players[players['team_type'] == 'home']['player_id_index'].values)
    away_players = paddy(players[players['team_type'] == 'away']['player_id_index'].values)
    return np.concatenate((home_players, away_players))


def make_game_data(lineups, expected_players_per_team):
    game_data = lineups.groupby(['game_id']).apply(lambda a: make_players_vector(a, expected_players_per_team))
    nrow = game_data.shape[0]
    ncol = game_data[0].shape[0]
    game_data_matrix = np.concatenate(game_data.values).reshape((nrow,ncol))
    return pd.DataFrame(game_data_matrix, index=game_data.index)


def make_oos_lineup(row, games, lineups):
    def find_lineup(team):
        most_recent_game = games[
            (games['home_team'] == team).values |
            (games['away_team'] == team).values
        ].sort_values('game_date', ascending=False).head(1)
        most_recent_game_id = str(most_recent_game.index.values[0])
        lineup = lineups[(lineups['game_id'] == most_recent_game_id).values & (lineups['team'] == team).values]
        return lineup
    game_id = str(row['game_id'])
    existing = lineups[lineups['game_id'] == game_id]
    if existing.shape[0] != 0:
        return existing
    ht = str(row['home_team'])
    at = str(row['away_team'])
    ht_lineup = find_lineup(ht)
    ht_lineup['team_type'] = 'home'
    at_lineup = find_lineup(at)
    at_lineup['team_type'] = 'away'
    res = pd.concat((ht_lineup, at_lineup))
    res['game_id'] = game_id
    res['team_type']
    return res


def make_oos_lineups(oos_games, games, lineups):
    x = oos_games.copy()
    x['game_id'] = x.index
    res = x.apply(lambda a: make_oos_lineup(a, games, lineups), axis=1)
    res = pd.concat(list(res))
    res.set_index('game_id', inplace=True)
    return res

def make_games_data(sport_name, tournament, max_oos_games, logger = None):
    """
    Finds games (separated to out of sample ones and already player out ones) and lineups.

    This has to be a single function because lineups are needed for filtering games
    :param sport_name: "Jalkapallo" or "Jääkiekko".
    :param tournament: "Veikkausliiga" or "Liiga".
    :param logger: A logger.
    :return: games, oos_games and lineups, all being pandas dataframes.
    """
    lineups = load_lineups(tournament)
    all_games, oos = load_games(sport_name = sport_name, tournament=tournament)
    teams = list(set(all_games['home_team']).union(all_games['away_team']))
    oos_games = oos[0:(max_oos_games - 1)]
    all_games = set_indices(all_games, 'home_team', teams)
    all_games = set_indices(all_games, 'away_team', teams)
    oos_games = set_indices(oos_games, 'home_team', teams)
    oos_games = set_indices(oos_games, 'away_team', teams)
    oos_games = oos_games.reset_index()
    game_ids = set(all_games['game_id']).intersection(set(lineups['game_id']))
    games = all_games[all_games['game_id'].isin(game_ids)]
    games = games.reset_index()
    lineups = lineups[lineups['game_id'].isin(game_ids)]
    lineups = set_indices(lineups, 'player_id', list(set(lineups['player_id'])))
    lineups.reset_index()
    return (games, oos_games, lineups)


def make_player_stats(tournament):
    """
    Load player statistics, make sure goals at least equals shots and set indices according to players in lineups.

    Player not in lineups won't be included.
    :param tournament:
    :param lineups:
    :return:
    """
    player_stats = load_player_stats(tournament)
    player_stats.set_index('player_id', inplace=True)
    mask = player_stats['goals'] > player_stats['shots']
    player_stats.loc[mask, 'shots'] = player_stats[mask]['goals']
    return player_stats


def write_preds_to_db(oos_dataset, mean_preds, logger=None):
    if logger is None:
        logger = logging.getLogger()
    rows = []
    newest_dl_time = np.max(oos_dataset['dl_time'])
    model_name = 'BNB1-v1'
    for game_index in range(0, oos_dataset.shape[0]):
        game = oos_dataset.iloc[game_index]
        upload_time = datetime.now(tz)
        game_id = game.name
        predictions_matrix = mean_preds[game_index, ::, ::]
        n, m = predictions_matrix.shape
        for i in range(0, n):
            for j in range(0, m):
                home_team_score = i
                away_team_score = j
                probability = predictions_matrix[i, j]
                d = {
                    'upload_time': upload_time,
                    'game_id': game_id,
                    'newest_dl_time': newest_dl_time,
                    'home_team_score': home_team_score,
                    'away_team_score': away_team_score,
                    'probability': probability,
                    'model_name': model_name
                }
                rows.append(d)
    conn = pgutil.db.get_db_connection('betting')
    try:
        pgutil.db.write_to_table(conn=conn, table_name='predictions', logger=logger, dict_list=rows)
    finally:
        conn.close()
        game_id

