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
      if (nrow(potential_specials)) {
        index <- potential_specials$index[1]
        row <- nrow(ei_maalit) - (index - 1)
        ei_maalit$score[row] <- 1
      } else if (nrow(potential_laukaus)) {
        if (nrow(potential_laukaus)) {
          index <- potential_laukaus$index[1]
          row <- nrow(ei_maalit) - (index - 1)
          ei_maalit$score[row] <- 1       
        }
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

goals_data <- goals %>%
  mutate(team_type = ifelse(team == home_team, "home", "away")) %>%
  mutate(opposing_team = ifelse(team == home_team, away_team, home_team)) %>%
  group_by(game_id, team, player_id, event_type, team_type, opposing_team) %>%
  summarize(goals = sum(score), n = n())

na_goals <-filter(goals_data, is.na(event_type))
goals_data <- filter(goals_data, !is.na(event_type))


lineup_files <- paste0("data/lineups/2018-08-01/", 2016:2018, ".csv")
lineups <- Map(function(d) { fread(d) }, lineup_files) %>% rbindlist %>% as.tbl

missing_lineups <- lineups %>% group_by(game_id) %>% summarize(n = n()) %>% filter(n != 22)
lineups <- filter(lineups, !game_id %in% missing_lineups$game_id)

goalies <- lineups %>% filter(player_position == "maalivahti") %>% 
  select(game_id, player_id, team_type) %>%
  rename(opposing_team_goalie = player_id) %>%
  mutate(join_team_type = ifelse(team_type == "home", "away", "home")) %>%
  select(-team_type)

position_goals <- inner_join(lineups, goals_data, by = c("game_id", "player_id", "team_type")) 
event_types <- unique(position_goals$event_type)
opposing_teams <- position_goals %>% select(game_id, team_type, team, opposing_team) %>% unique


dirpath <- paste0("r_models/", Sys.Date())
dir.create(dirpath)
for (event_type_f in event_types) {
  position_goals_event <- filter(position_goals, event_type == event_type_f)
  no_events <- anti_join(lineups, position_goals_event, by = c("game_id", "player_id", "team_type")) %>%
    inner_join(opposing_teams, by = c("game_id", "team_type")) %>%
    rowwise() %>%
    do((function(df) {
      res <- as.data.frame(df, stringsAsFactors = F)
      res$event_type <- event_type_f
      res$goals <- 0
      res$n <- 0
      res
    })(.)) 
  dataset <- rbindlist(list(no_events, position_goals_event), use.names = T) %>% as.tbl %>%
    inner_join(goalies, by = c(game_id = "game_id", team_type = "join_team_type"))

  #goals_data %<>%
  #  inner_join(goalies, by = c(game_id = "game_id", team_type = "join_team_type"))

  set_index <- function(df, variable) {
    df <- as.data.frame(df)
    values <- unique(df[,variable])
    indeces <- 1:length(values) %>% setNames(values)
    res_name <- paste0(variable, "_index")
    df[,res_name] <- indeces[as.character(df[,variable])]
    as.tbl(df)
  }

  set_indeces <- function(df, variables) {
    for (var in variables) {
      df <- set_index(df, var) 
    }
    df
  }

  goals_model_discrete_variables <- c(
    "player_id",
    "team_type",
    "team",
    "opposing_team",
    "player_position",
    "opposing_team_goalie")

  goals_data <- set_indeces(dataset, goals_model_discrete_variables)
  goals_model_variables <- c(
    paste0(goals_model_discrete_variables, "_index"),
    "goals", "n")
  goals_for_stan <- as.list(goals_data[,goals_model_variables])
  goals_for_stan$nrow <- length(goals_for_stan[[1]])
  n_goalies <- length(unique(goals_for_stan$opposing_team_goalie))
  goals_for_stan$n_goalies <- n_goalies
  n_players <- length(unique(goals_for_stan$player_id))
  goals_for_stan$n_players <- n_players
  n_teams <- length(unique(goals_data$opposing_team))
  goals_for_stan$n_teams <- n_teams
  stan_path <-"src/main/R/events/goals_model_4.stan"
  # 227 secs, 150 kk
  # 1000 secs 400 iters
  system(paste0("date > ", dirpath, "/", event_type_f, "_start.txt"))
  res <- stan(stan_path, refresh = 1, data = goals_for_stan, iter = 2500, 
              chains = 4, control = list(adapt_delta = 0.8, max_treedepth = 14))
  fp <- paste0(dirpath, "/", event_type_f, ".rds")
  save(res, file = fp)
  goals_data$index <- 1:nrow(goals_data)
  game_indices <- select(goals_data, game_id, team, event_type, player_id, 
                         player_position, team_type, index)
  gps <- rstan::extract(res, "goals_posterior")[[1]]
  gps_molten <- melt(gps)
  simulated <- inner_join(gps_molten, game_indices, by = c(Var2 = "index"))
  save(simulated, file = paste0(dirpath, "/simulations_", event_type_f, ".rds"))
  rm(res)
  rm(simulated)
  gc()
}
