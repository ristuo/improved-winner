import numpy as np
import sys
import pandas as pd
import keras
from keras import Input
from keras.models import Model
import keras.backend as K
from keras.layers import Conv1D, Reshape, Dense, Dropout, Activation

def find_game_vec(teams, team1, team2):
  t1 = teams.loc[[team1]].values
  t2 = teams.loc[[team2]].values
  res = np.concatenate((t1, t2), axis = 1)
  return res.squeeze()

def load_data(season):
  def load_teams(season):
    def find_top(df, min_players):
      res = df.sort_values('pct_in', ascending = False).head(min_players).drop(['Joukkue'], axis = 1)
      res.insert(0, 'player', range(0, min_players))
      return res
    players_path = 'data/{}_pelaajat.csv'.format(season)
    players = pd.read_csv(players_path)
    players = players.drop(['#', 'L%', 'Nimi'], axis = 1)
    players['pct_in'] =  players['AK'] / players['O']
    min_players = players['Joukkue'].value_counts().min()
    top_players = players.groupby('Joukkue').apply(lambda x: find_top(x, min_players)).reset_index().drop(['level_1'], axis = 1)
    melted = pd.melt(top_players, id_vars = ['Joukkue', 'player'])
    n_player_vars = melted['variable'].value_counts().shape[0]
    melted['variable'] = melted['player'].astype(str) + "_" + melted['variable']
    melted = melted.drop(['player'], axis = 1)
    res = melted.pivot(index = 'Joukkue', columns = 'variable')
    return (res, n_player_vars, min_players)
  def load_games(season):
    games_path = 'data/{}_pelit.csv'.format(season)
    games = pd.read_csv(games_path)
    games['t1_goals'], games['t2_goals'] = games['Tulos'].str.split(' — ', 1).str
    games['t1_goals'] = pd.to_numeric(games['t1_goals'])
    games['t2_goals'] = pd.to_numeric(games['t2_goals'])
    games['t1'], games['t2'] = games['Ottelu'].str.split(' - ', 1).str
    games = games[['t1', 't2', 't1_goals', 't2_goals']]
    return games
  teams, n_player_variables, min_players = load_teams(season) 
  games = load_games(season)
  Y = games.values[::,2:]
  X = np.apply_along_axis(lambda df: find_game_vec(teams, df[0], df[1]), 1, games)
  return (Y,X, n_player_variables, min_players, games, teams)

Y_train, X_train, n_player_variables, min_players, _, teams = load_data(2016)
n, m = X_train.shape
x_maxes = (X_train.max(axis=0) + K.epsilon())
X_train = X_train / x_maxes
X_train = X_train.reshape((n, m, 1))
inputs = keras.Input(shape = (m, 1))
n_filters = 4
X = Conv1D(
  filters = n_filters, 
  kernel_size = n_player_variables, 
  strides = n_player_variables
)(inputs)
X = Activation("tanh")(X)
condensed_player_vars = int(m / n_player_variables) * n_filters
X = Reshape([condensed_player_vars])(X)
X = Dense(4, activation = 'relu', input_shape = [condensed_player_vars], kernel_regularizer=keras.regularizers.l2(0.01))(X)
X = Dropout(0.5)(X)
Y = Dense(2, activation = K.exp)(X)
model = Model(inputs = inputs, outputs = Y)
model.compile('adam', loss = 'poisson')
values = model.fit(X_train, Y_train, validation_split = 0.1, epochs = 100)


model.predict(X_train)


def example(t1, t2, model, x_maxes):
  tvec = find_game_vec(teams, t1, t2) / x_maxes
  tvec = tvec.reshape(1, tvec.shape[0], 1)
  print(model.predict(tvec))

example("HJK", "HIFK", model, x_maxes)
