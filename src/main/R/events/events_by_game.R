library(data.table)
library(ggplot2)
library(rstan)
rstan_options(auto_write = TRUE)
#options(mc.cores = parallel::detectCores()) #
options(mc.cores = 4) 
library(stringr)
library(dplyr)
library(magrittr)
options(width = 120)
rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores()) #options(mc.cores = 2) 

plot_trace <- function(res, variable, which_to_plot) {
  traceplot(res, paste0(variable, "[", which_to_plot, "]"))
}

events_years <- c(2018, 2017, 2016)
events_files <- paste0("data/events/events_", events_years, ".csv")

events <- events_files %>% Map(fread, .) %>% rbindlist(use.names = T) %>% as.tbl
events$is_additional_time %<>% as.logical
events$minutes %<>% as.numeric
events$player_id <- str_extract(events$player_link, "/([0-9])*/") %>% gsub("/", "",.) %>% as.numeric 
events %<>% unique

goal_events <- events %>%
  mutate(event_type = ifelse(grepl("Laukaus", event_type), "Laukaus", event_type)) %>%
  filter(event_type %in% c("Laukaus", "Kulmapotku", "Vapaapotku", "Maali"))

set_goals <- function(df) {
  df$global_index <- nrow(df):1
  maalit <- filter(df, event_type == "Maali")
  ei_maalit <- filter(df, event_type != "Maali")
  ei_maalit$score <- 0
  ei_maalit$index <- nrow(ei_maalit):1
  na_goals <- filter(ei_maalit, FALSE)
  if (nrow(maalit)) {
    for (i in 1:nrow(maalit)) {
      maali <- as.list(maalit[i,])
      maali_gi <- maali$global_index
      minute <- maali$minutes
      potentials <- filter(
        ei_maalit, 
        team == maali$team & 
          global_index <= maali_gi &
          (minute - minutes) <= 1
      )
      potential_specials <- filter(potentials, event_type != "Laukaus")
      potential_laukaus <- filter(potentials, event_type == "Laukaus") 
      if (nrow(potential_laukaus)) {
        index <- potential_laukaus$index[1]
        row <- nrow(ei_maalit) - (index - 1)
        ei_maalit$score[row] <- 1       
      } else if (nrow(potential_specials)) {
        index <- potential_specials$index[1]
        row <- nrow(ei_maalit) - (index - 1)
        ei_maalit$score[row] <- 1
      } else {
        res <- as.data.frame(maali, stringsAsFactors = FALSE) 
        res$event_type <- NA
        res$index <- NA
        res$score <- 1
        na_goals <- rbindlist(list(na_goals, res))
      }
    }
  }
  if (nrow(na_goals)) {
    na_goals$score <- 1
  }
  res <- rbindlist(list(na_goals, ei_maalit))
  select(res, -global_index, -index)
}

goals <- goal_events %>%
  group_by(date, away_team, home_team) %>%
  do(set_goals(.)) %>%
  ungroup %>%
  mutate(team = gsub("\\(|\\)", "", team)) 

event_game <- goals %>%
  mutate(event_type = ifelse(is.na(event_type), "unknown", event_type)) %>%
  select(player_id, game_id, event_type, score) %>%
  mutate(n = 1)

lineup_files <- paste0("data/lineups/2018-08-01/", 2016:2018, ".csv")
raw_lineups <- Map(function(d) { fread(d) }, lineup_files) %>% rbindlist %>% as.tbl
missing_lineups <- raw_lineups %>% group_by(game_id) %>% summarize(n = n()) %>% filter(n != 22)
lineups <- filter(raw_lineups, !game_id %in% missing_lineups$game_id) %>%
  filter(game_id %in% event_game$game_id)
lineup_game <- lineups %>%
  rowwise() %>%
  do((function(df) {
    res <- as.data.frame(df, stringsAsFactors = F)[rep(1,4),]
    res$event_type <- c("Laukaus", "Vapaapotku", "Kulmapotku", "unknown")
    res$score <- 0
    res$n <- 0
    res
  })(.)) %>%
  select(game_id, player_id, event_type, score,n) %>%
  ungroup %>%
  mutate(event_type = enc2utf8(event_type))

player_goals <- filter(event_game, game_id %in% lineup_game$game_id) %>%
  bind_rows(lineup_game) %>%
  group_by(player_id, event_type) %>%
  summarize(goals = sum(score), n = sum(n), games = n_distinct(game_id))

shot_goals <- filter(player_goals, event_type == "Laukaus")
other_goals <- filter(player_goals, event_type != "Laukaus") %>%
  group_by(player_id) %>%
  summarize(goals = sum(goals), games = sum(games))

set_index <- function(df, variable, indices = c()) {
  df <- as.data.frame(df)
  values <- unique(df[,variable])
  if (!length(indices)) {
    indices <- 1:length(values) %>% setNames(values)
  }
  res_name <- paste0(variable, "_index")
  df[,res_name] <- indices[as.character(df[,variable])]
  list(df = as.tbl(df), indices = indices)
}

shot_goals %<>% filter(player_id %in% other_goals$player_id)
other_goals %<>% filter(player_id %in% shot_goals$player_id)
shot_index <- set_index(shot_goals, "player_id")
shot_goals <- shot_index$df
player_index <- shot_index$indices
other_goals <- set_index(other_goals, c("player_id"), indices = player_index)[[1]]

game_data <- lineups %>%
  group_by(game_id) %>%
  do((function(df) {
    home_players <- filter(df, team_type == "home")$player_id
    away_players <- filter(df, team_type == "away")$player_id
    home_players <- player_index[as.character(home_players)] %>% setNames(NULL)
    away_players <- player_index[as.character(away_players)] %>% setNames(NULL)
    as.data.frame(
      t(c(home_players, away_players)),
      stringsAsFactors = FALSE
    ) 
  })(.)) 

teams <- unique(events$home_team)
team_index <- 1:length(teams) %>% setNames(teams)
home_teams <- events %>% select(game_id, home_team, away_team) %>% unique
tmp <- set_index(home_teams, "home_team", team_index)
tmp_df <- tmp$df
tmp <- set_index(tmp_df, "away_team", team_index)
team_data <- tmp$df

results <- events %>%
  filter(event_type == "Maali") %>%
  mutate(team = gsub("\\(|\\)","",team)) %>%
  mutate(home = ifelse(home_team == team, "home", "away")) %>%
  group_by(game_id, team, home) %>%
  summarize(goals = n()) %>%
  ungroup  %>% 
  dcast(game_id ~ home, fill = 0)


results %<>% filter(game_id %in% game_data$game_id) %>% 
  arrange(game_id) 
home_team_goals <- results$home
away_team_goals <- results$away
game_data %<>% filter(game_id %in% results$game_id) %>% 
  arrange(game_id) %>%
  ungroup %>%
  select(-game_id) %>%
  as.matrix

team_data %<>% filter(game_id %in% results$game_id) %>% arrange(game_id)

stan_data <- 
  list(
    n_games = nrow(game_data),
    n_col_games = 22,
    n_teams = length(team_index),
    game_data = game_data,
    home_team_goals = home_team_goals,
    away_team_goals = away_team_goals,
    home_team_index = team_data$home_team_index,
    away_team_index = team_data$away_team_index,
    shot_n_rows = nrow(shot_goals),
    shot_player_id_index = shot_goals$player_id_index,   
    shot_goals = shot_goals$goals,
    shot_games = shot_goals$games,
    shot_n = shot_goals$n,
    other_player_id_index = other_goals$player_id_index,
    other_goals = other_goals$goals,
    other_games = other_goals$games,
    other_n_rows = nrow(other_goals)
  )
res <- 
  stan(  
    "src/main/R/events/model.stan",
    data = stan_data,
    refresh = 1,
    iter = 7500,
    chains = 4,   
    control = list(
      adapt_delta = 0.99,
      max_treedepth = 16
    )
)
path <- paste0("r_models/", Sys.Date(), "/model.rds")
save(res, file = path)
htp_goals <- rstan::extract(res, "home_team_post_goals")[[1]]
atp_goals <- rstan::extract(res, "away_team_post_goals")[[1]]
examples_path <- paste0("r_models/", Sys.Date(), "/examples")
for (i in sample(1:nrow(results), 10)) {
  game_id <- results$game_id[i]
  res <- table(htp_goals[,i], atp_goals[,i]) / nrow(htp_goals)
  write.table(as.matrix(res), paste0(examples_path, "/", game_id, ".csv"),
              row.names = T, col.names = T, sep = ",")
}

ss <- rstan::extract(res, "opportunity_lambda")[[1]]
means <- colSums(ss) / nrow(ss)
ps <- rstan::extract(res, "p")[[1]]
pmeans <- colSums(ps) / nrow(ps)
os <- rstan::extract(res, "other_p")[[1]]

ts <- rstan::extract(res, "team_strength")[[1]]
tmeans <- colSums(ts) / nrow(ts)

ht <- rstan::extract(res, "home_team_effect")[[1]]
htmean <- mean(ht)

htl <- rstan::extract(res, "home_team_lambda")[[1]]
atl <- rstan::extract(res, "away_team_lambda")[[1]]


team_scoring_strengths <- rstan::extract(res, "team_scoring_strength")[[1]]
tst_means <- colSums(team_scoring_strengths)/nrow(team_scoring_strengths)


