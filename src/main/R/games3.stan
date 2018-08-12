data {
  int<lower=0> n_games;
  int<lower=0> n_teams;
  int<lower=0> team1_index[n_games];
  int<lower=0> team2_index[n_games];
  real goal_diff[n_games];
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
}

model {
  hometeam_ga ~ normal(0.3, 100);
  //for (i in 1:n_teams) {
  //  h[i] ~ normal(0, 4);
  //} 
  sigma ~ inv_gamma(1,1);
  
  for (i in 1:n_games) {
    //goal_diff[i] ~ normal(hometeam_ga + h[team1_index[i]] - h[team2_index[i]], sigma);
    goal_diff[i] ~ normal(hometeam_da,sigma);
  }
}

generated quantities {
  //real team1_g[n_games];
  //real team2_g[n_games];
  //for (i in 1:n_games) {
  //  team1_g[i] = lognormal_rng(hometeam_ga + advantage[team1_index[i]][team2_index[i]], sigma);
  //  team2_g[i] = lognormal_rng(hometeam_da + advantage[team2_index[i]][team1_index[i]], sigma);
  //}
}
