// todo: default values compute team lambdaan oikein
//
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
  int<lower=0> n_teams;
  int game_data[n_games, n_col_games];
  int<lower=0> home_team_goals[n_games];
  int<lower=0> away_team_goals[n_games];
  int<lower=0> shot_n_rows;
  int<lower=0> shot_n[shot_n_rows];
  int<lower=0> shot_goals[shot_n_rows];
  int<lower=0> shot_player_id_index[shot_n_rows];
  vector[shot_n_rows] shot_games;
  int<lower=0> other_n_rows;
  int<lower=0> other_goals[other_n_rows];
  int<lower=0> other_player_id_index[other_n_rows];
  int other_games[other_n_rows];
  vector[n_games] away_elo_adv;
  vector[n_games] home_elo_adv;
  vector[n_games] away_elo_adv_sq;
  vector[n_games] home_elo_adv_sq;

  int<lower=0> oos_n_games;
  int oos_game_data[oos_n_games, n_col_games];
  int<lower=0> oos_home_team_index[oos_n_games];
  int<lower=0> oos_away_team_index[oos_n_games];

  vector[oos_n_games] oos_away_elo_adv;
  vector[oos_n_games] oos_home_elo_adv;
  vector[oos_n_games] oos_away_elo_adv_sq;
  vector[oos_n_games] oos_home_elo_adv_sq;
}

parameters {
  real home_team_effect;
  real scoring_strength_mu;
  real<lower=0> scoring_strength_sigma;
  real opportunity_strength_mu;
  real<lower=0> opportunity_strength_sigma;
  real other_strength_mu;
  real<lower=0> other_strength_sigma;
  vector[shot_n_rows] raw_scoring_strength;  
  vector[shot_n_rows] raw_opportunity_strength;
  vector[other_n_rows] raw_other_strength;
  real elo_effect;
  real elo_sq_effect;
  real beta;
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
  home_team_effect ~ normal(0, 3);
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
  elo_effect ~ normal(0,10);
  elo_sq_effect ~ normal(0,10);
  beta ~ normal(0, 1);
  home_team_goals ~ poisson_log(
    home_team_effect + 
    elo_effect *  home_elo_adv +
    elo_sq_effect * home_elo_adv_sq +
    beta * home_team_lambda
  );
  away_team_goals ~ poisson_log(
    elo_effect * away_elo_adv +
    elo_sq_effect * away_elo_adv_sq +
    beta * away_team_lambda 
  );
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
  real lambda;
  real oos_lambda;
  for (i in 1:n_games) {
    lambda = exp(
      home_team_effect + 
      elo_effect * home_elo_adv[i] +
      elo_sq_effect * home_elo_adv_sq[i] +
      beta * home_team_lambda[i]
    );
    if (lambda < 500) {
      home_team_post_goals[i] = poisson_rng(lambda);
    } else {
      home_team_post_goals[i] = -1;
    }
    lambda = exp(
      elo_effect * away_elo_adv[i] +
      elo_sq_effect * away_elo_adv_sq[i] +
      beta * away_team_lambda[i]
    );
    if (lambda < 500) {
      away_team_post_goals[i] = poisson_rng(lambda);
    } else {
      away_team_post_goals[i] = -1;
    }
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
    oos_lambda = exp(
      home_team_effect +
      beta * oos_home_team_lambda +
      elo_effect * oos_home_elo_adv[i] + 
      elo_sq_effect * oos_home_elo_adv_sq[i]
    );
    if (oos_lambda < 500) {
      oos_home_team_goals[i] = poisson_rng(oos_lambda);
    } else {
      oos_home_team_goals[i] = -1;
    }
    oos_lambda = exp(
      elo_effect * oos_away_elo_adv[i] + 
      elo_sq_effect * oos_away_elo_adv_sq[i] +
      beta * oos_away_team_lambda
    );
    if (oos_lambda < 500) {
      oos_away_team_goals[i] = poisson_rng(oos_lambda);
    } else {
      oos_away_team_goals[i] = -1;
    }
  }
}
