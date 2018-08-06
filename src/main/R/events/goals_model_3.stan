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
  vector[n_players] player_propensity;
  vector[n_players] player_strength;
  vector[n_teams] opposing_team_strength;
  vector[n_teams] opposing_team_strength_prop;
  real player_strength_mu;
  real<lower=0> player_strength_sigma;
  vector[4] player_position_effect;
  vector[2] team_type_effect;
}

transformed parameters {
  vector[nrow] lambda_prop;
  lambda_prop = player_propensity[player_id_index] + 
                player_position_effect[player_position_index] +
                opposing_team_strength_prop[opposing_team_index];
}

model {
  vector[nrow] mu;
  player_strength_mu ~ normal(0, 12);
  player_strength_sigma ~ uniform(0, 100);
  player_strength ~ normal(player_strength_mu, player_strength_sigma);
  opposing_team_strength ~ normal(0,12);
  opposing_team_strength_prop ~ normal(0,12);
  team_type_effect ~ normal(0,12);
  mu = inv_logit(player_strength[player_id_index] + 
                 team_type_effect[team_type_index] + 
                 opposing_team_strength[opposing_team_index]);
  goals ~ binomial(n, mu);
  player_position_effect ~ normal(0, 12);
  player_propensity ~ normal(0, 12);
  n ~ poisson_log(lambda_prop);
}

generated quantities {
  vector<lower=0>[nrow] goals_posterior;   
  real<lower=0> mu;
  for (i in 1:nrow) {
    mu = inv_logit(player_strength[player_id_index[i]] + 
                   team_type_effect[team_type_index[i]] + 
                   opposing_team_strength[opposing_team_index[i]]);
    goals_posterior[i] = binomial_rng(poisson_rng(exp(lambda_prop[player_id_index[i]])), 
                                                      mu);
  }
}
