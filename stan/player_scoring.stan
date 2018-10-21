data {
  int<lower=0> n_players;
  int goals[n_players];
  int shots[n_players];
  int games[n_players];
}

parameters {
  vector[n_players] raw_probability;
  real probability_population_mean;
  real<lower=0> probability_population_sigma;
  vector[n_players] raw_lambda;
  real lambda_population_mean;
  real<lower=0> lambda_population_sigma;
}

transformed parameters {
  vector[n_players] probability = inv_logit(
    probability_population_mean + 
    probability_population_sigma * raw_probability
  );
  vector[n_players] lambda = exp(
    lambda_population_mean + 
    lambda_population_sigma * raw_lambda
  ); 
}

model {
  raw_probability ~ normal(0,1);
  raw_lambda ~ normal(0,1);
  probability_population_mean ~ normal(0,2);
  probability_population_sigma ~ uniform(0,5);
  lambda_population_mean ~ normal(0,2);
  lambda_population_sigma ~ uniform(0,5);
  for (i in 1:n_players) {
    shots[i] ~ poisson(games[i] * lambda[i]);
    goals[i] ~ binomial(shots[i], probability[i]);
  }
}
