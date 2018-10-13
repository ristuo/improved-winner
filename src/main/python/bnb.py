import tensorflow as tf
import matplotlib.pyplot as plt
import numpy as np
from scipy.special import gamma
import pandas as pd
from keras.utils import to_categorical
from tensorflow.train import GradientDescentOptimizer, AdamOptimizer
from dummies import make_team_dummies

def broadcast_matmul(A, B):
    "Compute A @ B, broadcasting over the first `N-2` ranks"
    with tf.variable_scope("broadcast_matmul"):
        return tf.reduce_sum(A[..., tf.newaxis] * B[..., tf.newaxis, :, :],
                             axis=-2)


def bnb(dataset):
    n_rows, n_cols = dataset.shape
    Y_data = dataset[['home_team_goals', 'away_team_goals']].values
    ratings_data = dataset[['home_team_adv', 'home_team_adv_sq']].values.reshape(n_rows,1,2)
    expectations_data = dataset[['home_expected', 'away_expected']].values.reshape(n_rows,2)
    team_dummies_data = make_team_dummies(dataset)

    team_defence_initial = np.random.randn(team_dummies_data.shape[2], 1)
    team_attack_initial = np.random.randn(team_dummies_data.shape[2], 1)
    means_initial = np.array([[0.5, 0.3]])
    phi_initial = 0.5
    a_initial = np.random.rand(2)

    # parameters
    team_dummies = tf.placeholder(shape=team_dummies_data.shape, dtype=tf.float32, name='team_dummies')
    Y = tf.placeholder(shape=Y_data.shape, dtype=tf.float32, name='Y')
    ratings = tf.placeholder(shape=ratings_data.shape, dtype=tf.float32, name='ratings')
    expectations = tf.placeholder(shape=expectations_data.shape, dtype=tf.float32, name='expectations')

    team_attack = tf.Variable(team_attack_initial, name = 'team_attack', dtype = tf.float32)
    team_defence = tf.Variable(team_defence_initial, name='team_defences', dtype=tf.float32)
    means = tf.Variable(means_initial, name="home_mean", dtype=tf.float32)
    phi = tf.Variable(phi_initial, name="phi", dtype=tf.float32)
    theta = tf.Variable(0.34, name='theta', dtype=tf.float32)
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
    #mu = tf.exp(means + ratings_coeff + expectations_coeff + team_attack_coeff + team_defence_coeff)
    mu = tf.exp(means)

    a_inv_mu = a_inv * mu
    c = tf.pow(((1.0 - theta) / (1 - theta * 0.3678794)), a_inv_mu)
    exp_y_minus_c = tf.exp((-1) * Y) - c
    spesiaali = tf.multiply(phi, tf.multiply(exp_y_minus_c[::, 0], exp_y_minus_c[::, 1]))

    log_likelihoods = tf.reduce_sum(
        tf.lgamma(Y + a_inv_mu) - tf.lgamma(Y + 1) - tf.lgamma(a_inv_mu) - tf.multiply(Y, tf.log(a_inv + 1)) +
        tf.multiply(a_inv_mu, tf.log(a_inv) - tf.log(1 + a_inv)),
        axis=1
    ) + tf.log(1 + spesiaali)
    cost = (-1) * tf.reduce_sum(log_likelihoods)


    optimizer = GradientDescentOptimizer(learning_rate=0.000001)
    #optimizer =  AdamOptimizer(learning_rate = 0.0005)
    train = optimizer.minimize(cost)

    feed_dict = {
        expectations: expectations_data,
        ratings: ratings_data,
        team_dummies: team_dummies_data,
        Y: Y_data
    }
    with tf.Session() as sess:
        sess.run(tf.global_variables_initializer())
        for i in range(0, 12000):
            sess.run(train, feed_dict=feed_dict)
            res = sess.run(
                [cost, mu, expectations_coeff, phi, a],
                feed_dict=feed_dict
            )
            if i % 500 == 0:
                print("Iteration: " + str(i) + ", cost: " + str((-1) * res[0]))
                print(res[1])


