source("src/main/R/storage.R")
source("src/main/R/bnb_util.R")

library(data.table)
library(elo)
library(ggplot2)
library(rstan)
rstan_options(auto_write = TRUE)
#options(mc.cores = parallel::detectCores()) #
options(mc.cores = 4) 
library(stringr)
library(dplyr) 
library(magrittr) 
library(RPostgreSQL)
options(width = 120)
rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores()) #options(mc.cores = 2) 



lineups <- load_lineups("Veikkausliiga") %>% filter(game_id %in% game_id)
all_games <- load_games(sport_name = "Jalkapallo", "Veikkausliiga")
games <- all_games$games
game_ids <- intersect(unique(games$game_id), unique(lineups$game_id))
games <- filter(games, game_id %in% game_ids)
lineups <- filter(lineups, game_id %in% game_ids)

oos_games <- all_games$oos[1:min(15, nrow(all_games$oos)),]
teams <- unique(c(games$home_team,games$away_team))
games$home_team_index <- match(games$home_team, teams)
games$away_team_index <- match(games$away_team, teams)
oos_games$home_team_index <- match(oos_games$home_team, teams)
oos_games$away_team_index <- match(oos_games$away_team, teams)



player_stats <- load_player_stats("Veikkausliiga")
player_ids <- unique(lineups$player_id)
lineups$player_index <- match(lineups$player_id, player_ids)
player_stats$player_id_index <- match(player_stats$player_id, player_ids)
player_stats <- player_stats[complete.cases(player_stats),]
player_stats$shots <- mapply(function(x,y) max(x,y), player_stats$shots, player_stats$goals)


make_game_data <- function(lineups) {
  res <- lineups %>%
    group_by(game_id) %>%
    do((function(df) {
      home_players <- filter(df, team_type == "home")$player_index
      away_players <- filter(df, team_type == "away")$player_index
      as.data.frame(
        t(c(home_players, away_players)),
        stringsAsFactors = FALSE
      ) 
    })(.))
}

lineups_wide <- make_game_data(lineups)

find_most_recent_game <- function(games, team) {
  res <- filter(games, home_team == team | away_team == team) %>%
    arrange(game_date) %>%
    tail(n = 1)
  is_home <- res$home_team == team
  list(
    game_id = res$game_id, 
    team_type_in_game = ifelse(is_home, "home", "away")
  )
}

find_most_recent_lineup <- function(raw_lineups, games, team, team_type, game_id) {
  recent <- find_most_recent_game(games, team)
  recent_game_id <- recent$game_id
  recent_team_type <- recent$team_type_in_game
  lineup <- filter(raw_lineups, game_id == recent_game_id & team_type == recent_team_type)
  lineup$game_id <- game_id
  lineup$team_type <- team_type
  lineup
}

oos_lineups <- oos_games %>% rowwise() %>%
  do((function(df) { 
    home <- df$home_team
    home_res <- find_most_recent_lineup(lineups, games, home, "home", df$game_id)
    away <- df$away_team
    away_res <- find_most_recent_lineup(lineups, games, away, "away", df$game_id)
    bind_rows(home_res, away_res)
  })(.)) 

games <- arrange(games, game_date)
games$home_won <- with(games, ifelse(
  home_team_goals == away_team_goals, 0.5,
  ifelse(home_team_goals > away_team_goals, 1.0, 0)
))

elos <- elo.run(home_won ~ home_team + away_team, data = games, k = 22)
all_elo_ranks <- as.data.frame(elos) 
all_elo_ranks$game_id <- games$game_id
all_elo_ranks$elo.A %<>% {./100}
all_elo_ranks$elo.B %<>% {./100}
all_elo_ranks <- all_elo_ranks[sapply(games$game_id, function(d) which(all_elo_ranks$game_id == d)),]
home_elo_adv <- all_elo_ranks$elo.A - all_elo_ranks$elo.B
away_elo_adv <- all_elo_ranks$elo.B - all_elo_ranks$elo.A
home_elo_adv_sq <- sign(home_elo_adv) * (home_elo_adv ^ 2)
away_elo_adv_sq <- sign(away_elo_adv) * (away_elo_adv ^ 2)
final_elos <- final.elos(elos) / 100

oos_home_elo_adv <- final_elos[oos_games$home_team] - final_elos[oos_games$away_team]
oos_away_elo_adv <- final_elos[oos_games$away_team] - final_elos[oos_games$home_team]
oos_home_elo_adv_sq <- sign(oos_home_elo_adv) * (oos_home_elo_adv ^ 2)
oos_away_elo_adv_sq <- sign(oos_away_elo_adv) * (oos_away_elo_adv ^ 2)

game_data <- make_game_data(lineups)
game_data <- as.data.frame(game_data)
game_data <- game_data[sapply(games$game_id, function(d) which(game_data$game_id == d)),]

oos_game_data <- make_game_data(oos_lineups) %>%
  ungroup 
oos_game_data <- oos_game_data[sapply(oos_games$game_id, function(d) which(oos_game_data$game_id == d)),]
oos_game_data %<>% select(-game_id) %>% as.matrix

games$away_team %<>% factor
lvls <- levels(games$away_team)
games$home_team %<>% factor(levels = lvls)
oos_games$home_team %<>% factor(levels=lvls)
oos_games$away_team %<>% factor(levels=lvls)
stan_game_data <- game_data[,2:ncol(game_data)] %>% as.matrix

stan_data <- 
  list(
    n_games = nrow(game_data),
    n_col_games = 22,
    n_teams = length(teams),
    home_elo = all_elo_ranks$elo.A,
    away_elo = all_elo_ranks$elo.B,
    game_data = stan_game_data,
    away_elo_adv = away_elo_adv,
    home_elo_adv = home_elo_adv, 
    away_elo_adv_sq = away_elo_adv_sq,
    home_elo_adv_sq = home_elo_adv_sq,
    oos_away_elo_adv = oos_away_elo_adv,
    oos_home_elo_adv = oos_home_elo_adv,
    oos_away_elo_adv_sq = oos_away_elo_adv_sq,
    oos_home_elo_adv_sq = oos_home_elo_adv_sq,
    Y = cbind(games$home_team_goals, games$away_team_goals),
    shot_n_rows = nrow(player_stats),
    shot_player_id_index = player_stats$player_id_index,   
    shot_goals = player_stats$goals,
    shot_games = player_stats$games,
    shot_n = player_stats$shots,
    oos_n_games = nrow(oos_game_data),    
    oos_game_data = oos_game_data,
    home_teams = model.matrix(~home_team, games)[,-1],
    away_teams = model.matrix(~away_team, games)[,-1],
    oos_home_teams = model.matrix(~home_team, oos_games)[,-1],
    oos_away_teams = model.matrix(~away_team, oos_games)[,-1],
    n_team_col = length(unique(games$home_team)) - 1
  )

res <- 
  stan(  
    "src/main/R/model.stan",
    data = stan_data,
    refresh = 1,
    iter = 5000,
    chains = 4,   
    init = list(
      list(phi = 0.5, home_elo_effect = 0.4, away_elo_effect = 0.3, beta_home = 0.45, beta_away = 0.5, a = c(1.01, 0.99)),
      list(phi = 0.6, home_elo_effect = 0.4, away_elo_effect = 0.3, beta_home = 0.6, beta_away = 0.5, a = c(1.01, 0.99)),
      list(phi = 0.54, home_elo_effect = 0.4, away_elo_effect = 0.3, beta_home = 0.4, beta_away = 0.5, a = c(1.01, 0.99)),
      list(phi = 0.34, home_elo_effect = 0.4, away_elo_effect = 0.3, beta_home = 0.51, beta_away = 0.5, a = c(1.01, 0.99))
    ),
    control = list(
      adapt_delta = 0.99,
      max_treedepth = 16
    )
  )

date_str <- Sys.Date()
#date_str <- "2018-09-18"
dir.create(paste0("r_models/", date_str))
pred_dir <- paste0("predictions/", date_str)
dir.create(pred_dir, recursive = TRUE)
path <- paste0("r_models/", date_str, "/model.rds")
save(res, file = path)

sampled_values <- rstan::extract(res, c("oos_home_mu", "oos_away_mu","a","phi"))
mus <- rstan::extract(res, "mu")[[1]]
home_mus <- sampled_values$oos_home_mu
away_mus <- sampled_values$oos_away_mu
a <- sampled_values$a
phi <- sampled_values$phi
indices <- sample(1:nrow(a), 200)
phi_data <- phi[indices]
a_data <- a[indices,]

oos_home_l <- rstan::extract(res, "oos_home_team_lambda")[[1]]
oos_away_l <- rstan::extract(res, "oos_away_team_lambda")[[1]]
home_l <- rstan::extract(res, "home_team_lambda")[[1]]
away_l <- rstan::extract(res, "away_team_lambda")[[1]]

betas <- rstan::extract(res, "beta")[[1]]

elo_effect <- rstan::extract(res, "home_elo_effect")[[1]]
elo_effect <- rstan::extract(res, "away_elo_effect")[[1]]
elo_sq_effect <- rstan::extract(res, "home_elo_sq_effect")[[1]]
gm <- rstan::extract(res, "general_mean")[[1]]
hm <- rstan::extract(res, "home_mean")[[1]]



find_probs <- function(home_mus, away_mus, i, phi_data, a_data, indices) {
	mu_data <- data.frame(
		home = home_mus[,i],
		away = away_mus[,i]
	)[indices,]
	res <- matrix(rep(0, 10 * 10), ncol=10, nrow=10)
	k <- 0
	for (j in 1:nrow(mu_data)) {
		new_res <- bnb_sample(mu_data[j,], a_data[j,], phi_data[j])
		if (sum(is.na(new_res)) == 0) {
			res <- res + new_res
			k <- k + 1
		}
	}
	res <- res / k
	res
}

more_goals_than <- function(goals_table, x = 2.5) {
  m1 <- matrix(rep(0:(nrow(goals_table) - 1), ncol(goals_table)), byrow = FALSE, ncol = ncol(goals_table))
  m2 <- matrix(rep(0:(ncol(goals_table) - 1), nrow(goals_table)), byrow = TRUE, ncol = ncol(goals_table))
  mat <- m1 + m2
  sum(goals_table[mat > x])/sum(goals_table)
}

for (i in 1:ncol(home_mus)) {
	probability_mat <- find_probs(home_mus, away_mus, i, phi_data, a_data, indices)
	away_win <- sum(probability_mat[upper.tri(probability_mat)])
	draw <- sum(diag(probability_mat))
	home_win <- sum(probability_mat[lower.tri(probability_mat)])
	home <- oos_games[i,]$home_team
	away <- oos_games[i,]$away_team
	filename <- paste0(pred_dir, "/", gsub(" ", "_", home), "-", gsub(" ", "_", away), ".csv")
  sink(filename)
  cat(paste(rep("-", 80), collapse = ""), "\n")
  cat(home, "vs", away, "\n")
  cat("Goals:\n")
  print(round(probability_mat, 3))
  cat("P(#Goals > 2.5) = ", more_goals_than(probability_mat),"\n", sep = "")
  probs <- c("1" = home_win, "x" = draw, "2" = away_win)
  cat("Probs:\n")
  print(round(probs,2))
  cat("Implied odds\n")
  print(round(1 / probs,2))
  sink(NULL)
}




mus <- mu_data[sample(1:nrow(mu_data), 100),]
apply(mus,1,function(d) {
		
})

predictions <- rstan::extract(res, "oos_result")[[1]]


ht_lambda <- rstan::extract(res, "home_team_lambda")[[1]] %>% colMeans
at_lambda <- rstan::extract(res, "away_team_lambda")[[1]] %>% colMeans

home_post <- rstan::extract(res, "home_team_post_goals")[[1]] 
results$row <- 1:nrow(results)
true_goals <- results[,c("row", "home")]
hx <- melt(home_post) %>% inner_join(true_goals, by = c(Var2 = "row"))
away_post <- rstan::extract(res, "away_team_post_goals")[[1]]
results$hp <- home_post
results$ap <- away_post
plottable <- results



for (i in 1:nrow(oos)) {
  filename <- paste0(pred_dir, "/", oos$game_id[i], ".csv")
  sink(filename)
  cat(paste(rep("-", 80), collapse = ""), "\n")
  cat(oos_games$home_team[i], "vs", oos_games$away_team[i], "\n")
  cat("Goals:\n")
  print(goals_table)
  cat("P(#Goals > 2.5) = ", more_goals_than(goals_table),"\n", sep = "")
  home_win <- sum(goals_table[lower.tri(goals_table)])
  away_win <- sum(goals_table[upper.tri(goals_table)])
  draw <- sum(diag(goals_table))
  probs <- c("1" = home_win / total, "x" = draw / total, "2" = away_win / total)
  cat("Probs:\n")
  print(round(probs,2))
  cat("Implied odds\n")
  print(round(1 / probs,2))
  sink(NULL)
}


hm <- rstan::extract(res, "home_mean")[[1]]
gm <- rstan::extract(res, "general_mean")[[1]]
as <- rstan::extract(res, "a")[[1]]
ss <- rstan::extract(res, "opportunity_lambda")[[1]]
means <- colSums(ss) / nrow(ss)
ps <- rstan::extract(res, "p")[[1]]
pmeans <- colSums(ps) / nrow(ps)
os <- rstan::extract(res, "other_p")[[1]]


ht <- rstan::extract(res, "home_team_effect")[[1]]
htmean <- mean(ht)

htl <- rstan::extract(res, "home_team_lambda")[[1]]
atl <- rstan::extract(res, "away_team_lambda")[[1]]

x <- rstan::extract(res, "opportunity_strength_sigma")[[1]]
x <- rstan::extract(res, "opportunity_strength_sigma")[[1]]
x <- rstan::extract(res, "opportunity_strength_sigma")[[1]]
x <- rstan::extract(res, "away_elo_effect")[[1]]
x <- rstan::extract(res, "elo_sq_effect")[[1]]
x <- rstan::extract(res, "beta")[[1]]
x <- rstan::extract(res, "scoring_strength_mu")[[1]]
x <- rstan::extract(res, "home_team_effect")[[1]]
x <- rstan::extract(res, "scoring_strength_mu")[[1]]
x <- rstan::extract(res, "team_scoring_strength")[[1]]
x <- rstan::extract(res, "team_defensive_strength")[[1]]

traceplot(res, pars = "opportunity_strength_sigma")
traceplot(res, pars = "home_team_effect")
traceplot(res, pars = paste0("p[", sample(1:300,10), "]"))
traceplot(res, pars = "oos_home_team_goals[1]")



team_scoring_strengths <- rstan::extract(res, "team_scoring_strength")[[1]]
tst_means <- colSums(team_scoring_strengths)/nrow(team_scoring_strengths)


team_defensive_strengths <- rstan::extract(res, "team_scoring_strength")[[1]]
colnames(team_defensive_strengths) <- names(team_index)
df <- melt(team_defensive_strengths)
df <- filter(df, Var2 %in% c("FC Inter", "KuPS"))
ggplot(df, aes(x = value)) + theme_classic() + geom_histogram(bins = 50) + facet_grid(Var2~.)
tds <- colSums(team_defensive_strengths)/nrow(team_defensive_strengths)

a <- rstan::extract(res, "oos_home_team_goals")[[1]]
b <- rstan::extract(res, "home_team_post_goals")[[1]]

hgoals <- rstan::extract(res, "home_team_post_goals")[[1]]
agoals <- rstan::extract(res, "away_team_post_goals")[[1]]
hgoals <- rstan::extract(res, "oos_home_team_goals")[[1]]
agoals <- rstan::extract(res, "oos_away_team_goals")[[1]]

hg_all <- apply(hgoals, 1, sum)
ag_all <- apply(agoals, 1, sum)

ts <- rstan::extract(res, "team_attack_strengths")[[1]]

games_meta <- results %>% inner_join(games, by = "game_id")
plot_n_goals <- function(team1, team2, games_meta, hgoals, agoals) {
  games <- filter(games_meta, home_team %in% c(team1, team2) & away_team %in% c(team1, team2))$game_id
  game_indices <- which(results$game_id %in% games)
  goal_sums <- hgoals[,game_indices] + agoals[,game_indices] > 2.5
  df <- melt(goal_sums)
  ggplot(df, aes(x = value)) + geom_bar() + theme_classic() + facet_wrap(~Var2)
}
