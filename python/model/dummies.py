from keras.utils import to_categorical

def _make_dummies(df, variables, num_classes=None):
    dummies = df[variables]
    cats = to_categorical(dummies, num_classes=num_classes)
    return cats[..., 1:]

def make_team_dummies(games):
    return _make_dummies(games, ["home_team_index", "away_team_index"])


def make_goalie_dummies(dataset, n_goalies):
    return _make_dummies(
        dataset,
        ['home_goalie_index', 'away_goalie_index'],
        n_goalies)
