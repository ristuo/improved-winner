data {
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
}

model {
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
  shot_goals ~ binomial(shot_n, inv_logit(scoring_strength[shot_player_id_index]));
  other_goals ~ binomial(other_games, inv_logit(other_strength[other_player_id_index]));
}

generated quantities {

}
