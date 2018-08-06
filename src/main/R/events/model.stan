data {
  int<lower=0> n_rows;
  int<lower=0> n[n_rows];
  int<lower=0> goals[n_rows];
  int<lower=0> player_indices[n_rows];
}

parameters {
  real<lower=0, upper=1> p[n_rows];
  real<lower=0> lambda[n_rows]
}

transformed parameters {
  vector scoring_strength;
  vector opportunity_strength;
  scoring_strength = 
    scoring_strength_mu + 
    scoring_strength_sigma * raw_scoring_strength
  opportunity_strength = 
    opportunity_strength_mu +
    opportunity_strength_sigma * raw_opportunity_strength;
}

model {
  vector[n_rows] raw_scoring_strength;  
  vector[n_rows] raw_opportunity_strength;
  real scoring_strength_mu;
  real scoring_strength_sigma;
  real opportunity_strength_mu;
  real opportunity_strength_sigma;
  raw_pss ~ normal(0,1);
  raw_pos ~ normal(0,1);
  opportunity_strength_mu ~ normal(0, 31);
  opportunity_strength_sigma ~ normal(0, 31);
  scoring_strength_mu ~ normal(0, 31);
  scoring_strength_sigma ~ normal(0, 31);
  n ~ poisson_log(opportunity_strength);
  goals ~ binomial(n, inv_logit(scoring_strength));
}
