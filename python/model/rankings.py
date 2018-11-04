import numpy as np
import ranks.elo as elo


def _set_adv_variables(games):
    games['home_team_adv'] = (
        games['home_team_rating'] - games['away_team_rating']
    )
    games['home_team_adv_sq'] = np.sign(games['home_team_adv']) \
                                * np.power(games['home_team_adv'], 2)


def make_rankings(games, oos_games):
    df = games.copy()
    oos_df = oos_games.copy()
    conditions = [
        df['home_team_goals'].values > df['away_team_goals'],
        df['home_team_goals'].values < df['away_team_goals']
    ]
    choices = [df['home_team'].values, df['away_team'].values]
    df['result'] = np.select(conditions, choices, 'draw')
    elos, current_ratings = elo.compute(df, k=20)
    df = df.drop(columns=['result'])
    df['home_team_rating'] = elos[::, 0]
    df['away_team_rating'] = elos[::, 1]
    oos_df['home_team_rating'] = (
        oos_df['home_team'].apply(lambda a: current_ratings[a]))
    oos_df['away_team_rating'] = (
        oos_df['away_team'].apply(lambda a: current_ratings[a]))
    _set_adv_variables(df)
    _set_adv_variables(oos_df)
    return df, oos_df
