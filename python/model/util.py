from datalayer.datalayer import set_indices
def is_not_goalie(df):
    return (df['player_position'] != 'goalie') & (df['player_position'] != 'goalies')


def is_goalie(df):
    return ~is_not_goalie(df)

def make_goalies(lineups, oos_lineups):
    goalies = lineups[is_goalie(lineups)][['team', 'game_id', 'player_id']]
    oos_goalies = oos_lineups[is_goalie(oos_lineups)][['team', 'game_id', 'player_id']]

    def have_only_one_goalie(df):
        def pick_goalie(df):
            return df.iloc[0]['player_id']
        res = df.groupby(['team', 'game_id'], as_index=False).apply(pick_goalie).reset_index()
        res.columns = list(df.columns[:-1]) + ['player_id']
        return res
    goalies = have_only_one_goalie(goalies)
    oos_goalies = have_only_one_goalie(oos_goalies)
    goalies = set_indices(goalies, 'player_id')
    goalies = goalies.rename(columns={'player_id_index': 'goalie_index'})

    goalie_indices = goalies[['player_id', 'goalie_index']].drop_duplicates().reset_index()
    oos_goalies = oos_goalies.merge(goalie_indices, on='player_id')
    return goalies, oos_goalies

def set_goalies(games, goalies):
    with_goalies = games\
        .merge(goalies.drop('player_id', axis=1), left_on=['game_id', 'home_team'], right_on=['game_id', 'team'])\
        .drop('team',axis=1)\
        .rename(columns={'goalie_index': 'home_goalie_index'})\
        .merge(goalies.drop('player_id', axis=1), left_on=['game_id', 'away_team'], right_on=['game_id', 'team'])\
        .drop('team',axis=1)\
        .rename(columns={'goalie_index': 'away_goalie_index'})
    return with_goalies

