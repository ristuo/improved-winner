from model.player_model import SimplePlayerModel
from model.util import home_and_away_join
import pandas as pd
from model.rankings import make_rankings
import numpy as np
from model.bnb import bnb_stan
from datalayer.datalayer import make_games_data, make_game_data, make_oos_lineups, \
    make_player_stats, write_preds_to_db, set_indices, goalie_stats_load, is_not_goalie

pd.set_option('display.width', 250)
pd.set_option('display.max_columns', 20)

np.set_printoptions(linewidth=300)

tournament = 'Liiga'
sport_name = 'Jääkiekko'
expected_players_per_team = 19
max_oos_games = 20
games, oos_games, lineups = make_games_data(
    sport_name=sport_name,
    tournament=tournament,
    max_oos_games=max_oos_games
)
games.set_index('game_id', inplace=True)
oos_games.set_index('game_id', inplace=True)
non_goalie_lineups = lineups[is_not_goalie(lineups)]
game_data = make_game_data(non_goalie_lineups, expected_players_per_team=expected_players_per_team)
oos_lineups = make_oos_lineups(oos_games, games, lineups)
oos_non_goalie_lineups = oos_lineups[is_not_goalie(oos_lineups)]
oos_lineups['game_id'] = oos_lineups.index
oos_game_data = make_game_data(oos_non_goalie_lineups, expected_players_per_team=expected_players_per_team)

goalies, oos_goalies = goalie_stats_load(tournament, sport_name, lineups, oos_lineups)
with_pct = home_and_away_join(games, goalies, 'pct')
with_pct.set_index('game_id', inplace=True)
oos_with_pct = home_and_away_join(oos_games, oos_goalies, 'pct')
oos_with_pct.set_index('game_id', inplace=True)

player_stats = make_player_stats(tournament, lineups)
assert player_stats.shape[0] == player_stats.index.unique().shape[0], "Player id is not unique in player_stats!"
player_id_to_index = lineups[['player_id', 'player_id_index']].drop_duplicates()
player_id_to_index.set_index('player_id', inplace=True)
player_stats = player_stats.join(player_id_to_index, how='inner')
player_stats = player_stats[(player_stats['player_position'] != 'goalies') & (player_stats['player_position'] != 'goalie')]
player_stats = set_indices(player_stats, 'player_position')
simple_model = SimplePlayerModel(model_name='ebin_Malli_2', player_stats=player_stats)
simple_model.fit(iterations=3000)

team_expectations = simple_model.find_team_expectations(game_data)
oos_team_expectations = simple_model.find_team_expectations(oos_game_data)
games_with_rank, oos_games_with_rank = make_rankings(games, oos_games)
games_with_rank = games_with_rank[['home_team_adv', 'home_team_adv_sq']]
oos_games_with_rank = oos_games_with_rank[['home_team_adv', 'home_team_adv_sq']]
dataset = with_pct.join(team_expectations).join(games_with_rank)
oos_dataset = oos_with_pct.join(oos_team_expectations).join(oos_games_with_rank)

samples, mean_preds = bnb_stan(dataset, oos_dataset,n_iter=6000)
write_preds_to_db(oos_dataset=oos_dataset, mean_preds=mean_preds, tournament=tournament, sport_name=sport_name)
