from model.player_model import SimplePlayerModel
import numpy as np
from model.rankings import make_rankings
from datetime import datetime
from datalayer.datalayer import make_games_data, make_game_data, make_oos_lineups, \
    make_player_stats, set_indices, goalie_stats_load, is_not_goalie
from pytz import timezone
tz = timezone('Europe/Helsinki')




def home_and_away_join(games, df, variable):
    with_goalies = games\
        .merge(df, left_on=['game_id', 'home_team'], right_on=['game_id', 'team'])\
        .drop('team', axis=1)\
        .rename(columns={variable: 'home_' + variable})\
        .merge(df, left_on=['game_id', 'away_team'], right_on=['game_id', 'team'])\
        .drop('team', axis=1) \
        .rename(columns={variable: 'away_' + variable})
    return with_goalies


def make_datasets(sport_name, tournament, max_oos_games,
                  expected_players_per_team,
                  cutoff_date=datetime.now().date()):
    games, oos_games, lineups = make_games_data(
        sport_name=sport_name,
        tournament=tournament,
        max_oos_games=max_oos_games,
        cutoff_date=cutoff_date
    )
    games.set_index('game_id', inplace=True)
    oos_games.set_index('game_id', inplace=True)
    non_goalie_lineups = lineups[is_not_goalie(lineups)]
    game_data = make_game_data(
        non_goalie_lineups,
        expected_players_per_team=expected_players_per_team)
    oos_lineups = make_oos_lineups(oos_games, games, lineups)
    oos_non_goalie_lineups = oos_lineups[is_not_goalie(oos_lineups)]
    oos_lineups['game_id'] = oos_lineups.index
    oos_game_data = make_game_data(
        oos_non_goalie_lineups,
        expected_players_per_team=expected_players_per_team)
    goalies, oos_goalies = goalie_stats_load(
        tournament, sport_name, lineups, oos_lineups)
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
    simple_model = SimplePlayerModel(
        model_name='ebin_Malli_2',
        player_stats=player_stats)
    simple_model.fit(iterations=3000)
    team_expectations = simple_model.find_team_expectations(game_data)
    oos_team_expectations = simple_model.find_team_expectations(oos_game_data)
    games_with_rank, oos_games_with_rank = make_rankings(games, oos_games)
    games_with_rank = games_with_rank[['home_team_adv', 'home_team_adv_sq']]
    oos_games_with_rank = oos_games_with_rank[['home_team_adv', 'home_team_adv_sq']]
    dataset = with_pct.join(team_expectations).join(games_with_rank)
    oos_dataset = oos_with_pct.join(oos_team_expectations).join(oos_games_with_rank)
    return dataset, oos_dataset


def predictions_to_rows(mean_preds, oos_dataset, sport_name, tournament):
    rows = []
    newest_dl_time = np.max(oos_dataset['dl_time'])
    model_name = 'BNB1-v1'
    upload_time = datetime.now(tz)
    for game_index in range(0, oos_dataset.shape[0]):
        game = oos_dataset.iloc[game_index]
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
                    'model_name': model_name,
                    'sport_name': sport_name,
                    'tournament': tournament
                }
                rows.append(d)
    return rows
