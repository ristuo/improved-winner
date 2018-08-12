functions {
  real compute_team_lambda(int i, vector opportunity_lambda, 
                           int[,] game_data,
                           vector p, vector other_p, int start_index, 
                           int end_index,
                           real default_value) {
    real res = 0;
    int index;
    for (j in start_index:end_index) {
      index = game_data[i,j];
      if (index == -1) {
        res = res + default_value;
      } else {
        res = res + opportunity_lambda[index] * p[index] + other_p[index];
      }
    }
    return(res);
  }
}

data {
  int<lower=0> n_games;
  int<lower=0> n_col_games;
  int<lower=0> n_years;
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
  int<lower=0> game_year[n_games];
  // out of sample!
  int<lower=0> oos_n_games;
  int oos_game_data[oos_n_games, n_col_games];
  int<lower=0> oos_home_team_index[oos_n_games];
  int<lower=0> oos_away_team_index[oos_n_games];
  int<lower=0> oos_game_year[oos_n_games];
}

parameters {
  real<lower=0> home_team_effect;
  real<lower=0> team_defensive_strength[n_teams, n_years];
  real<lower=0> team_scoring_strength[n_teams, n_years];
  real scoring_strength_mu;
  real<lower=0> scoring_strength_sigma;
  real opportunity_strength_mu;
  real<lower=0> opportunity_strength_sigma;
  real other_strength_mu;
  real<lower=0> other_strength_sigma;
  vector[shot_n_rows] raw_scoring_strength;  
  vector[shot_n_rows] raw_opportunity_strength;
  vector[other_n_rows] raw_other_strength;
  real team_defensive_strength_mu[n_teams];
  real<lower=0> team_defensive_strength_sigma[n_teams];
  real team_scoring_strength_mu[n_teams];
  real<lower=0> team_scoring_strength_sigma[n_teams];
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
    home_team_lambda[i] = compute_team_lambda(
      i, 
      opportunity_lambda, 
      game_data,
      p, 
      other_p, 
      1, 
      n_col_games/2,
      exp(opportunity_strength_mu) * scoring_strength_mu + other_strength_mu
    );
    away_team_lambda[i] = compute_team_lambda(
      i, 
      opportunity_lambda, 
      game_data,
      p, 
      other_p, 
      n_col_games/2 + 1, 
      n_col_games,
      exp(opportunity_strength_mu) * scoring_strength_mu + other_strength_mu
    );
  }
}

model {
  home_team_effect ~ lognormal(0, 3);
  for (i in 1:n_teams) {
    team_defensive_strength_mu[i] ~ normal(0, 1);
    team_defensive_strength_sigma[i] ~ uniform(0, 10);
    team_scoring_strength_mu[i] ~ normal(0, 1);
    team_scoring_strength_sigma[i] ~ uniform(0,10);
    for (j in 1:n_years) {
      team_defensive_strength[i,j] ~ lognormal(
        team_defensive_strength_mu[i], 
        team_defensive_strength_sigma[i]
      );
      team_scoring_strength[i,j] ~ normal(
        team_scoring_strength_mu[i], 
        team_scoring_strength_sigma[i]
      );
    }
  }
  raw_scoring_strength ~ normal(0,1);
  raw_opportunity_strength ~ normal(0,1);
  raw_other_strength ~ normal(0,1);
  other_strength_mu ~ normal(0, 31); 
  other_strength_sigma ~ uniform(0, 50);
  opportunity_strength_mu ~ normal(0, 31);
  opportunity_strength_sigma ~ uniform(0, 50);
  scoring_strength_mu ~ normal(0, 31);
  scoring_strength_sigma ~ uniform(0, 50);
  shot_n ~ poisson(shot_games[shot_player_id_index] .* opportunity_lambda);
  shot_goals ~ binomial(shot_n, p);
  other_goals ~ binomial(other_games, other_p);
  for (i in 1:n_games) {
    home_team_goals ~ poisson(
      home_team_effect + 
      (team_scoring_strength[home_team_index[i], game_year[i]] + home_team_lambda[i]) .* 
      team_defensive_strength[away_team_index[i], game_year[i]]
    );
    away_team_goals ~ poisson(
      team_defensive_strength[home_team_index[i], game_year[i]] .*
      (away_team_lambda[i] + team_scoring_strength[away_team_index[i], game_year[i]])
    );
  }
}

generated quantities {
  int home_team_post_goals[n_games];
  int away_team_post_goals[n_games];
  real oos_home_team_lambda;
  real oos_away_team_lambda;
  int oos_home_team_goals[oos_n_games];
  int oos_away_team_goals[oos_n_games];
  real default_opportunity_lambda;
  real default_scoring_p;
  real default_other_p;
  for (i in 1:n_games) {
    home_team_post_goals[i] = poisson_rng(
      (team_scoring_strength[home_team_index[i], game_year[i]] + home_team_effect + home_team_lambda[i]) * 
      team_defensive_strength[away_team_index[i], game_year[i]]
    );
    away_team_post_goals[i] = poisson_rng(
      (team_scoring_strength[away_team_index[i], game_year[i]] + away_team_lambda[i]) * 
      team_defensive_strength[home_team_index[i], game_year[i]]
    );
  }

  for (i in 1:oos_n_games) {
    default_opportunity_lambda = exp(normal_rng(opportunity_strength_mu, opportunity_strength_sigma));
    default_scoring_p = inv_logit(normal_rng(scoring_strength_mu, scoring_strength_sigma));
    default_other_p = inv_logit(normal_rng(other_strength_mu, other_strength_sigma));
    oos_home_team_lambda = compute_team_lambda(
      i, 
      opportunity_lambda, 
      oos_game_data,
      p, 
      other_p, 
      1, 
      n_col_games/2,
      default_opportunity_lambda * default_scoring_p + default_other_p
    );
    oos_away_team_lambda = compute_team_lambda(
      i, 
      opportunity_lambda, 
      oos_game_data,
      p, 
      other_p, 
      n_col_games/2 + 1, 
      n_col_games,
      default_opportunity_lambda * default_scoring_p + default_other_p
    );
    oos_home_team_goals[i] = poisson_rng(
      (home_team_effect + team_scoring_strength[oos_home_team_index[i], oos_game_year[i]] + 
      oos_home_team_lambda) *
      team_defensive_strength[oos_away_team_index[i], oos_game_year[i]]
    );
    oos_away_team_goals[i] = poisson_rng(
      (team_scoring_strength[oos_away_team_index[i], oos_game_year[i]] +
       oos_away_team_lambda) *
      team_defensive_strength[oos_home_team_index[i], oos_game_year[i]]
    );
  }
}
