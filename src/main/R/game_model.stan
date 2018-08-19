data {
  int<lower=0> n_games;
  int<lower=0> n_teams;
  vector<lower=0>[n_games] expected_home;
  vector<lower=0>[n_games] expected_away;
  int years;
  int<lower=0> year_index[n_games];
  int<lower=0> home_team_goals[n_games];
  int<lower=0> away_team_goals[n_games];
  int<lower=0> home_team_index[n_games];
  int<lower=0> away_team_index[n_games];

  int<lower=0> oos_n_games;
  int<lower=0> oos_home_team_index[oos_n_games];
  int<lower=0> oos_away_team_index[oos_n_games];
}

parameters {
  vector[n_teams] raw_team_attack_strength;
  vector[n_teams] raw_team_defense_strength;
  real team_attack_strength_mu;
  real<lower=0> team_attack_strength_sigma;
  real team_defense_strength_mu;
  real<lower=0> team_defense_strength_sigma;
  real beta;
  real intercept;
  real home_team_effect;
}

transformed parameters {
  vector[n_teams] team_attack_strength[years];
  vector[n_teams] team_defense_strength;
  team_attack_strength = team_attack_strength_mu + raw_team_attack_strength *
    team_attack_strength_sigma;
  team_defense_strength = team_defense_strength_mu + raw_team_defense_strength *
    team_defense_strength_sigma;
}

model {
    home_team_goals ~ poisson_log(
      intercept + beta * expected_home + 
      team_attack_strength[home_team_index] + 
      team_defense_strength[away_team_index] + 
      home_team_effect
    );
    away_team_goals ~ poisson_log(
      intercept + beta * expected_away + 
      team_attack_strength[away_team_index] + 
      team_defense_strength[home_team_index] 
    );
    beta ~ normal(0, 5);
    intercept ~ normal(0, 5);
    home_team_effect ~ normal(0, 1);
    raw_team_attack_strength ~ normal(0, 1);
    raw_team_defense_strength ~ normal(0, 1);
    team_attack_strength_mu ~ normal(0, 3);
    team_attack_strength_sigma ~ uniform(0, 5);
    team_defense_strength_mu ~ normal(0, 3);
    team_defense_strength_sigma ~ uniform(0, 5);
}

