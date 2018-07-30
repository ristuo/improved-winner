data {
  int<lower=0> n;
  int<lower=0> goals[n];
  int<lower=0> games[n];
}

parameters {
  real<lower=0> beta_param;
  real<lower=0> alpha_param;
  real x[n];
  real mu;
  real precision;
}

transformed parameters {
  real m; 
  real s;
  real<lower=0, upper=1> p[n];

  s = 5.0;
  m = 2.0;
  for (i in 1:n) {
    p[i] = 1 / (1 + exp(-x[i]));
  }

}

model {
  for (i in 1:n) {
    goals[i] ~ binomial(games[i], p[i]);
  }
  for (i in 1:n) {
    x[i] ~ normal(mu, precision);
    #p[i] ~ beta(alpha_param, beta_param);
  }
  mu ~  normal(0, precision);
  precision ~ gamma((m * m) / (s * s), m / (s * s));
  #alpha_param ~ uniform(0,10);
  #beta_param ~ uniform(0,10);
}

generated quantities {

}
