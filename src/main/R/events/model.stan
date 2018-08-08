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
}

parameters {
  real<lower=0> home_team_effect;
  vector<lower=0>[n_teams] team_defensive_strength;
  vector<lower=0>[n_teams] team_scoring_strength;
  real scoring_strength_mu;
  real scoring_strength_sigma;
  real opportunity_strength_mu;
  real opportunity_strength_sigma;
  real other_strength_mu;
  real other_strength_sigma;
  vector[shot_n_rows] raw_scoring_strength;  
  vector[shot_n_rows] raw_opportunity_strength;
  vector[other_n_rows] raw_other_strength;
}

transformed parameters {
  vector[shot_n_rows] scoring_strength;
  vector[shot_n_rows] opportunity_strength;
  vector[shot_n_rows] opportunity_lambda;
  vector[other_n_rows] other_strength;
  vector[shot_n_rows] p;  
  vector[other_n_rows] other_p;
  vector[n_games] home_team_lambda;
  vector[n_games] away_team_lambda;
  other_strength  = 
    other_strength_mu + 
    raw_other_strength * 
    other_strength_sigma;
  other_p = inv_logit(other_strength[other_player_id_index]);
  scoring_strength = 
    scoring_strength_mu + 
    scoring_strength_sigma * raw_scoring_strength;
  p = inv_logit(scoring_strength[shot_player_id_index]);
  opportunity_strength = 
    opportunity_strength_mu +
    opportunity_strength_sigma * raw_opportunity_strength;
  opportunity_lambda = exp(opportunity_strength[shot_player_id_index]);
  for (i in 1:n_games) {
    home_team_lambda[i] = 0;
    for (j in 1:11) {
      home_team_lambda[i] = home_team_lambda[i] + 
                            opportunity_lambda[game_data[i,j]] * p[game_data[i,j]] +
                            other_p[game_data[i,j]]; 
    }
    away_team_lambda[i] = 0;
    for (j in 12:22) {
      away_team_lambda[i] = away_team_lambda[i] + 
                            opportunity_lambda[game_data[i,j]] * p[game_data[i,j]] +
                            other_p[game_data[i,j]]; 
    }
  }
}

model {
  home_team_effect ~ lognormal(0, 3);
  team_defensive_strength ~ lognormal(0, 3);
  team_scoring_strength ~ normal(0, 1);
  raw_scoring_strength ~ normal(0,1);
  raw_opportunity_strength ~ normal(0,1);
  raw_other_strength ~ normal(0,1);
  other_strength_mu ~ normal(0, 31); 
  other_strength_sigma ~ normal(0, 31);
  opportunity_strength_mu ~ normal(0, 31);
  opportunity_strength_sigma ~ normal(0, 31);
  scoring_strength_mu ~ normal(0, 31);
  scoring_strength_sigma ~ normal(0, 31);
  shot_n ~ poisson(shot_games[shot_player_id_index] .* opportunity_lambda);
  shot_goals ~ binomial(shot_n, p);
  other_goals ~ binomial(other_games, other_p);
  home_team_goals ~ poisson(home_team_effect + 
                            (team_scoring_strength[home_team_index] + home_team_lambda) .* 
                            team_defensive_strength[away_team_index]);
  away_team_goals ~ poisson(team_defensive_strength[home_team_index] .*
                            (away_team_lambda + team_scoring_strength[away_team_index]));
}

generated quantities {
  int home_team_post_goals[n_games];
  int away_team_post_goals[n_games];
  for (i in 1:n_games) {
    home_team_post_goals[i] = poisson_rng((team_scoring_strength[home_team_index[i]] +
                                          home_team_effect + 
                                          home_team_lambda[i]) * 
                                          team_defensive_strength[away_team_index[i]]);
    away_team_post_goals[i] = poisson_rng((team_scoring_strength[away_team_index[i]] +
                                          away_team_lambda[i]) * 
                                          team_defensive_strength[home_team_index[i]]);
  }
}
