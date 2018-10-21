from pystan import StanModel
import pickle
import numpy as np
import pandas as pd
from uuid import uuid4
from os import path


class SimplePlayerModel:
    default_control = {
        'adapt_delta': 0.99,
        'max_treedepth': 15
    }

    def __init__(self, player_stats, model_name=None):
        """
        A Stan model for player scoring probabilities.
        :param player_stats:
        :param model_name:
        """
        self.player_stats = player_stats
        self.stan_model = None
        self.samples = None
        self.stan_data = {
            'n_players': player_stats.shape[0],
            'goals': player_stats['goals'].values,
            'shots': player_stats['shots'].values,
            'games': player_stats['games'].values
        }
        if model_name is not None:
            self.model_name = 'model' + model_name
            self.samples_name = 'fit_' + model_name
        else:
            model_id = uuid4().hex
            self.model_name = 'model_' + model_id
            self.samples_name = 'fit_' + model_id
        self.samples_path = '.' + self.samples_name
        self.model_path = '.' + self.model_name

    def fit(self, iterations=5000, control=default_control):
        self.stan_model = StanModel(
            '../stan/player_scoring.stan'
        )
        self.samples = self.stan_model.sampling(
            self.stan_data,
            iter=iterations,
            chains=4,
            refresh=1,
            control=control
        )

    def save(self):
        if self.samples is None or self.stan_model is None:
            raise RuntimeError('Not much point saving with no samples')
        with open(self.model_path, 'wb') as fp:
            pickle.dump(self.stan_model, fp, protocol=pickle.HIGHEST_PROTOCOL)
        with open(self.samples_path, 'wb') as fp:
            pickle.dump(self.samples, fp, protocol=pickle.HIGHEST_PROTOCOL)

    def load(self):
        if not self._can_load():
            raise RuntimeError('Could not find file ' + self.model_path)
        with open(self.model_path, 'rb') as fp:
            self.stan_model = pickle.load(fp)
        with open(self.samples_path, 'rb') as fp:
            self.samples = pickle.load(fp)

    def _check_samples(self):
        if self.samples is None:
            raise RuntimeError('Sample before calling these model operations')

    def _can_load(self):
        return path.exists(self.model_path) and path.exists(self.samples_path)

    def load_or_fit(self):
        if self._can_load():
            self.load()
        else:
            self.fit()
        return self

    # todo: parempi olisi käyttää joinia, vaikka näyttää toimivan 14.10.
    def find_team_expectations(self, game_data):
        self._check_samples()
        lambdas = self.samples.extract('lambda')['lambda']
        probs = self.samples.extract('probability')['probability']
        lmeans = np.apply_along_axis(np.mean, 0, lambdas)
        pmeans = np.apply_along_axis(np.mean, 0, probs)
        player_id_indices = self.player_stats['player_id_index']

        player_expected = pd.DataFrame(
            lmeans * pmeans, index=player_id_indices
        )

        mean_expected = float(np.mean(player_expected))
        not_in_model = game_data > player_expected.shape[0]
        game_data[not_in_model] = player_expected.shape[0]
        player_expected_sorted = player_expected.sort_index().values.squeeze()
        player_expected_sorted = np.append(player_expected_sorted, mean_expected)

        cutoff = int(game_data.values.shape[1]/2)
        home_player_e = np.apply_along_axis(
            np.sum,
            1,
            player_expected_sorted[game_data.values][::, 0:cutoff]
        )
        away_player_e = np.apply_along_axis(
            np.sum,
            1,
            player_expected_sorted[game_data.values][::, cutoff::]
        )
        player_es = pd.DataFrame(np.stack((home_player_e, away_player_e), axis=1),
                                 index=game_data.index, columns=['home_expected', 'away_expected'])
        return player_es
