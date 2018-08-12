data {
  int<lower=0> n_games;
  real goal_diff[n_games];
}
parameters {
  real mu;
  real<lower=0> sigma;
}
model {
  mu ~ normal(0.3, 100);
  sigma ~ inv_gamma(1, 1);
  for (i in 1:n_games) {
    goal_diff[i] ~ normal(mu, sigma);
  }
}
