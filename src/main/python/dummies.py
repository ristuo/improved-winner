from keras.utils import to_categorical


def make_team_dummies(games):
    team_dummies = games[["home_team_index", "away_team_index"]] - 1
    team_cats = to_categorical(team_dummies)
    return team_cats[::, ::, 1:]
