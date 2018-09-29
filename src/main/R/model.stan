// todo: default values compute team lambdaan oikein
//
functions {
  real compute_team_lambda(int i, vector opportunity_lambda, 
                           int[,] game_data,
                           vector p, int start_index, 
                           int end_index,
                           real default_value) {
    real res = 0;
    int index;
    for (j in start_index:end_index) {
      index = game_data[i,j];
      if (index == -1) {
        res = res + default_value;
      } else {
        res = res + opportunity_lambda[index] * p[index];
      }
    }
    return(res);
  }

  real bnb_prob_term(int y, real mu, real a_inv) {
    real a_inv_mu = a_inv * mu;
    return lgamma(y + a_inv_mu) - lgamma(y + 1) - 
      lgamma(a_inv_mu) - y * log1p(a_inv) + 
      a_inv_mu * (log(a_inv) - log1p(a_inv));
  }

	real bnb_final_term(int y1, int y2, real phi, real mu1, real mu2, real a_inv1, real a_inv2) {
    real theta1;
    real theta2;
    real c1;
    real c2;
		real res;
    theta1 = 1.0 / (a_inv1 + 1);
    theta2 = 1.0 / (a_inv2 + 1);
    c1 = ((1.0 - theta1) / (1 - theta1 * exp(-1))) ^ (a_inv1 * mu1);
    c2 = ((1.0 - theta2) / (1 - theta2 * exp(-1))) ^ (a_inv2 * mu2);
		res = phi * (exp(-y1) - c1) * (exp(-y2) - c2);
		if (res > 0) {
			return log1p(res);
		} else {
			return -1;
		}
	}

  real bnb_prob(int y1, int y2, real phi, real mu1, real mu2, real a_inv1, real a_inv2) {
    real res;
    res = bnb_prob_term(y1, mu1, a_inv1) + bnb_prob_term(y2, mu2, a_inv2) + 
          bnb_final_term(y1, y2, phi, mu1, mu2, a_inv1, a_inv2);;
    return exp(res);
  }

  real bnb_cost(int[,] Y, real phi, vector[] mu, vector a_inv, int n) {
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
}

data {
  int<lower=0> n_games;
  int<lower=0> n_team_col;
  matrix[n_games, n_team_col] home_teams;
  matrix[n_games, n_team_col] away_teams;
  int<lower=0> n_col_games;
  int<lower=0> n_teams;
  int game_data[n_games, n_col_games];
  int<lower=0> Y[n_games, 2];
  int<lower=0> shot_n_rows;
  int<lower=0> shot_n[shot_n_rows];
  int<lower=0> shot_goals[shot_n_rows];
  int<lower=0> shot_player_id_index[shot_n_rows];
  vector[shot_n_rows] shot_games;
  vector[n_games] away_elo_adv;
  vector[n_games] home_elo_adv;
  vector[n_games] away_elo_adv_sq;
  vector[n_games] home_elo_adv_sq;
  int<lower=0> oos_n_games;
  int oos_game_data[oos_n_games, n_col_games];
  vector[oos_n_games] oos_away_elo_adv;
  vector[oos_n_games] oos_home_elo_adv;
  vector[oos_n_games] oos_away_elo_adv_sq;
  vector[oos_n_games] oos_home_elo_adv_sq;
  matrix[oos_n_games, n_team_col] oos_home_teams;
  matrix[oos_n_games, n_team_col] oos_away_teams;
}

parameters {
  real scoring_strength_mu;
  real<lower=0> scoring_strength_sigma;
  real opportunity_strength_mu;
  real<lower=0> opportunity_strength_sigma;
  vector[shot_n_rows] raw_scoring_strength;  
  vector[shot_n_rows] raw_opportunity_strength;
  real home_elo_effect;
  real home_elo_sq_effect;
  real away_elo_effect;
  real away_elo_sq_effect;
  real beta_home;
  real beta_away;
  vector<lower=0>[2] a;
  real phi;
  real home_mean;
  real general_mean;
  vector[n_teams - 1] team_defence_strengths;
  vector[n_teams - 1] team_attack_strengths;
}

transformed parameters {
  vector[2] a_inv;
  vector[shot_n_rows] scoring_strength;
  vector[shot_n_rows] opportunity_strength;
  vector[shot_n_rows] opportunity_lambda;
  vector[shot_n_rows] p;  
  vector[n_games] home_team_lambda;
  vector[n_games] away_team_lambda;
  vector[2] mu[n_games];
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
      1, 
      n_col_games/2,
      exp(opportunity_strength_mu) * scoring_strength_mu 
    );
    away_team_lambda[i] = compute_team_lambda(
      i, 
      opportunity_lambda, 
      game_data,
      p, 
      n_col_games/2 + 1, 
      n_col_games,
      exp(opportunity_strength_mu) * scoring_strength_mu 
    );
  }
  for (i in 1:n_games) {
    mu[i][1] = exp(
      home_mean +
      home_elo_effect * home_elo_adv[i] +
      home_elo_sq_effect * home_elo_adv_sq[i] +
      beta_home * home_team_lambda[i] + 
      home_teams[i,] * team_attack_strengths + 
      away_teams[i,] * team_defence_strengths
    );
    mu[i][2] = exp(
      general_mean +
      away_elo_effect * home_elo_adv[i] +
      away_elo_sq_effect * home_elo_adv_sq[i] +
      beta_away * away_team_lambda[i] + 
      home_teams[i,] * team_defence_strengths + 
      away_teams[i,] * team_attack_strengths
    );
  }
  for (i in 1:2) {
    a_inv[i] = 1.0 / a[i];
  }
}

model {
  home_mean ~ normal(0,5);
  general_mean ~ normal(0,5);
  phi ~ normal(0, 8);
  a[1] ~ lognormal(0.1, 0.4);
  a[2] ~ lognormal(0.1, 0.4);
  raw_scoring_strength ~ normal(0,1);
  raw_opportunity_strength ~ normal(0,1);
  opportunity_strength_mu ~ normal(0, 31);
  opportunity_strength_sigma ~ uniform(0, 50);
  scoring_strength_mu ~ normal(0, 31);
  scoring_strength_sigma ~ uniform(0, 50);
  shot_n ~ poisson(shot_games[shot_player_id_index] .* opportunity_lambda);
  shot_goals ~ binomial(shot_n, p);
  home_elo_effect ~ normal(0,10);
  home_elo_sq_effect ~ normal(0,10);
  away_elo_effect ~ normal(0,10);
  away_elo_sq_effect ~ normal(0,10);
  beta_home ~ normal(0, 5);
  beta_away ~ normal(0, 5);

  target += bnb_cost(Y, phi, mu, a_inv, n_games);
}

generated quantities {
	real default_opportunity_lambda;
	real default_scoring_p;
	vector[oos_n_games] oos_home_mu;
	vector[oos_n_games] oos_away_mu;
	vector[oos_n_games] oos_home_team_lambda;
	vector[oos_n_games] oos_away_team_lambda;
  for (i in 1:oos_n_games) {
    default_opportunity_lambda = exp(normal_rng(opportunity_strength_mu, opportunity_strength_sigma));
    default_scoring_p = inv_logit(normal_rng(scoring_strength_mu, scoring_strength_sigma));
    oos_home_team_lambda[i] = compute_team_lambda(
      i, 
      opportunity_lambda, 
      oos_game_data,
      p, 
      1, 
      n_col_games/2,
      default_opportunity_lambda * default_scoring_p 
    );
    oos_away_team_lambda[i] = compute_team_lambda(
      i, 
      opportunity_lambda, 
      oos_game_data,
      p, 
      n_col_games/2 + 1, 
      n_col_games,
      default_opportunity_lambda * default_scoring_p 
    );
    oos_home_mu[i] = exp(
      home_mean +
      beta_home * oos_home_team_lambda[i] +
      home_elo_effect * oos_home_elo_adv[i] + 
      home_elo_sq_effect * oos_home_elo_adv_sq[i] +
      home_teams[i,] * team_attack_strengths + 
      away_teams[i,] * team_defence_strengths
    );
    oos_away_mu[i] = exp(
			general_mean +
      beta_away * oos_away_team_lambda[i] +
      away_elo_effect * oos_home_elo_adv[i] + 
      away_elo_sq_effect * oos_home_elo_adv_sq[i] +
      oos_home_teams[i,] * team_defence_strengths + 
      oos_away_teams[i,] * team_attack_strengths
    );
	}
}
