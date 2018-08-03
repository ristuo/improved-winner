data {
  int<lower=0> nrow;
  int<lower=0> n[nrow];
  int<lower=0> player_id_index[nrow];
  int<lower=0> team_type_index[nrow];
  int<lower=0> opposing_team_index[nrow];
  int<lower=0> opposing_team_goalie_index[nrow];
  int<lower=0> goals[nrow];
  int<lower=0> n_players;
  int<lower=0> n_goalies;
  int<lower=0> n_teams;
}

parameters {
  vector[n_players] player_strength;
  vector<lower=0>[n_players] player_propensity;
  vector[n_teams] opposing_team_strength;
  vector[n_teams] team_type_effect;
  real player_strength_mu;
  real<lower=0> player_strength_sigma;
  real<lower=0> player_propensity_mu;
  real<lower=0> player_propensity_sigma;
}

model {
  vector[nrow] mu;
  player_strength_mu ~ normal(0, 100);
  player_strength_sigma ~ uniform(0, 500);
  player_strength ~ normal(player_strength_mu, player_strength_sigma);
  opposing_team_strength ~ normal(0,200);
  team_type_effect ~ normal(0, 100);
  for (i in 1:nrow) {
    mu[i] = inv_logit(
      player_strength[player_id_index[i]] + 
      team_type_effect[team_type_index[i]] + 
      opposing_team_strength[opposing_team_index[i]]);
  }  
  goals ~ binomial(n, mu);
  player_propensity_mu ~ normal(0, 100);
  player_propensity_sigma ~ uniform(0, 500);
  player_propensity ~ lognormal(player_propensity_mu, player_propensity_sigma);
  n ~ poisson(player_propensity[player_id_index]);
}

generated quantities {
  int<lower=0> goals_posterior[nrow];   
  real<lower=0> mu;
  for (i in 1:nrow) {
    mu = inv_logit(
      player_strength[player_id_index[i]] + 
      team_type_effect[team_type_index[i]] + 
      opposing_team_strength[opposing_team_index[i]]);
    goals_posterior[i] = binomial_rng(poisson_rng(player_propensity[player_id_index[i]]), mu);
  }
}

