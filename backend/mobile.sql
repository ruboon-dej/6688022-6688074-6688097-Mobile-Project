-- ------------------------------------------------------------------
-- Fresh schema for the mobile app
-- ------------------------------------------------------------------
DROP DATABASE IF EXISTS mobile;
CREATE DATABASE mobile CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mobile;

-- -------------------------------------------------
-- Users / profile  (used by /auth/* and /profile)
-- bcrypt hashes are ~60 chars; store as VARBINARY(60)
-- -------------------------------------------------
DROP TABLE IF EXISTS profile;
CREATE TABLE profile (
  id            INT            NOT NULL PRIMARY KEY,
  display_name  VARCHAR(190)   NOT NULL,
  email         VARCHAR(190)   NOT NULL,
  password_hash VARBINARY(100) NULL,   -- nullable for quick seeded users
  avatar_url    VARCHAR(255)   NULL,
  bio           VARCHAR(500)   NULL,
  updated_at    TIMESTAMP      NULL DEFAULT NULL,
  UNIQUE KEY uq_profile_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed demo users (no password yet)
INSERT INTO profile (id, display_name, email, bio)
VALUES
  (1, 'Demo User #1', 'user1@example.com', ''),
  (2, 'Demo User #2', 'user2@example.com', '')
ON DUPLICATE KEY UPDATE display_name=VALUES(display_name);

-- -----------------------------------------
-- Tasks  (/tasks CRUD)
-- -----------------------------------------
DROP TABLE IF EXISTS tasks;
CREATE TABLE tasks (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT           NOT NULL,
  title      VARCHAR(255)  NOT NULL,
  urgency    TINYINT       NOT NULL DEFAULT 3,        -- 1=high,2=med,3=low
  due_date   DATE          NULL,
  done       TINYINT(1)    NOT NULL DEFAULT 0,
  created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_tasks_user FOREIGN KEY (user_id)
    REFERENCES profile(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_tasks_user ON tasks(user_id);
CREATE INDEX idx_tasks_user_due ON tasks(user_id, due_date);
CREATE INDEX idx_tasks_user_done ON tasks(user_id, done);

-- -----------------------------------------
-- Goal  (/goal GET/PUT)
-- -----------------------------------------
DROP TABLE IF EXISTS goals;
CREATE TABLE goals (
  user_id   INT         NOT NULL PRIMARY KEY,
  progress  DECIMAL(6,3) NOT NULL DEFAULT 0,
  CONSTRAINT fk_goals_user FOREIGN KEY (user_id)
    REFERENCES profile(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -----------------------------------------
-- Nutrients target & computed current
--   kind: 'current' (computed on backend) or 'goal' (editable)
--   your backend writes/reads both here
-- -----------------------------------------
DROP TABLE IF EXISTS nutrients;
CREATE TABLE nutrients (
  user_id    INT          NOT NULL,
  kind       ENUM('current','goal') NOT NULL,
  veg        DECIMAL(6,3) NOT NULL DEFAULT 0,
  carb       DECIMAL(6,3) NOT NULL DEFAULT 0,
  protein    DECIMAL(6,3) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                              ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, kind),
  CONSTRAINT fk_nutr_user FOREIGN KEY (user_id)
    REFERENCES profile(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Optional: a default goal for user #1
INSERT INTO nutrients (user_id, kind, veg, carb, protein)
VALUES (1, 'goal', 0.45, 0.33, 0.22)
ON DUPLICATE KEY UPDATE veg=VALUES(veg), carb=VALUES(carb), protein=VALUES(protein);

-- -----------------------------------------
-- Food catalog per user (used to pre-fill entries; optional)
-- -----------------------------------------
DROP TABLE IF EXISTS food_items;
CREATE TABLE food_items (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  user_id     INT          NOT NULL,
  name        VARCHAR(190) NOT NULL,
  veg_g       DECIMAL(7,2) NOT NULL DEFAULT 0,    -- grams per unit
  carb_g      DECIMAL(7,2) NOT NULL DEFAULT 0,
  protein_g   DECIMAL(7,2) NOT NULL DEFAULT 0,
  per_unit_g  DECIMAL(7,2) NOT NULL DEFAULT 100,  -- 100 -> values are per 100g
  created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_food_user FOREIGN KEY (user_id)
    REFERENCES profile(id) ON DELETE CASCADE ON UPDATE CASCADE,
  UNIQUE KEY uq_food_user_name (user_id, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_food_user ON food_items(user_id);

-- Sample foods for user 1
INSERT INTO food_items (user_id, name, veg_g, carb_g, protein_g, per_unit_g) VALUES
(1, 'Seafood Paella', 40, 55, 25, 100),
(1, 'Garden Salad',   80, 10,  5, 100)
ON DUPLICATE KEY UPDATE
  veg_g=VALUES(veg_g), carb_g=VALUES(carb_g),
  protein_g=VALUES(protein_g), per_unit_g=VALUES(per_unit_g);

-- -----------------------------------------
-- Nutrient history (what the user ate)
--   used by /nutrients/history (GET/POST/PUT/DELETE)
-- -----------------------------------------
DROP TABLE IF EXISTS nutrient_history;
CREATE TABLE nutrient_history (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT          NOT NULL,
  eaten_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  food_id    INT          NULL,                  -- optional link to catalog
  name       VARCHAR(190) NULL,                  -- ad-hoc name when no food_id
  veg_g      DECIMAL(7,2) NOT NULL DEFAULT 0,    -- actual grams for this entry
  carb_g     DECIMAL(7,2) NOT NULL DEFAULT 0,
  protein_g  DECIMAL(7,2) NOT NULL DEFAULT 0,
  amount_g   DECIMAL(7,2) NULL,
  note       VARCHAR(255) NULL,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_nh_user FOREIGN KEY (user_id)
    REFERENCES profile(id) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_nh_food FOREIGN KEY (food_id)
    REFERENCES food_items(id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_nh_user_time ON nutrient_history(user_id, eaten_at);

-- Seed one history item for today (user 1)
INSERT INTO nutrient_history (user_id, eaten_at, food_id, name, veg_g, carb_g, protein_g, amount_g, note)
VALUES (1, NOW(), NULL, 'Seafood Paella', 40, 55, 25, 300, 'Lunch');

-- -----------------------------------------
-- Diary (/diary GET/POST/DELETE)
-- -----------------------------------------
DROP TABLE IF EXISTS diary_entries;
CREATE TABLE diary_entries (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT          NOT NULL,
  entry_date DATE         NOT NULL,
  title      VARCHAR(255) NOT NULL DEFAULT '',
  content    TEXT         NULL,
  mood       VARCHAR(30)  NULL,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP    NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_diary_user FOREIGN KEY (user_id)
    REFERENCES profile(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_diary_user_date ON diary_entries(user_id, entry_date);

-- -----------------------------------------
-- Calendar (/calendar/events GET/POST/DELETE)
-- -----------------------------------------
DROP TABLE IF EXISTS calendar_events;
CREATE TABLE calendar_events (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT          NOT NULL,
  title      VARCHAR(255) NOT NULL,
  note       TEXT         NULL,
  starts_at  DATETIME     NOT NULL,
  ends_at    DATETIME     NULL,
  all_day    TINYINT(1)   NOT NULL DEFAULT 0,
  color      VARCHAR(16)  NULL,                  -- e.g. '#FFAA00'
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_cal_user FOREIGN KEY (user_id)
    REFERENCES profile(id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_cal_user_time ON calendar_events(user_id, starts_at);

-- -------------------------------------------------
-- Done.
-- -------------------------------------------------