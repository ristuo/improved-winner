import numpy as np


def _lpd_hat(log_likelihoods):
    return np.sum(np.log(np.mean(np.exp(log_likelihoods), axis=0)))


def _pwaic(log_likelihoods):
    s, n = log_likelihoods.shape
    squared_errors = np.square(
        log_likelihoods - np.mean(log_likelihoods, axis=0))
    return np.sum(np.sum(squared_errors), axis=0) * (1 / (s - 1))


def waic(samples, likelihood_name='log_likelihoods'):
    likelihoods = samples[likelihood_name]
    return _lpd_hat(likelihoods) - _pwaic(likelihoods)
