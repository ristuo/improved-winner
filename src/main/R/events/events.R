library(data.table)
library(ggplot2)
library(rstan)
library(stringr)
library(dplyr)
library(magrittr)
options(width = 120)
rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores()) #options(mc.cores = 2) 
events_files <- c(
  "events_2015.csv",
  "events_2016.csv",
  "events_2017.csv",
  "events_2018.csv")

events <- events_files %>% Map(fread, .) %>% rbindlist %>% as.tbl
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
  do(set_goals(.))

goals <- mutate(goals, game_id = paste(away_team, home_team, date, sep = "_"))

goals_by_player <- goals %>%
  filter(event_type %in% c("Laukaus", "Kulmapotku", "Vapaapotku")) %>%
  group_by(player_id, event_type) %>%
  summarize(goals = sum(score), n = n(), games = n_distinct(game_id))

date_str <- Sys.Date()
dir_path <- paste0("r_models/", date_str)
dir.create(dir_path, recursive = T, showWarnings = F)
n_iter <- 20000
player_probs_list <- list()
for (event_type_f in unique(goals_by_player$event_type)) {
  df <- goals_by_player %>% filter(event_type == event_type_f)
  player_ids <- unique(df$player_id)
  player_to_index <- 1:length(player_ids) %>% setNames(player_ids)
  df$player_index <- player_to_index[as.character(df$player_id)]
  for_stan <- list(
    nrows = nrow(df),
    player_indices = df$player_index,
    n = df$n,
    goals = df$goals)
  stan_path <- "src/main/R/events/model.stan"
  res <- stan(stan_path, refresh = 100, data = for_stan, iter = n_iter, chains = 4,control = list(adapt_delta = 0.9999))
  save(res, file = paste0(dir_path, "/", event_type_f, ".rd"))
  ps <- rstan::extract(res, "p")[[1]]
  probs <- colSums(ps) / nrow(ps)
  player_probs <- data.frame(
    player_index = 1:length(probs),
    p = probs,
    event_type = event_type_f,
    stringsAsFactors = FALSE) %>% as.tbl
  player_probs$player_id <- player_ids[player_probs$player_index]
  player_probs %<>% select(-player_index)
  player_probs_list <- c(player_probs_list, list(player_probs))
}
player_probs <- rbindlist(player_probs_list) %>% as.tbl
with_probs <- goals %>%
  inner_join(player_probs, by = c("player_id", "event_type"))
expected_goals <- group_by(with_probs, team, home_team, away_team, date) %>%
  summarize(eg = sum(p), goals = sum(score), n_events = n())


# add estimates on the number of na type goals team gets per game
# better would be use player level data, but that requires more scraping

na_goals_by_team <- filter(goals, is.na(event_type)) %>% 
  group_by(team) %>% summarize(goals = n())
games_per_team <- events %>% group_by(team) %>% summarize(games = n_distinct(date)) 
na_goals <- left_join(games_per_team, na_goals_by_team, by = "team") %>%
  mutate(goals = ifelse(is.na(goals), 0, goals))
games_data <- group_by(goals, home_team, away_team, date, player_id) %>% summarize(n = n())
for_stan <- list(
  n = nrow(na_goals),
  goals = na_goals$goals,
  games = na_goals$games)
stan_path <- "src/main/R/events/na_team_level_model.stan"
res <- stan(stan_path, refresh = 100, data = for_stan, iter = 40000, chains = 4,control = list(adapt_delta = 0.9999999, max_treedepth = 20))
ps <- rstan::extract(res, "p")[[1]]
means <- colSums(ps) / nrow(ps)
na_egs_team <- data.frame(
  team = na_goals$team,
  na_eg = means, 
  stringsAsFactors = FALSE)
#plottable <- melt(ps)
#ggplot(plottable, aes(x = value)) + 
#  geom_histogram(bins = 100) +
#  theme_classic() +
#  facet_wrap(~Var2)

expected_goals <- inner_join(expected_goals, na_egs_team, by = "team") %>%
  mutate(corrected_eg = (eg + na_eg))

write.table(expected_goals, file = paste0(dir_path, "/expected_goals.csv"), sep = ",",
  row.names = FALSE, col.names = TRUE)

# huom pitäisi tallentaa myös indeksit pelaajille!
