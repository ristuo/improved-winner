data {
  int<lower=0> n_games;
  int<lower=0> n_teams;
  int<lower=0> team1_index[n_games];
  int<lower=0> team2_index[n_games];
  real<lower=0> team1_goals[n_games];
  real<lower=0> team2_goals[n_games];
}

parameters {
  real h[n_teams];
  real p[n_teams];
  real<lower=0> sigma;
  real hometeam_ga;
  real hometeam_da;
}

transformed parameters {
  real advantage[n_teams, n_teams];
  for (i in 1:n_teams) {
    for (j in 1:n_teams) {
      advantage[i][j] = h[i] - p[j];
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
  for (i in 1:n_games) {
    team1_goals[i] ~ lognormal(hometeam_ga + advantage[team1_index[i]][team2_index[i]], sigma);
    team2_goals[i] ~ lognormal(hometeam_da + advantage[team2_index[i]][team1_index[i]], sigma);
  }
}

generated quantities {
  real team1_g[n_games];
  real team2_g[n_games];
  int result[n_games];
  for (i in 1:n_games) {
    team1_g[i] = lognormal_rng(hometeam_ga + advantage[team1_index[i]][team2_index[i]], sigma);
    team2_g[i] = lognormal_rng(hometeam_da + advantage[team2_index[i]][team1_index[i]], sigma);
    if (fabs(team1_g[i] - team2_g[i]) < 0.5) {
      result[i] = 3; 
    } else if (team1_g[i] > team2_g[i]) {
      result[i] = 1;
    } else {
      result[i] = 2;
    }
  }
}
