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
  int<lower=0> player_position_index[nrow];
}

parameters {
  vector<lower=0>[n_players] player_propensity;
  vector[n_teams] opposing_team_strength;
  vector[n_teams] opposing_team_strength_prop;
  real player_strength_mu;
  real<lower=0> player_strength_sigma;
  real<lower=0> player_propensity_mu;
  real<lower=0> player_propensity_sigma;
  vector[4] player_position_mu;
  vector<lower=0>[4] player_position_sigma;
  vector[2] team_type_effect;
  vector[n_players] raw_ps;
}

transformed parameters {
  vector[n_players] player_strength;
  vector[nrow] lambda_prop;
  player_strength = player_strength_mu + player_strength_sigma * raw_ps;
  lambda_prop = exp(
    player_propensity[player_id_index] + 
    opposing_team_strength_prop[opposing_team_index]);
}

model {
  vector[nrow] mu;
  raw_ps ~ normal(0, 1);
  player_strength_mu ~ normal(0, 100);
  player_strength_sigma ~ uniform(0, 31);
  //player_strength ~ normal(player_strength_mu, player_strength_sigma);
  opposing_team_strength ~ normal(0,31);
  opposing_team_strength_prop ~ normal(0,31);
  team_type_effect ~ normal(0, 100);
  mu = inv_logit(player_strength[player_id_index] + 
                 team_type_effect[team_type_index] + 
                 opposing_team_strength[opposing_team_index]);
  goals ~ binomial(n, mu);
  player_position_mu ~ normal(0, 100);
  player_position_sigma ~ uniform(0, 31);
  player_propensity_mu ~ normal(
    player_position_mu[player_position_index], 
    player_position_sigma[player_position_index]);
  player_propensity_sigma ~ uniform(0, 31);
  player_propensity ~ normal(player_propensity_mu, player_propensity_sigma);
  n ~ poisson(lambda_prop);
}
generated quantities {
  vector<lower=0>[nrow] goals_posterior;   
  real<lower=0> mu;
  mu = inv_logit(player_strength[player_id_index] + 
                 team_type_effect[team_type_index] + 
                 opposing_team_strength[opposing_team_index]);
  goals_posterior = binomial_rng(poisson_rng(player_propensity[player_id_index]), mu);
}
