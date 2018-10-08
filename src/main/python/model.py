from pprint import pprint
import arviz as az
from datalayer import load_lineups, load_games, load_player_stats
from pystan import StanModel
import numpy as np
import pandas as pd
import math
import logging
np.set_printoptions(linewidth=300)
tournament = 'Veikkausliiga'
sport_name = 'Jalkapallo'
expected_players_per_team = 11
lineups = load_lineups("Veikkausliiga")
max_oos_games = 15


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


def make_game_data(lineups):
    game_data = lineups.groupby(['game_id']).apply(lambda a: make_players_vector(a, expected_players_per_team))
    nrow = game_data.shape[0]
    ncol = game_data[0].shape[0]
    game_data_matrix = np.concatenate(game_data.values).reshape((nrow,ncol))
    return game_data_matrix, game_data.index


def make_oos_lineup(row, games, lineups):
    def find_lineup(team):
        most_recent_game = games[
            (games['home_team'] == team).values |
            (games['away_team'] == team).values
        ].sort_values('game_date', ascending=False).head(1)
        most_recent_game_id = str(most_recent_game['game_id'].values[0])
        lineup = lineups[(lineups['game_id'] == most_recent_game_id).values & (lineups['team'] == team).values]
        return lineup


    game_id = str(row['game_id'].values[0])
    existing = lineups[lineups['game_id'] == game_id]
    if existing.shape[0] != 0:
        return existing
    ht = str(row['home_team'].values[0])
    at = str(row['away_team'].values[0])
    ht_lineup = find_lineup(ht)
    ht_lineup['team_type'] = 'home'
    at_lineup = find_lineup(at)
    at_lineup['team_type'] = 'away'
    res = pd.concat((ht_lineup, at_lineup))
    res['game_id'] = game_id
    res['team_type']
    return res


def make_oos_lineups(oos_games, games, lineups):
    res = oos_games.groupby('game_id').apply(lambda a: make_oos_lineup(a, games, lineups))
    return pd.DataFrame(res.values, columns=res.columns)

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

player_stats = load_player_stats("Veikkausliiga")

player_ids = list(set(lineups['player_id']))
lineups = set_indices(lineups, 'player_id', player_ids)
player_stats = set_indices(player_stats, 'player_id', player_ids)
player_stats = player_stats[player_stats['player_id_index'].apply(lambda a: a is not None)]
mask = player_stats['goals'] > player_stats['shots']
player_stats.loc[mask, 'shots'] = player_stats[mask]['goals']



game_data, game_data_index = make_game_data(lineups)
oos_lineups = make_oos_lineups(oos_games, all_games, lineups)
oos_game_data, oos_game_data_index = make_game_data(oos_lineups)

stan_data = {
    'n_players': player_stats.shape[0],
    'goals': player_stats['goals'].values,
    'shots': player_stats['shots'].values,
    'games': player_stats['games'].values
}

stan_model = StanModel(
    'src/main/stan/player_scoring.stan'
)

samples = stan_model.sampling(
    stan_data,
    iter=5000,
    chains=4,
    refresh=1,
    control={
        'adapt_delta': 0.99,
        'max_treedepth': 15
    }
)



lambdas = samples.extract('lambda')['lambda']
probs = samples.extract('probability')['probability']
lmeans = np.apply_along_axis(np.mean, 0, lambdas)
pmeans = np.apply_along_axis(np.mean, 0, probs)
player_expected = pd.DataFrame(
    lmeans * pmeans, index=player_stats['player_id']
)
player_expected_sorted = player_expected.loc[player_ids].values.squeeze()
cutoff = int(game_data.shape[1] / 2)
home_player_e = np.apply_along_axis(
    np.sum,
    1,
    player_expected_sorted[game_data][::,0:11]
)
away_player_e = np.apply_along_axis(
    np.sum,
    1,
    player_expected_sorted[game_data][::, cutoff::]
)
player_es = pd.DataFrame(np.stack((home_player_e, away_player_e), axis=1),
                         index=game_data_index)
games = pd.merge(games, player_es, on = 'game_id')

