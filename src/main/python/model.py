import arviz as az
from player_model import SimplePlayerModel
from dummies import make_team_dummies
from rankings import make_rankings
import numpy as np
from datalayer import make_games_data, make_game_data, make_oos_lineups, make_player_stats
from bnb import find_probabilities

np.set_printoptions(linewidth=300)

tournament = 'Liiga'
sport_name = 'Jääkiekko'
expected_players_per_team = 42
max_oos_games = 15

games, oos_games, lineups = make_games_data(
    sport_name=sport_name,
    tournament=tournament,
    max_oos_games=max_oos_games
)
games.set_index('game_id', inplace=True)
oos_games.set_index('game_id', inplace=True)
game_data = make_game_data(lineups, expected_players_per_team=expected_players_per_team)
oos_lineups = make_oos_lineups(oos_games, games, lineups)
oos_lineups['game_id'] = oos_lineups.index
oos_game_data = make_game_data(oos_lineups, expected_players_per_team=expected_players_per_team)

player_stats = make_player_stats(tournament, list(set(lineups['player_id'])))
simple_model = SimplePlayerModel(model_name='ebin_Malli', player_stats=player_stats)
simple_model.load_or_fit()
simple_model.save()

team_expectations = simple_model.find_team_expectations(game_data)
oos_team_expectations = simple_model.find_team_expectations(oos_game_data)
games_with_rank, oos_games_with_rank = make_rankings(games, oos_games)
games_with_rank = games_with_rank[['home_team_adv', 'home_team_adv_sq']]
oos_games_with_rank = oos_games_with_rank[['home_team_adv', 'home_team_adv_sq']]

dataset = games.join(team_expectations).join(games_with_rank)
oos_dataset = oos_games.join(oos_team_expectations).join(oos_games_with_rank)
results = find_probabilities(dataset, oos_dataset)

