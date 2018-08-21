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
options(width = 120)
rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores()) #options(mc.cores = 2) 

plot_trace <- function(res, variable, which_to_plot) { traceplot(res, paste0(variable, "[", which_to_plot, "]"))
}
make_game_data <- function(lineups) {
  res <- lineups %>%
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

oos <- data.frame(
  game_id = c(
    970094, 
    970095, 
    970097, 
    970098, 
    970099, 
    970100, 
    970101, 
    970102, 
    970103,
    970104,
    970105,
    1,
    2
),
  home = c(
    "FC Honka", 
    "VPS", 
    "FC Lahti", 
    "KuPS", 
    "RoPS", 
    "TPS", 
    "FC Inter", 
    "HJK", 
    "IFK Mariehamn", 
    "FC Lahti", 
    "SJK",
    "HJK",
    "KuPS"),
  away = c(
    "TPS", 
    "SJK", 
    "FC Inter", 
    "PS Kemi", 
    "IFK Mariehamn", 
    "VPS", 
    "KuPS",
    "PS Kemi",
    "FC Honka",
    "RoPS",
    "Ilves",
    "KuPS",
    "HJK"),
  stringsAsFactors = FALSE
)
games <- select(events, "game_id", "home_team", "away_team", "date") %>% unique %>%
  mutate(date = as.Date(date, "%d.%m.%Y")) %>%
  filter(game_id %in% raw_lineups$game_id)
find_most_recent_game <- function(games, team) {
  res <- filter(games, home_team == team | away_team == team) %>%
    arrange(date) %>%
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
oos_known_lineups <- filter(raw_lineups, game_id %in% oos$game_id)
missing <- oos %>% filter(!game_id %in% oos_known_lineups$game_id)
oos_lineups <- missing %>% rowwise() %>%
  do((function(df) { 
    home <- df$home
    home_res <- find_most_recent_lineup(raw_lineups, games, home, "home", df$game_id)
    away <- df$away
    away_res <- find_most_recent_lineup(raw_lineups, games, away, "away", df$game_id)
    bind_rows(home_res, away_res)
  })(.)) %>% bind_rows(oos_known_lineups)

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


game_data <- make_game_data(lineups)

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
oos_home_team_index <- setNames(team_index[oos$home], NULL)
oos_away_team_index <- setNames(team_index[oos$away], NULL)
oos_game_data <- make_game_data(oos_lineups) %>%
  arrange(game_id) %>%
  ungroup %>%
  select(-game_id) %>%
  as.matrix

full_games <- results %>% inner_join(team_data, by = "game_id") %>%
  mutate(home_won = ifelse(home == away, 0.5, ifelse(home > away, 1, 0)))
elos <- elo.run(home_won ~ home_team + away_team, data = full_games, k = 22)
all_elo_ranks <- as.data.frame(elos)
final_elos <- final.elos(elos)
oos_home_elo <- final_elos[oos$home] 
oos_away_elo <- final_elos[oos$away]

stan_data <- 
  list(
    n_games = nrow(game_data),
    n_col_games = 22,
    n_teams = length(team_index),
    home_elo = all_elo_ranks$elo.A,
    away_elo = all_elo_ranks$elo.B,
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
    other_n_rows = nrow(other_goals),
    oos_n_games = nrow(oos_game_data),    
    oos_game_data = oos_game_data, 
    oos_home_team_index = oos_home_team_index,
    oos_away_team_index = oos_away_team_index,
    oos_home_elo = oos_home_elo,
    oos_away_elo = oos_away_elo
  )
res <- 
  stan(  
    "src/main/R/model.stan",
    data = stan_data,
    refresh = 5,
    iter = 10000,
    chains = 4,   
    control = list(
      adapt_delta = 0.8,
      max_treedepth = 15
    )
  )
dir.create(paste0("r_models/", Sys.Date()))
path <- paste0("r_models/", Sys.Date(), "/model.rds")
save(res, file = path)
htp_goals <- rstan::extract(res, "home_team_post_goals")[[1]]
atp_goals <- rstan::extract(res, "away_team_post_goals")[[1]]
examples_path <- paste0("r_models/", Sys.Date(), "/examples")
for (i in sample(1:nrow(results), 10)) {
  game_id <- results$game_id[i]
  results_table <- table(htp_goals[,i], atp_goals[,i]) / nrow(htp_goals)
  write.table(as.matrix(res), paste0(examples_path, "/", game_id, ".csv"),
              row.names = T, col.names = T, sep = ",")
}

more_goals_than <- function(goals_table, x = 2.5) {
  m1 <- matrix(rep(0:(nrow(goals_table) - 1), ncol(goals_table)), byrow = FALSE, ncol = ncol(goals_table))
  m2 <- matrix(rep(0:(ncol(goals_table) - 1), nrow(goals_table)), byrow = TRUE, ncol = ncol(goals_table))
  mat <- m1 + m2
  sum(goals_table[mat > x])/sum(goals_table)
}

oos_hg <- rstan::extract(res, "oos_home_team_goals")[[1]]
oos_ag <- rstan::extract(res, "oos_away_team_goals")[[1]]
for (i in 1:nrow(oos)) {
  cat(paste(rep("-", 80), collapse = ""), "\n")
  goals_table <- table(oos_hg[,i], oos_ag[,i])
  cat(oos$home[i], "vs", oos$away[i], "\n")
  cat("Goals:\n")
  print(goals_table)
  cat("P(#Goals > 2.5) = ", more_goals_than(goals_table),"\n", sep = "")
  total <- nrow(oos_hg)
  home_win <- sum(goals_table[lower.tri(goals_table)])
  away_win <- sum(goals_table[upper.tri(goals_table)])
  draw <- sum(diag(goals_table))
  probs <- c("1" = home_win / total, "x" = draw / total, "2" = away_win / total)
  cat("Probs:\n")
  print(round(probs,2))
  cat("Implied odds\n")
  print(round(1 / probs,2))
}


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
x <- rstan::extract(res, "elo_effect")[[1]]
x <- rstan::extract(res, "beta")[[1]]
x <- rstan::extract(res, "scoring_strength_mu")[[1]]
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

games_meta <- results %>% inner_join(games, by = "game_id")
plot_n_goals <- function(team1, team2, games_meta, hgoals, agoals) {
  games <- filter(games_meta, home_team %in% c(team1, team2) & away_team %in% c(team1, team2))$game_id
  game_indices <- which(results$game_id %in% games)
  goal_sums <- hgoals[,game_indices] + agoals[,game_indices] > 2.5
  df <- melt(goal_sums)
  ggplot(df, aes(x = value)) + geom_bar() + theme_classic() + facet_wrap(~Var2)
}
