library(RPostgreSQL)
library(stringr)
library(dplyr)
library(magrittr)
library(configr)

DEFAULT_PATH <- "/home/risto/Code/hobbies/veikkausliiga/secrets/db-config.yaml"


make_unique_game_id <- function(res) {
  res$game_id <- paste0(res$season, res$game_set, res$game_id)
  res
}

load_conf_from_env <- function() {
  username <- Sys.getenv("DB_USER")
  password <- Sys.getenv("DB_PASSWORD")
  host <- Sys.getenv("DB_HOST")
  dbname <- Sys.getenv("DB_NAME")
  list(
    username = username,
    password = password,
    host = host,
    dbname = dbname
  )
}

load_conf_from_file <- function() {
  read.config(file=DEFAULT_PATH)$db
}

load_db_conf <- function() {
  load_conf_from_file()
}

get_connection <- function() {
  drv <- dbDriver("PostgreSQL")
  conf <- load_db_conf()
  con <- dbConnect(
    drv, 
    dbname = conf$dbname,
    host = conf$host, 
    port = conf$port,
    user = conf$username, 
    password = conf$password
  )
  con
}

load_games <- function(sport_name, tournament) {
  con <- get_connection()
  qs <- paste0("
    SELECT 
      *
    FROM
      games
    WHERE
      sport_name='",sport_name,"' AND 
      tournament='",tournament,"'
  ")   
  res <- dbGetQuery(con, qs) %>% as.tbl
  res$home_team <- str_trim(res$home_team)
  res$away_team <- str_trim(res$away_team)
  res <- make_unique_game_id(res)
  games <- filter(res, !is.na(home_team_goals)) 
  oos <- filter(res, is.na(home_team_goals)) %>%
    arrange(game_date) %>%
    filter(game_date >= Sys.Date())
  dbDisconnect(con)  
  list(
    games=games,
    oos=oos
  )
}

load_player_stats <- function(tournament) {
  if (tournament == "Veikkausliiga") {
    tbl_name = "veikkausliiga_player_stats"
  } else if (tournament == "Liiga") {
    tbl_name = "liiga_player_stats"
    return(load_liiga_player_stats())
  } else {
    stop(paste0("Unknown tournament ", tournament))
  }
  con <- get_connection()
  qs <- paste0("
    SELECT 
      sum(shots) as shots,
      sum(goals) as goals,
      sum(games) as games,
      nimi,
      player_id
    FROM ",
      tbl_name,"
    WHERE
      season > '2015'
    GROUP BY
      nimi,
      player_id
  ")   
  res <- dbGetQuery(con, qs)
  dbDisconnect(con)
  as.tbl(res)
}

load_liiga_player_stats <- function() {
  con <- get_connection()
  qs <- paste0("
    SELECT 
      sum(shots) as shots,
      sum(goals) as goals,
      sum(games) as games,
      player_name as nimi,
      player_id
    FROM
      liiga_player_stats
    WHERE
      season > '2015'
    GROUP BY
      nimi,
      player_id
  ")   
  res <- dbGetQuery(con, qs)
  dbDisconnect(con)
  as.tbl(res)
}

load_lineups <- function(tournament) {
  con <- get_connection()
  qs <- paste0("
    SELECT 
      team,
      game_id,
      player_id,
      season,
      team_type,
      game_set
    FROM
      lineups 
    WHERE
      league='",tournament,"'
  ")   
  res <- dbGetQuery(con, qs)
  dbDisconnect(con)
  res <- make_unique_game_id(res)
  as.tbl(res)  
}
