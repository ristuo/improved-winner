functions {
  //real bnb_cost(int[,] Y, real phi, vector[] mu, vector a_inv, int n) {
  real bnb_cost(int[,] Y, real phi, matrix mu, vector a_inv, int n) {
    vector[n] logl;
    real tmp;
    vector[2] theta;
    vector[2] c[n];
    vector[2] a_inv_mu[n];
    theta[1] = 1.0 / (a_inv[1] + 1); 
    theta[2] = 1.0 / (a_inv[2] + 1); 
    for (i in 1:n) {
      for (t in 1:2) {
        a_inv_mu[i][t] = a_inv[t] * mu[i][t];
        c[i][t] = ((1.0 - theta[t]) / (1 - theta[t] * exp(-1))) ^ (a_inv_mu[i][t]);
      }   
    }   
    tmp = 0;
    for (i in 1:n) {
      tmp = 0;
      for (t in 1:2) {
        tmp += lgamma(Y[i,t] + a_inv_mu[i][t]) - lgamma(Y[i,t] + 1) - 
               lgamma(a_inv_mu[i][t]) - Y[i,t] * log1p(a_inv[t]) + 
               a_inv_mu[i][t] * (log(a_inv[t]) - log1p(a_inv[t]));
      }   
      tmp += log1p(phi * (exp(-Y[i,1]) - c[i][1]) * (exp(-Y[i,2]) - c[i][2]));
      logl[i] = tmp;
    }   
    return sum(logl);
  }

  real bnb_probability(int[] Y, vector mu, vector a_inv, real phi) {
    vector[2] a_inv_mu;
    vector[2] theta;
    vector[2] c;
    vector[2] fst;
    vector[2] snd;
    vector[2] trd;
    vector[2] y;
    real raw_frt;
    real frt;
    y[1] = Y[1];
    y[2] = Y[2];
    a_inv_mu = mu .* a_inv;
    for (i in 1:2) {
      theta[i] = 1.0 / (a_inv[i] + 1.0);
      c[i] = ((1.0 - theta[i]) / (1.0 - theta[i] * exp(-1))) ^ a_inv_mu[i];
    }
    fst = lgamma(y + a_inv_mu) - lgamma(y + 1) - lgamma(a_inv_mu);
    snd = y .* log1p(a_inv);
    trd = a_inv_mu .* (log(a_inv) - log1p(a_inv));
    raw_frt = phi * (exp(-y[1]) - c[1]) * (exp(-y[2]) - c[2]);
    if (raw_frt < -1.0) {
      print("Uh oh, about to take log1p of value smaller than -1, let's arbitrarily set it to -0.995");
      print("a_inv");
      print(a_inv);
      print("phi");
      print(phi);
      print("y");
      print(y);
      print("theta");
      print(theta);
      print("c");
      print(c);
      raw_frt = -0.995;
    } 
    frt = log1p(raw_frt);
    return exp(sum(fst - snd + trd) + frt);
  }

  matrix bnb_predictions(vector mu, vector a_inv, real phi, int max_goals) {
    matrix[max_goals, max_goals] res;
    int y[2];
    for (i in 0:(max_goals-1)) {
      for (j in 0:(max_goals-1)) {
        y[1] = i;
        y[2] = j;
        res[i + 1,j + 1] = bnb_probability(y, mu, a_inv, phi);
      }
    }
    return res;
  }  
}

data {
  int n_rows;
  int n_teams;
  int m_ratings;
  int max_goals;
  matrix[n_rows, n_teams] home_team_dummies;
  matrix[n_rows, n_teams] away_team_dummies;
  matrix[n_rows, 2] expectations;
  matrix[n_rows, m_ratings] ratings;
  int Y[n_rows, 2];

  int oos_n_rows;
  matrix[oos_n_rows, n_teams] oos_home_team_dummies;
  matrix[oos_n_rows, n_teams] oos_away_team_dummies;
  matrix[oos_n_rows, 2] oos_expectations;
  matrix[oos_n_rows, m_ratings] oos_ratings; 
}

parameters {
  vector[m_ratings] ratings_beta_home;
  vector[m_ratings] ratings_beta_away;
  real expectations_beta;
  vector[n_teams] team_attack_beta;
  vector[n_teams] team_defence_beta;
  vector<lower=0>[2] a;
  real phi;
  real intercept;
  real home_team_effect;
}

transformed parameters {
  vector[2] a_inv;
  matrix[n_rows,2] mu;
  a_inv[1] = 1.0 / a[1];
  a_inv[2] = 1.0 / a[2];
  mu[:,1] = exp(
    intercept + home_team_effect + home_team_dummies * team_attack_beta +  
    away_team_dummies * team_defence_beta + ratings * ratings_beta_home + 
    expectations[:,1] * expectations_beta
  );
  mu[:,2] = exp(
    intercept + away_team_dummies * team_attack_beta +  
    home_team_dummies * team_defence_beta + ratings * ratings_beta_away + 
    expectations[:,2] * expectations_beta
  );
}


model {
  phi ~ normal(0,5);
  intercept ~ normal(0,5);
  home_team_effect ~ normal(0.2,3);
  ratings_beta_home ~ normal(0,5);
  ratings_beta_away ~ normal(0,5);
  team_attack_beta ~ normal(0,1);
  team_defence_beta ~ normal(0,1);
  expectations_beta ~ normal(0,5);
  a ~ uniform(0,10);
  target += bnb_cost(Y, phi, mu, a_inv, n_rows);
}

generated quantities {
  matrix[oos_n_rows, 2] oos_mu;
  matrix[max_goals, max_goals] probability;
  matrix[max_goals, max_goals] predicted_probabilities[oos_n_rows];
  oos_mu[:,1] = exp(
    intercept + home_team_effect + oos_home_team_dummies * team_attack_beta +  
    oos_away_team_dummies * team_defence_beta + oos_ratings * ratings_beta_home + 
    oos_expectations[:,1] * expectations_beta
  );
  oos_mu[:,2] = exp(
    intercept + oos_away_team_dummies * team_attack_beta +  
    oos_home_team_dummies * team_defence_beta + oos_ratings * ratings_beta_away + 
    oos_expectations[:,2] * expectations_beta
  ); 
  for (i in 1:oos_n_rows) {
    probability = bnb_predictions(to_vector(oos_mu[i,:]), a_inv, phi, max_goals);
    predicted_probabilities[i] = probability;
  }
}
