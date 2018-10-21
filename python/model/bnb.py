import tensorflow as tf
from pystan import StanModel
import logging
from datetime import datetime
import pytz
tz=pytz.timezone('Europe/Helsinki')
import numpy as np
from scipy.special import loggamma
import pandas as pd
import pgutil.db
from tensorflow.train import AdamOptimizer
from model.dummies import make_team_dummies
np.set_printoptions(precision=2, suppress=True)

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
    max_goals = 10
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



def broadcast_matmul(A, B):
    "Compute A @ B, broadcasting over the first `N-2` ranks"
    with tf.variable_scope("broadcast_matmul"):
        return tf.reduce_sum(A[..., tf.newaxis] * B[..., tf.newaxis, :, :],
                             axis=-2)


def extract_data(dataset):
    n_rows, n_cols = dataset.shape
    Y_data = dataset[['home_team_goals', 'away_team_goals']].values
    ratings_data = dataset[['home_team_adv', 'home_team_adv_sq']].values.reshape(n_rows,1,2)
    expectations_data = dataset[['home_expected', 'away_expected']].values.reshape(n_rows,2)
    team_dummies_data = make_team_dummies(dataset)
    return Y_data, ratings_data, expectations_data, team_dummies_data

def normalize(mat, oos_mat):
    mean = np.mean(mat)
    sd = np.std(mat)
    return (mat - mean) / sd, (oos_mat - mean) / sd


def bnb_stan(dataset, oos_dataset):
    Y_data, ratings_data, expectations_data, team_dummies_data = extract_data(dataset)
    _, oos_ratings_data, oos_expectations_data, oos_team_dummies_data = \
        extract_data(oos_dataset)
    ratings_data = ratings_data.squeeze()
    oos_ratings_data = oos_ratings_data.squeeze()
    ratings_data, oos_ratings_data = normalize(ratings_data, oos_ratings_data)
    expectations_data, oos_expectations_data = normalize(expectations_data, oos_expectations_data)
    home_team_dummies = team_dummies_data[::,0, ::]
    away_team_dummies = team_dummies_data[::,1, ::]
    stan_data = {
        'n_rows': Y_data.shape[0],
        'n_teams': team_dummies_data.shape[2],
        'm_ratings': ratings_data.shape[1],
        'max_goals': 10,
        'home_team_dummies': home_team_dummies,
        'away_team_dummies': away_team_dummies,
        'expectations': expectations_data,
        'ratings': ratings_data,
        'Y': Y_data.astype(np.int16),
        'oos_n_rows': oos_ratings_data.shape[0],
        'oos_home_team_dummies': oos_team_dummies_data[::,0,::],
        'oos_away_team_dummies': oos_team_dummies_data[::,1,::],
        'oos_expectations': oos_expectations_data,
        'oos_ratings': oos_ratings_data
    }
    stan_model = StanModel(
        '/home/risto/Code/hobbies/veikkausliiga/src/main/stan/game_model.stan'
    )
    init_list = [
        {
            'phi': 0.5,
            'a': [0.12, 0.11]
        },
        {
            'phi': -0.3,
            'a': [0.43, 0.03]
        },
        {
            'phi': 0.45,
            'a': [0.23, 0.15]

        },
        {
            'phi': -0.9,
            'a': [0.3, 0.53]
        }
    ]
    samples = stan_model.sampling(
        stan_data,
        iter=1000,
        chains=4,
        refresh=1,
        init=init_list,
        control={'adapt_delta': 0.99, 'max_treedepth': 15}
    )
    preds = samples['predicted_probabilities']
    mean_preds = np.mean(preds,axis=0)
    return samples, mean_preds

def write_preds_to_db(oos_dataset, mean_preds, logger=None):
    if logger is None:
        logger = logging.getLogger()
    rows = []
    newest_dl_time = np.max(oos_dataset['dl_time'])
    model_name = 'BNB1-v1'
    for game_index in range(0, oos_dataset.shape[0]):
        game = oos_dataset.iloc[game_index]
        upload_time = datetime.now(tz)
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
                    'model_name': model_name
                }
                rows.append(d)
    conn = pgutil.db.get_db_connection('betting')
    try:
        pgutil.db.write_to_table(conn=conn, table_name='predictions', logger=logger, dict_list=rows)
    finally:
        conn.close()
        game_id


def bnb_predict(dataset, oos_dataset, convergence_epsilon = 0.01, iterations = 250000, logger = None):
    if logger is None:
        logger = logging.getLogger()

    Y_data, ratings_data, expectations_data, team_dummies_data = extract_data(dataset)
    _, oos_ratings_data, oos_expectations_data, oos_team_dummies_data = \
        extract_data(oos_dataset)
    ratings_data, oos_ratings_data = normalize(ratings_data, oos_ratings_data)
    expectations_data, oos_expectations_data = \
        normalize(expectations_data, oos_expectations_data)

    team_defence_initial = np.random.randn(team_dummies_data.shape[2], 1)
    team_attack_initial = np.random.randn(team_dummies_data.shape[2], 1)
    means_initial = np.array([[0.5, 0.3]])
    phi_initial = 0.5
    a_initial = np.random.rand(2)



    # parameters
    team_dummies = tf.placeholder(shape=(None, *team_dummies_data.shape[1:]),
                                  dtype=tf.float32, name='team_dummies')
    Y = tf.placeholder(shape=(None, *Y_data.shape[1:]), dtype=tf.float32, name='Y')
    ratings = tf.placeholder(shape=(None, *ratings_data.shape[1:]), dtype=tf.float32, name='ratings')
    expectations = tf.placeholder(shape=(None, *expectations_data.shape[1:]), dtype=tf.float32, name='expectations')

    team_attack = tf.Variable(team_attack_initial, name = 'team_attack', dtype = tf.float32)
    team_defence = tf.Variable(team_defence_initial, name='team_defences', dtype=tf.float32)
    means = tf.Variable(means_initial, name="home_mean", dtype=tf.float32)
    phi = tf.Variable(phi_initial, name="phi", dtype=tf.float32)
    a = tf.exp(tf.Variable(a_initial, name="a", dtype=tf.float32))  # ,0.00001)
    a_inv = 1 / a

    expectations_beta_initial = np.random.randn(expectations_data.shape[1])
    ratings_beta_initial = np.random.randn(1, ratings_data.shape[2], Y_data.shape[1])


    ratings_beta = tf.Variable(ratings_beta_initial, name="beta", dtype=tf.float32)
    expectations_beta = tf.Variable(expectations_beta_initial,
                                    name="beta", dtype=tf.float32)
    ratings_coeff = tf.squeeze(broadcast_matmul(ratings, ratings_beta))
    expectations_coeff = expectations * expectations_beta
    team_attack_coeff = tf.squeeze(broadcast_matmul(team_dummies, team_attack))
    team_defence_coeff = tf.squeeze(broadcast_matmul(team_dummies, team_defence))
    mu = tf.exp(means + ratings_coeff + expectations_coeff + team_attack_coeff + team_defence_coeff)
    #mu = tf.exp(means)

    a_inv_mu = a_inv * mu
    theta = 1 / (a_inv + 1)
    c = tf.pow(((1.0 - theta) / (1 - theta * 0.3678794)), a_inv_mu)
    exp_y_minus_c = tf.exp((-1) * Y) - c
    spesiaali = tf.multiply(phi, tf.multiply(exp_y_minus_c[::, 0], exp_y_minus_c[::, 1]))

    log_likelihoods = tf.reduce_sum(
        tf.lgamma(Y + a_inv_mu) - tf.lgamma(Y + 1) - tf.lgamma(a_inv_mu) - tf.multiply(Y, tf.log(a_inv + 1)) +
        tf.multiply(a_inv_mu, tf.log(a_inv) - tf.log(1 + a_inv)),
        axis=1
    ) + tf.log(1 + spesiaali)
    log_likelihood = tf.reduce_sum(log_likelihoods)
    cost = (-1) * log_likelihood

    #optimizer =  AdamOptimizer(learning_rate = 0.00005)
    #optimizer = GradientDescentOptimizer(learning_rate=0.00001)
    optimizer = AdamOptimizer(learning_rate=0.0001)
    train = optimizer.minimize(cost)

    feed_dict = {
        expectations: expectations_data,
        ratings: ratings_data,
        team_dummies: team_dummies_data,
        Y: Y_data
    }
    logger.info('Starting to train a model')
    costs = []
    with tf.Session() as sess:
        sess.run(tf.global_variables_initializer())
        for i in range(0, iterations):
            sess.run(train, feed_dict=feed_dict)
            res = sess.run(
                [cost, mu, phi, a, team_attack, team_defence, ratings_beta],
                feed_dict=feed_dict
            )
            if i % 5000 == 0:
                costs.append(res[0])
                msg = ("Iteration: " + str(i) + "/" + str(iterations) +
                       ', cost: ' + str((-1) * res[0]))
                logger.info(msg)
            last_5_costs = costs[-5:]
            if len(costs) > 4 and np.abs(max(last_5_costs) - min(last_5_costs)) < convergence_epsilon:
                msg = (
                    'Reached convergence as last 5 costs have been' +
                    ' oscillating within ' + str(convergence_epsilon) +
                    ': ' + ', '.join(['{:.4f}'.format(x) for x in last_5_costs])
                )
                logger.info(msg)
                break
        logger.info('Final cost was ' + str(res[0]))
        oos_mu_hat = sess.run([mu], feed_dict={
            expectations: oos_expectations_data,
            ratings: oos_ratings_data,
            team_dummies: oos_team_dummies_data
        })[0]
    _, mu_hat, phi_hat, a_hat, team_attack_weights, team_defence_weights, ratings_beta = res
    return mu_hat, oos_mu_hat, phi_hat, a_hat


def find_stan_probs(samples):
    params = samples.extract(['oos_mu', 'a', 'phi'])
    samples.summary(['a'])
    a = np.mean(params['a'])
    np.quantile(a[::,0], np.arange(0,1,0.01))
    phi = np.mean(params['phi'])
    oos_mu = np.mean(params['oos_mu'], axis=0)
    x = find_game_probabilities(oos_mu[0,::], a=a,phi=phi)
    oos_mu.shape
    np.mean(oos_mu,axis=0)
    np.mean(a, axis=0)
    np.mean(phi)



def find_probabilities(dataset, oos_dataset):
    mu_hat, oos_mu_hat, phi_hat, a_hat = bnb_predict(dataset, oos_dataset)
    res = []
    game_ids = oos_dataset.index
    for i in range(0, oos_dataset.shape[0]):
        probs = find_game_probabilities(oos_mu_hat[i,::],
                                        a_hat, phi_hat)
        x = pd.DataFrame(probs, columns = ['home_team_goals', 'away_team_goals', 'p'])
        x['home_team_goals'] = x['home_team_goals'].apply(lambda a: int(a))
        x['away_team_goals'] = x['away_team_goals'].apply(lambda a: int(a))
        x['game_id'] = game_ids[i]
        res.append(x)
    return pd.concat(res)

