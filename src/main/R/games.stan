data {
  int<lower=0> n_games;
  int<lower=0> n_teams;
  int<lower=0> team1_index[n_games];
  int<lower=0> team2_index[n_games];
  int<lower=0> team1_goals[n_games];
  int<lower=0> team2_goals[n_games];
}

parameters {
  real h[n_teams];
  real<lower=0> lambda[n_teams, n_teams];
  real p[n_teams];
  real<lower=0> sigma;
  real hometeam_ga;
  real hometeam_da;
}

transformed parameters {
  real advantage[n_teams, n_teams];
  for (i in 1:n_teams) {
    for (j in 1:n_teams) {
      advantage[i][j] = exp(h[i] - p[j]);
    }
  }
}

model {
  hometeam_ga ~ normal(0.3, 1);
  hometeam_da ~ normal(-0.3, 1);
  for (i in 1:n_teams) {
    h[i] ~ normal(0, 4);
    p[i] ~ normal(0, 4);
  }
  sigma ~ inv_gamma(1,1);
  for (i in 1:n_teams) {
    for (j in 1:n_teams) {
      lambda[i][j] ~ lognormal(advantage[i][j], sigma);
    }
  }
  for (i in 1:n_games) {
    team1_goals[i] ~ poisson(hometeam_ga + lambda[team1_index[i]][team2_index[i]]);
    team2_goals[i] ~ poisson(hometeam_da + lambda[team2_index[i]][team1_index[i]]);
  }
}

generated quantities {
  int team1_g[n_games];
  int team2_g[n_games];
  for (i in 1:n_games) {
    team1_g[i] = poisson_rng(hometeam_ga + lambda[team1_index[i]][team2_index[i]]);
    team2_g[i] = poisson_rng(hometeam_da + lambda[team2_index[i]][team1_index[i]]);
  }
}
