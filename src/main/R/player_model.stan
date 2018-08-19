data {
  int<lower=0> n_games;
  int<lower=0> n_col_games;
  int<lower=0> n_teams;
  int game_data[n_games, n_col_games];
  int<lower=0> home_team_goals[n_games];
  int<lower=0> away_team_goals[n_games];
  int<lower=0> home_team_index[n_games];
  int<lower=0> away_team_index[n_games];
  int<lower=0> shot_n_rows;
  int<lower=0> shot_n[shot_n_rows];
  int<lower=0> shot_goals[shot_n_rows];
  int<lower=0> shot_player_id_index[shot_n_rows];
  vector[shot_n_rows] shot_games;
  int<lower=0> other_n_rows;
  int<lower=0> other_goals[other_n_rows];
  int<lower=0> other_player_id_index[other_n_rows];
  int other_games[other_n_rows];

 
  int<lower=0> oos_n_games;
  int oos_game_data[oos_n_games, n_col_games];
  int<lower=0> oos_home_team_index[oos_n_games];
  int<lower=0> oos_away_team_index[oos_n_games];
}

parameters {
  vector<lower=0>[shot_n_rows] shot_player_lambda;
  real<lower=0> shot_lambda_beta_alpha;
  real<lower=0> shot_lambda_beta_beta;
  vector<lower=0, upper=1>[shot_n_rows] shot_player_p;
  real<lower=1> shot_p_kappa;
  real<lower=0,upper=1> shot_p_phi;
  vector<lower=0, upper=1>[other_n_rows] other_player_p;
  real<lower=1> other_p_kappa;
  real<lower=0,upper=1> other_p_phi;
}

model {
  shot_n ~ poisson(shot_games .* shot_player_lambda);
  shot_player_lambda ~ gamma(shot_lambda_beta_alpha, shot_lambda_beta_beta);
  shot_lambda_beta_alpha ~ uniform(0, 10);
  shot_lambda_beta_beta ~ uniform(0, 10);

  shot_goals ~ binomial(shot_n, shot_player_p);
  shot_player_p ~ beta(shot_p_phi * shot_p_kappa, (1 - shot_p_phi) * shot_p_kappa);
  shot_p_kappa ~ pareto(1, 15);
  shot_p_phi ~ uniform(0,1);

  other_goals ~ binomial(other_games, other_player_p);
  other_player_p ~ beta(other_p_phi * other_p_kappa, (1 - other_p_phi) * other_p_kappa);
  other_p_kappa ~ pareto(1, 15);
  other_p_phi ~ uniform(0,1);
}

generated quantities {
  vector[shot_n_rows] expected_goals;
  for (i in 1:shot_n_rows) {
    expected_goals[i] = poisson_rng(shot_player_p[i] * shot_player_lambda[i]) + 
      poisson_rng(other_player_p[i]); 
  }
}


