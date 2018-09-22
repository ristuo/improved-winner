create table results (
  game_id varchar(100) primary key,
  home_team_goals integer,
  away_team_goals integer
);

create table games (
  event_name varchar(100),
  event_id varchar(100) unique,
  game_id varchar(100) primary key references results on delete cascade,
  home_team varchar(100),
  away_team varchar(100),
  game_date date,
  game_time time with time zone
);

create table odds (
  time timestamp with time zone,
  category_name varchar(100),
  odds float,
  id integer,
  event_id varchar(100),
  sport_name varchar(100),
  short_name varchar(100), 
  event_name varchar(100),
  status varchar(100),
  tournament_name varchar(100),
  name varchar(100),
  dl_time timestamp with time zone,
  close_time timestamp with time zone,
  open_time timestamp with time zone,
  agency varchar(100),
  primary key(event_id, id)
);


