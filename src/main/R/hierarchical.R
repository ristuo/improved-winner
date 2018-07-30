library(data.table)
library(ggplot2)
library(rstan)
rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores())
library(dplyr)
library(stringr)
library(magrittr)
library(reshape2)
read_eg_games <- function() {
  eg <- fread("r_models/2018-07-29/expected_goals.csv") %>% as.tbl
  eg$team %<>% gsub("\\(|\\)","",.)
  eg$home <- ifelse(eg$team == eg$home_team, "team1_goals", "team2_goals")
  res <- dcast(eg, date +home_team + away_team ~ home, value.var = "corrected_eg") %>%
    rename("team1" = "home_team") %>%
    rename("team2" = "away_team")
  teams <- unique(c(res$team1, res$team2))
  team_to_index <- 1:length(teams) %>% setNames(teams)   
  res$team1_index <- team_to_index[res$team1]
  res$team2_index <- team_to_index[res$team2]
  res$goal_diff <- res$team1_goals - res$team2_goals
  res$team1_goals_discrete <- round(res$team1_goals,0)
  res$team2_goals_discrete <- round(res$team2_goals,0)
  res
}


read_normal_games <- function() {
  games <- fread("data/16-17_pelit.csv")
  games[,c("team1", "team2")] <- as.data.frame(
    str_split(games$Ottelu, " - ", simplify = TRUE),
    stringsAsFactors = FALSE)
  games[,c("team1_goals", "team2_goals")] <- as.data.frame(
    str_split(games$Tulos, " — ", simplify = TRUE),
    stringsAsFactors = FALSE)
  games$team1_goals %<>% as.numeric
  games$team2_goals %<>% as.numeric
  index_to_teams <- unique(c(games$team1, games$team2)) %>% setNames(1:(length(.) - 0))
  teams_to_index <- 1:(length(index_to_teams) - 0) %>% setNames(index_to_teams)
  games$team1_index <- teams_to_index[games$team1]
  games$team2_index <- teams_to_index[games$team2]
  games$date <- str_extract(games$Pvm, "[0-9]{1,2}.[0-9]{1,2}.[0-9]{4}")
  date <- games$date[1]
  for (i in 1:nrow(games)) {
    if (is.na(games$date[i])) {
      games$date[i] <- date
    } else {
      date <- games$date[i]
    }
  }
  games
}

games <- read_eg_games()
scores <- read_normal_games() %>% select(date, team1, team2, team1_goals, team2_goals) %>%
  rename(team1_goals_act = "team1_goals") %>%
  rename(team2_goals_act = "team2_goals")
both <- scores %>% inner_join(games, by = c("date", "team1", "team2")) %>% as.tbl

for_stan <- list(
  n_games = nrow(games),
  n_teams = length(unique(c(games$team1, games$team2))),
  team1_goals = games$team1_goals,
  team2_goals = games$team2_goals,
  team1_index = games$team1_index,
  team2_index = games$team2_index)
stan_path <- "src/main/R/games2.stan"
res <- stan(stan_path, refresh = 100, data = for_stan, iter = 2000, chains = 4,control = list(adapt_delta = 0.999, max_treedepth = 20))




results <- rstan::extract(res, "result")[[1]]
game_probs <- function(team1, team2) {
  index <- which(games$team1 == team1 & games$team2 == team2)[1]
  ps <- table(results[,index]) / nrow(results)
  ps
}








for_stan <- list(
  n_games = nrow(games),
  n_teams = length(unique(c(games$team1, games$team2))),
  team1_goals = games$team1_goals,
  team2_goals = games$team2_goals,
  team1_index = games$team1_index,
  team2_index = games$team2_index)
stan_path <- "src/main/R/games.stan"
res <- stan(stan_path, refresh = 100, data = for_stan, iter = 2000, chains = 2,control = list(adapt_delta = 0.999, max_treedepth = 20))








home_ga <- rstan::extract(res, "hometeam_ga")[[1]]






mean_lambdas <- apply(rstan::extract(res, "lambda")[[1]], 2:3, mean)
diag(mean_lambdas) <- 0
team1_pred <- mapply(function(i,j) mean_lambdas[i,j], games$team1_index, games$team2_index)
team2_pred <- mapply(function(i,j) mean_lambdas[j,i], games$team1_index, games$team2_index)
pred_vs_truth <- data.frame(
  pred = c(team1_pred, team2_pred),
  truth = c(games$team1_goals, games$team2_goals)) %>% as.data.table


lambdas <- rstan::extract(res, "advantage")[[1]]
team_name_table <- select(games, team1, team2, team1_index, team2_index)  %>% unique
plottable_lambdas <- melt(lambdas) %>% 
  as.tbl %>% 
  filter(value < 4) %>% 
  setNames(c("iterations", "team1_index", "team2_index", "lambda")) %>%
  filter(team1_index != team2_index) %>%
  inner_join(team_name_table, by = c(team1_index = "team1_index", team2_index = "team2_index"))
ggplot(plottable_lambdas, aes(x = lambda)) + 
  geom_histogram() + 
  theme_classic() + 
  facet_grid(team1 ~ team2)

sigma <- rstan::extract(res, "sigma")[[1]]

team1_goals <- rstan::extract(res, "team1_g")[[1]]
team2_goals <- rstan::extract(res, "team2_g")[[1]]

game_probs <- function(team1, team2) {
  index <- which(games$team1 == team1 & games$team2 == team2)[1]
  table(team1_goals[,index], team2_goals[,index]) / (nrow(team1_goals) / 100)
}

game_1x2_probs <- function(team1, team2) {
  tab <- game_probs(team1, team2)
  draw <- sum(diag(tab))
  t1_win <- sum(tab[lower.tri(tab)])
  t2_win <- sum(tab[upper.tri(tab)])
  list(t1_win = t1_win, draw = draw, t2_win = t2_win)
}


htga <- rstan::extract(res, "hometeam_ga")[[1]]
htda <- rstan::extract(res, "hometeam_da")[[1]]








