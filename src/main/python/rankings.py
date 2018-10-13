from rankit.Table import Table
import numpy as np
from rankit.Ranker import MarkovRanker


def _set_adv_variables(games):
    games['home_team_adv'] = (
        games['home_team_rating'] - games['away_team_rating']
    )
    games['home_team_adv_sq'] = np.sign(games['home_team_adv']) * np.power(games['home_team_adv'], 2)


def make_rankings(games, oos_games, ranker_start = 30):
    games = games.copy()
    oos_games = oos_games.copy()

    ds = games[0:ranker_start]
    data = Table(ds, ['home_team', 'away_team', 'home_team_goals', 'away_team_goals'])
    ranker = MarkovRanker(data)
    current_ranks = ranker.rank()
    current_ranks = current_ranks[['name', 'rating']]
    res = ds.merge(current_ranks, how='left', left_on='home_team', right_on='name')
    res = res.rename(columns={'rating': 'home_team_rating'})
    res = res.drop('name', axis=1)
    res = res.merge(current_ranks, how='left', left_on='away_team', right_on='name')
    res = res.rename(columns={'rating': 'away_team_rating'})
    res = res.drop('name', axis=1)

    games['home_team_rating'] = np.NaN
    games['away_team_rating'] = np.NaN


    games['home_team_rating'][0:ranker_start] = res['home_team_rating']
    games['away_team_rating'][0:ranker_start] = res['away_team_rating']
    oos_games['home_team_rating'] = np.NaN
    oos_games['away_team_rating'] = np.NaN

    def set_ranks(ht, at, i, games, crank_dict):
        mean_rating = np.mean(list(crank_dict.values()))
        if ht in crank_dict:
            games['home_team_rating'][i] = crank_dict[ht]
        else:
            games['home_team_rating'][i] = mean_rating
        if at in crank_dict:
            games['away_team_rating'][i] = crank_dict[at]
        else:
            games['away_team_rating'][i] = mean_rating
    upto = games.shape[0]
    for i in range(ranker_start, upto):
        ht = str(games['home_team'][i])
        at = str(games['away_team'][i])
        crank_dict = dict(list(current_ranks.values))
        set_ranks(ht, at, i, games, crank_dict)
        data = Table(games[0:i], ['home_team', 'away_team', 'home_team_goals', 'away_team_goals'])
        ranker = MarkovRanker(data)
        current_ranks = ranker.rank()[['name', 'rating']]

    for i in range(0, oos_games.shape[0]):
        ht = str(oos_games['home_team'][i])
        at = str(oos_games['away_team'][i])
        set_ranks(ht, at, i, oos_games, crank_dict)

    _set_adv_variables(games)
    _set_adv_variables(oos_games)
    return games, oos_games

