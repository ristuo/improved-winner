from datalayer.datalayer import set_indices




def home_and_away_join(games, df, variable):
    with_goalies = games\
        .merge(df, left_on=['game_id', 'home_team'], right_on=['game_id', 'team'])\
        .drop('team', axis=1)\
        .rename(columns={variable: 'home_' + variable})\
        .merge(df, left_on=['game_id', 'away_team'], right_on=['game_id', 'team'])\
        .drop('team', axis=1) \
        .rename(columns={variable: 'away_' + variable})
    return with_goalies

