import tensorflow as tf
import matplotlib.pyplot as plt
import numpy as np
from scipy.special import gamma
import pandas as pd
from keras.utils import to_categorical
from tensorflow.train import GradientDescentOptimizer, AdamOptimizer
from dummies import make_team_dummies
def bnb(dataset):
    Y_data = dataset[['home_team_goals', 'away_team_goals']].values
    ratings_data = dataset[['home_team_adv', 'home_team_adv_sq']].values
    goal_expectations_data = dataset[['home_expected', 'away_expected']].values.reshape(dataset.shape[0],2,1)
    team_dummies_data = make_team_dummies(dataset)

    team_defence_initial = np.random.randn(team_dummies_data.shape[2], 1)
    team_attack_initial = np.random.randn(team_dummies_data.shape[2], 1)
    home_mean_initial = 0.3
    away_mean_initial = 0.2
    phi_initial = 0.5
    a_initial = np.random.rand(2)

    # parameters
    team_dummies = tf.placeholder(shape=team_dummies_data.shape, dtype=tf.float32, name='team_dummies')
    Y = tf.placeholder(shape=Y_data.shape, dtype=tf.float32, name='Y')
    team_attack = tf.Variable(team_attack_initial, name = 'team_attack', dtype = tf.float32)
    team_defence = tf.Variable(team_defence_initial, name='team_defences', dtype=tf.float32)
    home_mean = tf.Variable(home_mean_initial, name="home_mean", dtype=tf.float32)
    away_mean = tf.Variable(away_mean_initial, name="away_mean", dtype=tf.float32)
    phi = tf.Variable(phi_initial, name="phi", dtype=tf.float32)
    a = tf.exp(tf.Variable(a_initial, name="a", dtype=tf.float32))  # ,0.00001)
    a_inv = 1 / a


    beta = tf.Variable(np.random.randn(X_data.shape[2], 1), name="beta", dtype=tf.float32)
    beta_away = tf.Variable(np.random.randn(X_data.shape[2], 1), name="beta_away", dtype=tf.float32)

    # cost
    theta = 1.0 / (a_inv + 1)

    # mu1 = tf.exp(home_mean + tf.matmul(X[::,0,::], team_attacks) + tf.matmul(X[::,1,::], team_defences))
    # mu2 = tf.exp(away_mean + tf.matmul(X[::,1,::], team_attacks) + tf.matmul(X[::,0,::], team_defences))
    # mu2 = tf.exp(away_mean + tf.matmul(X[::, 1, ::], beta) + tf.matmul(X[::,0,2:], team_defences))
    mu1 = tf.exp(home_mean + tf.matmul(X[::, 0, ::], beta) + tf.matmul(X[::, 1, 2:], team_defences))
    mu2 = tf.exp(away_mean + tf.matmul(X[::, 1, ::], beta_away) + tf.matmul(X[::, 0, 2:], team_defences))
    mu = tf.stack([mu1, mu2], axis=1)
    mu = tf.squeeze(mu, axis=2)

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

    optimizer = GradientDescentOptimizer(learning_rate=0.0001)
    # optimizer =  AdamOptimizer(learning_rate = 0.005)
    train = optimizer.minimize(cost)
