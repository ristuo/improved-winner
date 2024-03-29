from pystan import StanModel
import pytz
import numpy as np
from scipy.special import loggamma
from model.dummies import make_team_dummies, make_goalie_dummies

np.set_printoptions(precision=2, suppress=True)
tz = pytz.timezone('Europe/Helsinki')


def bnb_prob(y, mu, a, phi):
    ai = 1.0 / a
    ai_mu = np.multiply(ai, mu)
    theta = 1 / (ai + 1)
    c = np.power((1 - theta) / (1 - theta * np.exp(-1)), ai_mu)
    fst = loggamma(y + ai_mu) - loggamma(y + 1) - loggamma(ai_mu)
    snd = y * np.log(1.0 / (ai + 1))
    trd = ai_mu * np.log(ai / (ai + 1))
    frt = np.log(1 + phi * np.multiply((np.exp(-y[::,0]) - c[0]),
                                       (np.exp(-y[::,1]) -c[1])))
    return np.exp(np.sum(fst + snd + trd) + frt)


def find_game_probabilities(mu, a, phi, max_goals = 10):
    res = np.zeros((max_goals * max_goals, 3))
    np.set_printoptions(precision=3, suppress = True,
                        floatmode = "fixed", linewidth=200)
    for i in range(0, max_goals):
        for j in range(0, max_goals):
            row_index = 10 * i + j
            y = np.array([[i, j]])
            res[row_index, 0] = i
            res[row_index, 1] = j
            res[row_index, 2] = bnb_prob(y, mu, a, phi)
    return res


def extract_data(dataset):
    n_rows, n_cols = dataset.shape
    Y_data = dataset[['home_team_goals', 'away_team_goals']].values
    ratings_data = dataset[['home_team_adv']]\
        .values.reshape(n_rows, 1, 1)
    expectations_data = dataset[['home_expected', 'away_expected']]\
        .values.reshape(n_rows, 2)
    team_dummies_data = make_team_dummies(dataset)
    pct = dataset[['home_pct', 'away_pct']].values
    return Y_data, ratings_data, expectations_data, team_dummies_data, pct


def normalize(mat, oos_mat):
    mean = np.mean(mat)
    sd = np.std(mat)
    return (mat - mean) / sd, (oos_mat - mean) / sd


def bnb_stan(dataset, oos_dataset, warmup=20000, n_iter=25000):
    Y_data, ratings_data, expectations_data, team_dummies_data, pct = (
        extract_data(dataset))
    _, oos_ratings_data, oos_expectations_data, oos_team_dummies_data, oos_pct = \
        extract_data(oos_dataset)
    ratings_data = ratings_data.squeeze()
    oos_ratings_data = oos_ratings_data.squeeze()
    ratings_data, oos_ratings_data = normalize(ratings_data, oos_ratings_data)
    ratings_data = np.stack(
        (ratings_data, np.square(ratings_data)),
        axis=1)
    oos_ratings_data = np.stack(
        (oos_ratings_data, np.sign(oos_ratings_data) * np.square(oos_ratings_data)),
        axis=1)
    pct, oos_pct = normalize(pct, oos_pct)
    expectations_data, oos_expectations_data = normalize(
        expectations_data, oos_expectations_data)
    home_team_dummies = team_dummies_data[::, 0, ::]
    away_team_dummies = team_dummies_data[::, 1, ::]
    stan_data = {
        'n_rows': Y_data.shape[0],
        'n_teams': team_dummies_data.shape[2],
        'm_ratings': ratings_data.shape[1],
        'max_goals': 10,
        'home_team_dummies': home_team_dummies,
        'away_team_dummies': away_team_dummies,
        'expectations': expectations_data,
        'pct': pct,
        'ratings': ratings_data,
        'Y': Y_data.astype(np.int16),
        'oos_n_rows': oos_ratings_data.shape[0],
        'oos_home_team_dummies': oos_team_dummies_data[::, 0,::],
        'oos_away_team_dummies': oos_team_dummies_data[::, 1,::],
        'oos_expectations': oos_expectations_data,
        'oos_ratings': oos_ratings_data,
        'oos_pct': oos_pct
    }
    stan_model = StanModel(
        '../stan/games.stan'
    )
    samples = stan_model.sampling(
        stan_data,
        warmup=warmup,
        iter=n_iter,
        chains=4,
        refresh=1,
        control={'adapt_delta': 0.99, 'max_treedepth': 15}
    )
    preds = samples['predicted_probabilities']
    mean_preds = np.mean(preds,axis=0)
    return samples, mean_preds

