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
expected_players_per_team = 21
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


player_stats = make_player_stats(tournament)
assert player_stats.shape[0] == player_stats.index.unique().shape[0], "Player id is not unique in player_stats!"
player_id_to_index = lineups[['player_id', 'player_id_index']].drop_duplicates()
player_id_to_index.set_index('player_id', inplace=True)
player_stats = player_stats.join(player_id_to_index, how='inner')



simple_model = SimplePlayerModel(model_name='ebin_Malli_2', player_stats=player_stats)
simple_model.load_or_fit()

team_expectations = simple_model.find_team_expectations(game_data)
oos_team_expectations = simple_model.find_team_expectations(oos_game_data)

games_with_rank, oos_games_with_rank = make_rankings(games, oos_games)
games_with_rank = games_with_rank[['home_team_adv', 'home_team_adv_sq']]
oos_games_with_rank = oos_games_with_rank[['home_team_adv', 'home_team_adv_sq']]

dataset = games.join(team_expectations).join(games_with_rank)
oos_dataset = oos_games.join(oos_team_expectations).join(oos_games_with_rank)


dataset.head()
oos_dataset.head()
oos_dataset.loc['runkosarja_2018-2019_90']

dataset[dataset['home_team_index'] == 6]['home_team']


results = find_probabilities(dataset, oos_dataset)


self = simple_model
oos_games
oos_team_expectations
oos_games_with_rank

game_id = 'runkosarja_2018-2019_90'
game_df = results[results['game_id'] == game_id]
p_home_win = np.sum(game_df.loc[game_df['home_team_goals'] > game_df['away_team_goals'], 'p'])
p_away_win = np.sum(game_df.loc[game_df['home_team_goals'] < game_df['away_team_goals'], 'p'])
p_draw = np.sum(game_df.loc[game_df['home_team_goals'] == game_df['away_team_goals'], 'p'])
p_home_win
p_draw
p_away_win


import matplotlib.pyplot as plt
# This import registers the 3D projection, but is otherwise unused.
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401 unused import
fig = plt.figure(figsize=(8, 3))
ax1 = fig.add_subplot(121, projection='3d')

x = game_df['home_team_goals'].values
y = game_df['away_team_goals'].values
top = game_df['p'].values
width = depth = 1
bottom = np.zeros_like(top)
ax1.bar3d(x, y, bottom, width, depth, top, shade=True)
ax1.set_title('Shaded')

plt.show()

