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

events_years <- c(2018, 2017, 2016 2015)
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

player_goals <- goals %>%
  mutate(event_type = ifelse(is.na(event_type), "unknown", event_type)) %>%
  group_by(player_id, event_type) %>%
  summarize(goals = sum(score), n = n())

stan_data <- 
  list(
    n_rows = nrow(player_goals),
    n_players = length(unique(player_goals$player_id)),
    player_id_index = player_goals$player_id_index,   
    goals = player_goals$goals,
    n = player_goals$n
  )
  
  
