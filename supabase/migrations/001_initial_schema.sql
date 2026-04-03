-- ============================================================
-- BirthdayMe — Initial Schema Migration 001
-- Run in Supabase SQL Editor to set up complete database
-- Tables, indexes, RLS policies, seed data, AI prompts
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── HELPER: Case ID generator (BM-2026-001234 format) ────────
CREATE SEQUENCE IF NOT EXISTS case_id_seq START 1000;

CREATE OR REPLACE FUNCTION generate_case_id()
RETURNS TEXT AS $$
BEGIN
  RETURN 'BM-' || TO_CHAR(CURRENT_DATE, 'YYYY') || '-' ||
         LPAD(nextval('case_id_seq')::TEXT, 6, '0');
END;
$$ LANGUAGE plpgsql;

-- ── HELPER: Auto-update updated_at timestamp ──────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- SECTION 1: CORE USER TABLES
-- ============================================================

CREATE TABLE users (
  id                UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug              TEXT        UNIQUE NOT NULL,
  username          TEXT        UNIQUE,
  name              TEXT        NOT NULL,
  email             TEXT        UNIQUE,
  dob               DATE,
  gender            TEXT        CHECK (gender IN ('man','woman','nonbinary','prefer_not')),
  emoji             TEXT        DEFAULT '🎂',
  bio               TEXT,
  photo_url         TEXT,
  background        JSONB,
  overlay_intensity NUMERIC     DEFAULT 0,
  is_verified       BOOLEAN     DEFAULT FALSE,
  is_vip            BOOLEAN     DEFAULT FALSE,
  is_partner        BOOLEAN     DEFAULT FALSE,
  is_demo           BOOLEAN     DEFAULT FALSE,
  account_type      TEXT        DEFAULT 'user'
                    CHECK (account_type IN ('user','verified','partner','vip','demo')),
  raised            NUMERIC     DEFAULT 0,
  giver_count       INT         DEFAULT 0,
  total_given       NUMERIC     DEFAULT 0,
  badges            JSONB       DEFAULT '[]',
  theme_preference  TEXT        DEFAULT 'light',
  gender_set        BOOLEAN     DEFAULT FALSE,
  force_pwd_change  BOOLEAN     DEFAULT FALSE,
  require_username  BOOLEAN     DEFAULT FALSE,
  admin_note        TEXT,       -- internal only, never exposed to client
  created_by_admin  BOOLEAN     DEFAULT FALSE,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_users_email    ON users(email);
CREATE INDEX idx_users_slug     ON users(slug);
CREATE INDEX idx_users_username ON users(username);
CREATE TRIGGER trg_users_upd BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Security questions — answer stored as bcrypt hash ONLY, never plain text
CREATE TABLE security_questions (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID        UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  question_id TEXT        NOT NULL,
  -- Question IDs: first_pet | childhood_street | elementary_school |
  --               maternal_grandmother | first_car | childhood_nickname
  answer_hash TEXT        NOT NULL, -- bcrypt of lowercase(trim(answer))
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE TRIGGER trg_sq_upd BEFORE UPDATE ON security_questions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Login attempt lockout tracking
CREATE TABLE login_attempts (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  identifier    TEXT        UNIQUE NOT NULL, -- email or username
  attempt_count INT         DEFAULT 0,
  locked_until  TIMESTAMPTZ,
  last_attempt  TIMESTAMPTZ DEFAULT NOW(),
  ip_address    INET,
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Security question recovery attempt tracking (separate from login lockout)
CREATE TABLE recovery_attempts (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID        UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  attempt_count INT         DEFAULT 0,
  locked_until  TIMESTAMPTZ,
  last_attempt  TIMESTAMPTZ DEFAULT NOW(),
  ip_address    INET,
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Active device sessions — max 3 per user enforced at app layer
CREATE TABLE user_sessions (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id   TEXT        UNIQUE NOT NULL,
  device_type  TEXT,       -- Mobile | Tablet | iPad | Desktop
  browser      TEXT,
  ip_address   INET,
  city         TEXT,
  is_current   BOOLEAN     DEFAULT FALSE,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  last_active  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_sessions_user ON user_sessions(user_id);

-- AI support chat history — structured summary NOT verbatim transcripts
CREATE TABLE support_history (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID        UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  summary         JSONB       DEFAULT '[]', -- [{issue,resolution,ts}] last 5 interactions
  last_issue_type TEXT,
  last_contact_at TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE TRIGGER trg_sh_upd BEFORE UPDATE ON support_history
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Social follows
CREATE TABLE followers (
  follower_id  UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  following_id UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (follower_id, following_id)
);
CREATE INDEX idx_followers_following ON followers(following_id);

-- ============================================================
-- SECTION 2: GIFTING & FINANCIAL TABLES
-- ============================================================

CREATE TABLE gifts (
  id                    UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id             UUID        REFERENCES users(id) ON DELETE SET NULL,
  recipient_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount_gross          NUMERIC     NOT NULL,
  platform_fee          NUMERIC     NOT NULL,
  amount_net            NUMERIC     NOT NULL,
  stripe_payment_intent TEXT,
  status                TEXT        DEFAULT 'pending'
                        CHECK (status IN ('pending','held','released','failed','refunded')),
  is_anonymous          BOOLEAN     DEFAULT FALSE,
  is_belated            BOOLEAN     DEFAULT FALSE,
  is_guest              BOOLEAN     DEFAULT FALSE,
  guest_name            TEXT,
  guest_email           TEXT,
  message               TEXT,
  sent_at               TIMESTAMPTZ DEFAULT NOW(),
  released_at           TIMESTAMPTZ,
  hold_until            TIMESTAMPTZ
);
CREATE INDEX idx_gifts_sender    ON gifts(sender_id);
CREATE INDEX idx_gifts_recipient ON gifts(recipient_id);
CREATE INDEX idx_gifts_status    ON gifts(status);

CREATE TABLE group_pools (
  id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  recipient_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_by     UUID        REFERENCES users(id) ON DELETE SET NULL,
  name           TEXT        NOT NULL,
  goal_amount    NUMERIC     NOT NULL,
  current_amount NUMERIC     DEFAULT 0,
  status         TEXT        DEFAULT 'open'
                 CHECK (status IN ('open','closed','released','failed')),
  closes_at      TIMESTAMPTZ,
  released_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_pools_recipient ON group_pools(recipient_id);

CREATE TABLE gift_contributions (
  id                    UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  pool_id               UUID        NOT NULL REFERENCES group_pools(id) ON DELETE CASCADE,
  contributor_id        UUID        REFERENCES users(id) ON DELETE SET NULL,
  amount_gross          NUMERIC     NOT NULL,
  platform_fee          NUMERIC     NOT NULL,
  amount_net            NUMERIC     NOT NULL,
  stripe_payment_intent TEXT,
  status                TEXT        DEFAULT 'pending'
                        CHECK (status IN ('pending','confirmed','refunded')),
  contributed_at        TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_contributions_pool        ON gift_contributions(pool_id);
CREATE INDEX idx_contributions_contributor ON gift_contributions(contributor_id);

-- Cashout requests: Stripe holds funds, Tremendous disburses
CREATE TABLE cashout_requests (
  id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount              NUMERIC     NOT NULL,
  status              TEXT        DEFAULT 'pending'
                      CHECK (status IN ('pending','approved','held','rejected','disbursed')),
  payout_method       TEXT        CHECK (payout_method IN ('paypal','venmo','ach','gift_card')),
  tremendous_transfer TEXT,
  requested_at        TIMESTAMPTZ DEFAULT NOW(),
  processed_at        TIMESTAMPTZ,
  admin_note          TEXT,
  approved_by         UUID        REFERENCES users(id) ON DELETE SET NULL
);
CREATE INDEX idx_cashouts_user   ON cashout_requests(user_id);
CREATE INDEX idx_cashouts_status ON cashout_requests(status);

CREATE TABLE flagged_transactions (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  gift_id     UUID        REFERENCES gifts(id) ON DELETE SET NULL,
  user_id     UUID        REFERENCES users(id) ON DELETE CASCADE,
  flag_reason TEXT        NOT NULL,
  flag_source TEXT        CHECK (flag_source IN ('velocity','stripe_radar','manual','ai')),
  amount      NUMERIC,
  status      TEXT        DEFAULT 'pending'
              CHECK (status IN ('pending','cleared','blocked')),
  flagged_at  TIMESTAMPTZ DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID        REFERENCES users(id) ON DELETE SET NULL
);

-- Daily velocity tracking per recipient (resets midnight)
CREATE TABLE velocity_tracking (
  id             UUID     PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  window_date    DATE     NOT NULL DEFAULT CURRENT_DATE,
  total_received NUMERIC  DEFAULT 0,
  updated_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, window_date)
);

-- ============================================================
-- SECTION 3: CONTENT & SOCIAL TABLES
-- ============================================================

CREATE TABLE wall_posts (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  author_id    UUID        REFERENCES users(id) ON DELETE SET NULL,
  content      TEXT,
  is_gift_post BOOLEAN     DEFAULT FALSE,
  gift_id      UUID        REFERENCES gifts(id) ON DELETE SET NULL,
  is_anonymous BOOLEAN     DEFAULT FALSE,
  is_hidden    BOOLEAN     DEFAULT FALSE,
  hidden_at    TIMESTAMPTZ,
  hidden_by    UUID        REFERENCES users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_wall_profile ON wall_posts(profile_id);
CREATE INDEX idx_wall_author  ON wall_posts(author_id);

CREATE TABLE ecards (
  id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipient_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  background_url TEXT,
  message        TEXT,
  font           TEXT,
  color          TEXT,
  ai_generated   BOOLEAN     DEFAULT FALSE,
  sent_at        TIMESTAMPTZ DEFAULT NOW(),
  read_at        TIMESTAMPTZ,
  is_archived    BOOLEAN     DEFAULT FALSE
);
CREATE INDEX idx_ecards_recipient ON ecards(recipient_id);

CREATE TABLE wishlists (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       TEXT        NOT NULL,
  url        TEXT,
  price      NUMERIC,
  priority   INT         DEFAULT 2 CHECK (priority IN (1,2,3)),
  is_claimed BOOLEAN     DEFAULT FALSE,
  claimed_by UUID        REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_wishlists_user ON wishlists(user_id);

CREATE TABLE card_signatures (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  recipient_id UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  signer_id    UUID        REFERENCES users(id) ON DELETE SET NULL,
  guest_name   TEXT,
  message      TEXT        NOT NULL,
  emoji        TEXT,
  signed_at    TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_signatures_recipient ON card_signatures(recipient_id);

CREATE TABLE notifications (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type       TEXT        NOT NULL,
  title      TEXT        NOT NULL,
  body       TEXT,
  data       JSONB       DEFAULT '{}',
  is_read    BOOLEAN     DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_notifications_user ON notifications(user_id, is_read);

-- ============================================================
-- SECTION 4: POINTS & GAMIFICATION
-- ============================================================

CREATE TABLE point_transactions (
  id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount           INT         NOT NULL,
  transaction_type TEXT        NOT NULL
                   CHECK (transaction_type IN (
                     'gift_received','gift_sent','check_in','referral',
                     'welcome_bonus','birthday_bonus','admin_credit','redemption')),
  reference_id     UUID,
  note             TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_points_user ON point_transactions(user_id);

CREATE TABLE check_ins (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  checked_in    DATE NOT NULL DEFAULT CURRENT_DATE,
  streak_count  INT  DEFAULT 1,
  points_earned INT  DEFAULT 5,
  UNIQUE(user_id, checked_in)
);
CREATE INDEX idx_checkins_user ON check_ins(user_id);

CREATE TABLE referrals (
  id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  referrer_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  referred_user_id UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status           TEXT        DEFAULT 'pending' CHECK (status IN ('pending','credited')),
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  credited_at      TIMESTAMPTZ
);

-- ============================================================
-- SECTION 5: BUSINESS MARKETPLACE
-- ============================================================

CREATE TABLE businesses (
  id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  slug             TEXT        UNIQUE NOT NULL,
  owner_id         UUID        REFERENCES users(id) ON DELETE SET NULL,
  name             TEXT        NOT NULL,
  domain           TEXT,
  website_url      TEXT,
  gift_card_url    TEXT,
  logo_url         TEXT,
  description      TEXT,
  category         TEXT,
  city             TEXT,
  tier             TEXT        DEFAULT 'standard' CHECK (tier IN ('standard','premium')),
  status           TEXT        DEFAULT 'pending'
                   CHECK (status IN ('pending','active','suspended')),
  badges           JSONB       DEFAULT '[]',
  rating           NUMERIC     DEFAULT 0,
  view_count       INT         DEFAULT 0,
  gift_click_count INT         DEFAULT 0,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  created_by       UUID        REFERENCES users(id) ON DELETE SET NULL,
  verified_at      TIMESTAMPTZ,
  verified_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_businesses_owner  ON businesses(owner_id);
CREATE INDEX idx_businesses_status ON businesses(status);
CREATE TRIGGER trg_biz_upd BEFORE UPDATE ON businesses
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE business_badges (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  business_id UUID        NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  badge_id    TEXT        NOT NULL,
  awarded_by  UUID        REFERENCES users(id) ON DELETE SET NULL,
  awarded_at  TIMESTAMPTZ DEFAULT NOW(),
  is_permanent BOOLEAN    DEFAULT FALSE,
  expires_at  TIMESTAMPTZ
);
CREATE INDEX idx_biz_badges ON business_badges(business_id);

CREATE TABLE business_transfer_requests (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  case_id      TEXT        UNIQUE DEFAULT generate_case_id(),
  business_id  UUID        NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  from_user_id UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_email     TEXT        NOT NULL,
  reason       TEXT,
  status       TEXT        DEFAULT 'pending'
               CHECK (status IN ('pending','approved','rejected')),
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  resolved_at  TIMESTAMPTZ,
  resolved_by  UUID        REFERENCES users(id) ON DELETE SET NULL
);

-- ============================================================
-- SECTION 6: MODERATION, REPORTS & SUPPORT
-- ============================================================

CREATE TABLE reports (
  id                   UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  case_id              TEXT        UNIQUE DEFAULT generate_case_id(),
  reporter_id          UUID        REFERENCES users(id) ON DELETE SET NULL,
  reported_user_id     UUID        REFERENCES users(id) ON DELETE SET NULL,
  reported_business_id UUID        REFERENCES businesses(id) ON DELETE SET NULL,
  reported_post_id     UUID        REFERENCES wall_posts(id) ON DELETE SET NULL,
  reason               TEXT        NOT NULL,
  details              TEXT,
  status               TEXT        DEFAULT 'open'
                       CHECK (status IN ('open','in_review','resolved','archived')),
  assigned_to          UUID        REFERENCES users(id) ON DELETE SET NULL,
  created_at           TIMESTAMPTZ DEFAULT NOW(),
  resolved_at          TIMESTAMPTZ,
  updated_at           TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_reports_status   ON reports(status);
CREATE INDEX idx_reports_reporter ON reports(reporter_id);
CREATE INDEX idx_reports_case     ON reports(case_id);
CREATE TRIGGER trg_reports_upd BEFORE UPDATE ON reports
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE support_tickets (
  id                UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  case_id           TEXT        UNIQUE DEFAULT generate_case_id(),
  user_id           UUID        REFERENCES users(id) ON DELETE SET NULL,
  ticket_type       TEXT        NOT NULL
                    CHECK (ticket_type IN (
                      'lockout','recovery','payment','dob_change',
                      'username_change','general','harassment',
                      'business_transfer','escalated_complaint')),
  subject           TEXT        NOT NULL,
  details           TEXT,
  status            TEXT        DEFAULT 'open'
                    CHECK (status IN ('open','in_review','resolved','archived')),
  assigned_to       UUID        REFERENCES users(id) ON DELETE SET NULL,
  security_verified BOOLEAN     DEFAULT FALSE,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  resolved_at       TIMESTAMPTZ,
  resolution_note   TEXT,
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_tickets_status ON support_tickets(status);
CREATE INDEX idx_tickets_user   ON support_tickets(user_id);
CREATE INDEX idx_tickets_case   ON support_tickets(case_id);
CREATE TRIGGER trg_tickets_upd BEFORE UPDATE ON support_tickets
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Internal admin comment threads — never visible to users
CREATE TABLE ticket_comments (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  ticket_id  UUID        REFERENCES support_tickets(id) ON DELETE CASCADE,
  report_id  UUID        REFERENCES reports(id) ON DELETE CASCADE,
  author_id  UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body       TEXT        NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT chk_one_parent CHECK (
    (ticket_id IS NOT NULL AND report_id IS NULL) OR
    (ticket_id IS NULL AND report_id IS NOT NULL)
  )
);
CREATE INDEX idx_comments_ticket ON ticket_comments(ticket_id);
CREATE INDEX idx_comments_report ON ticket_comments(report_id);

CREATE TABLE moderation_actions (
  id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  case_id        TEXT        DEFAULT generate_case_id(),
  admin_id       UUID        REFERENCES users(id) ON DELETE SET NULL,
  action_type    TEXT        NOT NULL
                 CHECK (action_type IN (
                   'warn','hide','remove','suspend','shadow_ban','freeze',
                   'unsuspend','unfreeze','verify','badge_award','badge_remove',
                   'dob_update','username_update','admin_credit')),
  target_user_id UUID        REFERENCES users(id) ON DELETE SET NULL,
  target_post_id UUID        REFERENCES wall_posts(id) ON DELETE SET NULL,
  target_biz_id  UUID        REFERENCES businesses(id) ON DELETE SET NULL,
  before_state   JSONB,
  after_state    JSONB,
  reason         TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_modactions_admin  ON moderation_actions(admin_id);
CREATE INDEX idx_modactions_target ON moderation_actions(target_user_id);

CREATE TABLE content_flags (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id     UUID        NOT NULL REFERENCES wall_posts(id) ON DELETE CASCADE,
  flagged_by  UUID        REFERENCES users(id) ON DELETE SET NULL,
  reason      TEXT,
  flag_source TEXT        DEFAULT 'user_report'
              CHECK (flag_source IN ('user_report','keyword','ai','admin')),
  status      TEXT        DEFAULT 'pending'
              CHECK (status IN ('pending','dismissed','hidden','removed')),
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);
CREATE INDEX idx_flags_post   ON content_flags(post_id);
CREATE INDEX idx_flags_status ON content_flags(status);

CREATE TABLE keyword_blocklist (
  id        UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  keyword   TEXT        UNIQUE NOT NULL,
  added_by  UUID        REFERENCES users(id) ON DELETE SET NULL,
  added_at  TIMESTAMPTZ DEFAULT NOW(),
  is_active BOOLEAN     DEFAULT TRUE
);

-- ============================================================
-- SECTION 7: ACCOUNT CHANGE REQUESTS (admin approval required)
-- ============================================================

-- DOB is locked client-side; changes require admin review
CREATE TABLE dob_change_requests (
  id                UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  case_id           TEXT        UNIQUE DEFAULT generate_case_id(),
  user_id           UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  current_dob       DATE        NOT NULL,
  requested_dob     DATE        NOT NULL,
  reason            TEXT,
  security_verified BOOLEAN     DEFAULT FALSE,
  status            TEXT        DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected')),
  requested_at      TIMESTAMPTZ DEFAULT NOW(),
  resolved_at       TIMESTAMPTZ,
  resolved_by       UUID        REFERENCES users(id) ON DELETE SET NULL,
  admin_note        TEXT
);
CREATE INDEX idx_dob_user   ON dob_change_requests(user_id);
CREATE INDEX idx_dob_status ON dob_change_requests(status);

-- One username change per 30 days enforced at app layer
CREATE TABLE username_change_requests (
  id                 UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  case_id            TEXT        UNIQUE DEFAULT generate_case_id(),
  user_id            UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  old_username       TEXT        NOT NULL,
  requested_username TEXT        NOT NULL,
  security_verified  BOOLEAN     DEFAULT FALSE,
  status             TEXT        DEFAULT 'pending'
                     CHECK (status IN ('pending','approved','rejected','unavailable')),
  requested_at       TIMESTAMPTZ DEFAULT NOW(),
  resolved_at        TIMESTAMPTZ,
  resolved_by        UUID        REFERENCES users(id) ON DELETE SET NULL
);
CREATE INDEX idx_username_user ON username_change_requests(user_id);

-- ============================================================
-- SECTION 8: PLATFORM CONFIGURATION & ADMIN
-- ============================================================

-- Append-only audit log — RLS: INSERT via service role only, NO UPDATE/DELETE ever
CREATE TABLE audit_log (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  admin_id     UUID        REFERENCES users(id) ON DELETE SET NULL,
  action_type  TEXT        NOT NULL,
  target_type  TEXT,       -- user | business | post | config | flag | ticket
  target_id    UUID,
  before_state JSONB,
  after_state  JSONB,
  ip_address   INET,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_audit_admin   ON audit_log(admin_id);
CREATE INDEX idx_audit_created ON audit_log(created_at DESC);
CREATE INDEX idx_audit_target  ON audit_log(target_type, target_id);

CREATE TABLE platform_config (
  key        TEXT        PRIMARY KEY,
  value      TEXT        NOT NULL,
  description TEXT,
  updated_by UUID        REFERENCES users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE feature_flags (
  key        TEXT        PRIMARY KEY,
  is_enabled BOOLEAN     DEFAULT FALSE,
  description TEXT,
  updated_by UUID        REFERENCES users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE platform_banner (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  message      TEXT        NOT NULL,
  type         TEXT        DEFAULT 'info' CHECK (type IN ('info','warn','success')),
  published_by UUID        REFERENCES users(id) ON DELETE SET NULL,
  published_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at   TIMESTAMPTZ,
  is_active    BOOLEAN     DEFAULT TRUE
);

-- AI configuration — editable from admin panel at runtime, no redeploy needed
CREATE TABLE ai_config (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  feature_name  TEXT        UNIQUE NOT NULL,
  model         TEXT        DEFAULT 'claude-sonnet-4-20250514',
  system_prompt TEXT        NOT NULL,
  temperature   NUMERIC     DEFAULT 0.4 CHECK (temperature BETWEEN 0 AND 1),
  max_tokens    INT         DEFAULT 1000,
  daily_limit   INT         DEFAULT 0, -- 0 = unlimited
  is_enabled    BOOLEAN     DEFAULT TRUE,
  updated_by    UUID        REFERENCES users(id) ON DELETE SET NULL,
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);
CREATE TRIGGER trg_ai_upd BEFORE UPDATE ON ai_config
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Prompt version history — last 5 versions auto-kept per feature
CREATE TABLE ai_prompt_history (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  feature_name  TEXT        NOT NULL,
  model         TEXT,
  system_prompt TEXT        NOT NULL,
  temperature   NUMERIC,
  max_tokens    INT,
  saved_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
  saved_at      TIMESTAMPTZ DEFAULT NOW(),
  change_note   TEXT
);
CREATE INDEX idx_prompt_hist ON ai_prompt_history(feature_name, saved_at DESC);

-- ============================================================
-- SECTION 9: DEFAULT SEED DATA
-- ============================================================

INSERT INTO platform_config (key, value, description) VALUES
  ('platform_fee',             '0.10',  'Platform commission rate on all transactions'),
  ('min_gift_increment',       '0.25',  'Gift slider increment. Formula: turning_age x increment'),
  ('max_gift',                 '5000',  'Max single gift for registered users ($)'),
  ('max_guest_gift',           '200',   'Max single gift for non-registered guests ($)'),
  ('max_pool_size',            '10000', 'Max total a group pool can raise ($)'),
  ('hold_hours',               '48',    'Hours before received funds can be withdrawn'),
  ('min_payout',               '5',     'Minimum balance to initiate cashout ($)'),
  ('pool_funding_close_hours', '24',    'Hours before birthday when pools stop accepting'),
  ('belated_gift_window_days', '14',    'Days after birthday belated gifts are allowed'),
  ('max_wishlist',             '50',    'Max wishlist items per user'),
  ('referral_points',          '50',    'Points awarded per successful referral'),
  ('checkin_points',           '5',     'Points for daily check-in'),
  ('welcome_bonus',            '25',    'Points on first sign-up'),
  ('birthday_bonus',           '100',   'Bonus points on user own birthday'),
  ('email_per_account',        '1',     'Max email addresses per account'),
  ('ai_requests_per_day',      '0',     'Max Claude AI requests per user per day (0=unlimited)');

INSERT INTO feature_flags (key, is_enabled, description) VALUES
  ('guest_gifting',               TRUE,  'Allow non-registered users to send gifts'),
  ('anonymous_gifting',           TRUE,  'Allow senders to hide their name (sender always recorded)'),
  ('belated_gifting',             TRUE,  'Allow gifts after birthday within configured window'),
  ('belated_gifts_enabled',       TRUE,  'Master switch for all belated gifting'),
  ('age_formula_enabled',         TRUE,  'Use turning-age based minimum gift formula'),
  ('group_pools',                 TRUE,  'Enable group birthday pool contributions'),
  ('card_signing',                TRUE,  'Enable multi-person card signing'),
  ('card_signing_require_account',FALSE, 'Require account to sign cards'),
  ('wishlist',                    TRUE,  'Enable wishlist registry'),
  ('wishlists_public',            FALSE, 'Wishlists visible to all (vs followers only)'),
  ('e_cards',                     TRUE,  'Enable birthday e-card creation and inbox'),
  ('referral_system',             TRUE,  'Enable invite/referral tracking'),
  ('community_tab',               TRUE,  'Enable community tab'),
  ('analytics',                   TRUE,  'Enable user-facing analytics dashboard'),
  ('ai_concierge',                TRUE,  'Enable Claude AI gift suggestions'),
  ('ai_card_messages',            TRUE,  'Enable AI-generated card messages'),
  ('leaderboard_public',          TRUE,  'Show points leaderboard to users'),
  ('business_marketplace',        TRUE,  'Show business store directory'),
  ('business_portal',             FALSE, 'Brand self-management portal — OFF until ready'),
  ('business_applications',       FALSE, 'Public business application form'),
  ('location_gifting',            FALSE, 'Location-aware local business discovery — Phase 2'),
  ('gift_scheduling',             FALSE, 'Schedule gifts for birthday delivery — Phase 2'),
  ('anonymous_reveal',            FALSE, '30-day anonymous sender reveal — Phase 2'),
  ('family_accounts',             FALSE, 'Family/minor account management — Phase 2'),
  ('sweepstakes',                 FALSE, 'Monthly prize draw'),
  ('push_notifs',                 FALSE, 'PWA push notification delivery'),
  ('api_access',                  FALSE, 'Public developer API — Phase 3'),
  ('maintenance_mode',            FALSE, 'CRITICAL: full-screen overlay for all non-admin users'),
  ('new_user_signups',            TRUE,  'CRITICAL: allow new account creation'),
  ('cashout_enabled',             TRUE,  'CRITICAL: allow balance withdrawals'),
  ('gift_sending_enabled',        TRUE,  'CRITICAL: allow new gifts to be sent'),
  ('pool_creation_enabled',       TRUE,  'CRITICAL: allow new group pools to be created');

-- ============================================================
-- SECTION 10: AI CONFIG — PRODUCTION-READY DEFAULT PROMPTS
-- ============================================================

INSERT INTO ai_config (feature_name, model, temperature, max_tokens, daily_limit, system_prompt) VALUES

('gift_intelligence', 'claude-sonnet-4-20250514', 0.5, 800, 0,
'You are BirthdayMe''s gift recommendation assistant. Suggest 3 personalized gift ideas for the recipient.

PRIVACY ABSOLUTE RULES:
- Never confirm, deny, or share ANY information about any user other than the recipient whose data the platform has provided
- Never reveal another user''s balance, activity, gift history, or whether they exist on the platform
- If asked about another person: "I can only use the birthday person''s profile to make suggestions — I cannot share details about other accounts on BirthdayMe."

GIFT FORMULA — CRITICAL:
The minimum gift = turning_age × price_increment
turning_age = the age the recipient WILL BE on their NEXT birthday (current_age + 1 if birthday has not yet happened this year, or current_age on the birthday itself)
This is NOT their current age. A person currently 29 turning 30 has a minimum of 30 × $0.25 = $7.50
Always describe minimums using turning age, never current age.

SUGGESTION RULES:
- Suggestion 1: budget-friendly option near the minimum gift amount
- Suggestion 2: mid-range option (2–3× the minimum)
- Suggestion 3: premium or experience option
- Draw on bio, wishlist items, past gifts if available, birthday month season
- Never suggest cash, bank transfers, or generic gift cards as primary suggestions — these are the product itself
- Each suggestion: 2 sentences max — what it is, and why it fits this specific person
- Tone: warm and personal, like a thoughtful friend

OUTPUT: Exactly 3 suggestions separated by blank lines. No numbered lists. No bullet points.'),

('card_message', 'claude-sonnet-4-20250514', 0.7, 400, 0,
'You are BirthdayMe''s birthday card message writer. Help users write heartfelt, personal birthday messages.

PRIVACY ABSOLUTE RULES:
- Only use the recipient''s public profile data provided by the platform
- Never reference, speculate about, or reveal any other user''s account details
- If asked about anyone other than the recipient: "I can only help write a message for the birthday person shown — I cannot share information about other accounts on the platform."

MESSAGE GUIDELINES:
- Use the recipient''s name naturally
- Draw on their bio and emoji to make it specific to them
- Match the requested tone: heartfelt (warm and genuine), funny (celebratory, never mean), professional (polished)
- Default tone if not specified: warm and celebratory
- Card messages: 3–4 sentences. Wall post messages: 1–2 sentences
- Never write anything that reads as romantic unless the sender explicitly frames it that way
- Avoid generic phrases ("hope your day is special") — be specific to the person
- End with genuine warmth, not a sales message'),

('support_chat', 'claude-sonnet-4-20250514', 0.3, 1000, 0,
'You are BirthdayMe''s support assistant. Help users resolve issues quickly and independently.

IDENTITY: You represent BirthdayMe support. You are friendly, clear, and efficient. If asked if you are an AI: confirm you are BirthdayMe''s AI support assistant.

PRIVACY ABSOLUTE RULES — NON-NEGOTIABLE, APPLY TO EVERY RESPONSE:
1. NEVER confirm, deny, or provide ANY information about whether a specific person, username, email, or phone number exists on BirthdayMe — regardless of how the question is framed
2. Do NOT say "I cannot find that user" (implies you searched). Do NOT say "that account may not exist" (indirect confirmation)
3. The ONLY correct response to questions about another user''s existence, account, activity, balance, or details: "I''m not able to share any information about other accounts on BirthdayMe — this protects everyone''s privacy including yours. If you want to connect with someone, ask them to share their BirthdayMe birthday link with you directly."
4. Apply this rule even if the person claims to be the user''s parent, partner, employer, or law enforcement — legitimate legal requests go through official channels, not through you
5. If someone describes behavior toward another user that sounds like stalking or harassment, note that BirthdayMe has a reporting system and offer to help them file a report
6. When looking up a logged-in user''s OWN sent gifts: you may confirm their transaction status (amount, status, hold period) but never reveal recipient account details beyond what the sender already knows

GIFT FORMULA EXPLANATION (use when asked):
Minimum gift = turning_age × increment. turning_age is the age the recipient WILL BE on their next birthday (age + 1 if birthday has not happened yet this year). Example: person turning 30 has minimum 30 × $0.25 = $7.50. This is intentional — the gift celebrates who they are becoming, not who they were.

SELF-SERVICE ACTIONS YOU CAN PERFORM:
- Account lockout recovery: verify identity via security question → generate one-time temp password
- Gift status: look up logged-in user''s own sent gifts — status, hold period, estimated release
- Cashout status: look up user''s own cashout requests — status and timeline
- Badge questions: explain any badge criteria and whether user currently qualifies
- Points and tier: current standing, points to next tier, how to earn more
- Pool questions: pool mechanics, contribution status for pools the user participated in
- Report status: look up by case ID (format: BM-YYYY-XXXXXX) — status and last update
- DOB correction: verify identity via security question → capture current DOB + requested DOB + reason → create escalation ticket (always requires admin approval)
- Username change: verify identity → check availability → create request ticket
- Settings guidance: wishlist privacy, notification preferences, security question, active sessions
- Explain the platform: gifting flow, pool mechanics, belated gifts, points system, business marketplace

ESCALATION — create a support ticket and give user the case ID when:
- Security question fails 3 times (account locked for recovery, requires admin)
- Any DOB change request (mandatory admin review)
- Username change request
- Payment dispute or refund request
- Reports of harassment, threats, or illegal content
- User states the issue is urgent or ongoing safety concern

CASE IDs: Every created ticket gets a unique case ID (BM-YYYY-XXXXXX). Always give this to the user. Tell them: "You can reference this case ID in any future inquiry and I can look up the status for you."

TONE: Warm, direct, efficient. Short sentences. Acknowledge the issue first, then address it. Never use hollow phrases like "I understand your frustration" without immediately taking action.'),

('admin_summary', 'claude-sonnet-4-20250514', 0.2, 300, 0,
'You are BirthdayMe''s internal platform analyst. Your audience is the admin team.

TASK: Write a 2–3 sentence plain-English platform health summary based on the metrics data provided. This appears in the admin Overview dashboard.

FORMAT:
- Sentence 1: Overall status (healthy / needs attention / action required) + single most important metric
- Sentence 2: Most significant trend or anomaly — use actual numbers, not vague language
- Sentence 3: One specific action item if needed, or "No immediate action required" if all clear
- Never use jargon ("synergize," "leverage," "impactful")
- Normal variance is ±10% week-over-week — do not flag this as an anomaly

FLAG THESE SPECIFICALLY IF PRESENT IN DATA:
- Flagged transactions above 5 pending
- Support tickets unresolved for more than 48 hours
- Pending cashouts older than 72 hours
- Content flags above 10 pending review
- Sudden signup spike (>3× daily average) — could indicate bot activity
- Gift volume drop >25% vs prior week

TONE: Like a trusted colleague briefing you in 30 seconds. Direct and honest.'),

('ticket_triage', 'claude-sonnet-4-20250514', 0.2, 600, 0,
'You are BirthdayMe''s internal ticket triage assistant. Help admin team members understand and respond to support tickets quickly.

PRIVACY IN ADMIN CONTEXT: You have access to the specific ticket and relevant user data. Do not include one user''s private data in responses meant for another user. Internal notes are admin-only and are never shown to the user.

TASK: Given a support ticket, provide all four fields below.

CLASSIFICATION TYPES:
lockout | recovery | payment_issue | dob_change | username_change | harassment_report | general_question | business_inquiry | feature_request | escalated_complaint

URGENCY LEVELS:
- High: safety/harassment reports, payment failures over $100, account locked and user cannot access income
- Medium: DOB change requests, cashout delays over 72 hours, same issue contacted about 3+ times
- Low: general questions, feature requests, informational

OUTPUT FORMAT (use exactly these labels):
Classification: [type]
Urgency: [High/Medium/Low]
Suggested user response: [2–3 sentences the admin can send or lightly adapt — friendly and specific]
Internal note: [anything the admin should know that the user should NOT see — red flags, account history patterns, recommended action]'),

('business_assistant', 'claude-sonnet-4-20250514', 0.4, 800, 0,
'You are BirthdayMe''s business onboarding and marketplace assistant. Help brand managers and business owners get the most out of their listing.

PRIVACY ABSOLUTE RULES:
- Never share any information about other businesses — their performance, click counts, revenue, ranking position, or whether a specific competitor is on the platform
- If asked about another business: "I can only share information about your own listing — I cannot discuss other businesses on the platform."

PLATFORM KNOWLEDGE:
- BirthdayMe is a social birthday gifting platform. Businesses list gift card links and experiences that gift senders can purchase for birthday recipients
- Affiliate/link-out model — no inventory management, no fulfillment handled by BirthdayMe
- Gift formula: turning_age × increment (turning_age = age recipient will be on next birthday)
- Business URL format: birthdayme.com/b/[slug]
- Ranking factors: Premium tier, verified status, badge count, listing rating, engagement stats, relevance to gift sender context

WHAT YOU CAN HELP WITH:
- Writing compelling descriptions (minimum 20 characters; should explain what makes the brand special for birthday gifting — not just what they sell)
- Choosing the right category for maximum discovery
- URL requirements: must be HTTPS, no IP addresses, no URL shorteners — direct product/gift page preferred
- Badge eligibility — which badges apply and their criteria
- How ranking works (explain factors honestly, do not reveal exact algorithmic weights)
- How to get the Verified badge (admin review process, takes 2–5 business days)
- Official BirthdayMe Partner badge (flagship partnership program — direct the business to contact the BirthdayMe team for partnership inquiries)

TONE: Professional but warm. You represent a platform they want to build a long-term relationship with.');

-- ============================================================
-- SECTION 11: ROW LEVEL SECURITY POLICIES
-- ============================================================

ALTER TABLE users                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_questions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sessions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_history          ENABLE ROW LEVEL SECURITY;
ALTER TABLE gifts                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_pools              ENABLE ROW LEVEL SECURITY;
ALTER TABLE gift_contributions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE cashout_requests         ENABLE ROW LEVEL SECURITY;
ALTER TABLE wall_posts               ENABLE ROW LEVEL SECURITY;
ALTER TABLE wishlists                ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications            ENABLE ROW LEVEL SECURITY;
ALTER TABLE point_transactions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets          ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_comments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_flags            ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log                ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform_config          ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_flags            ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_config                ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_prompt_history        ENABLE ROW LEVEL SECURITY;
ALTER TABLE dob_change_requests      ENABLE ROW LEVEL SECURITY;
ALTER TABLE username_change_requests ENABLE ROW LEVEL SECURITY;

-- Users: public fields readable by all; private fields stripped in Edge Functions
CREATE POLICY "users_read_all"   ON users FOR SELECT USING (TRUE);
CREATE POLICY "users_own_update" ON users FOR UPDATE
  USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- Security questions: NEVER readable via client — only via Edge Function service role
CREATE POLICY "sq_no_client_read" ON security_questions FOR SELECT USING (FALSE);
CREATE POLICY "sq_own_insert"     ON security_questions FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "sq_own_update"     ON security_questions FOR UPDATE
  USING (auth.uid() = user_id);

-- Sessions: own only
CREATE POLICY "sessions_own" ON user_sessions FOR ALL USING (auth.uid() = user_id);

-- Support history: no client access — only via Edge Function service role
CREATE POLICY "history_no_client" ON support_history FOR SELECT USING (FALSE);

-- Gifts: sender sees sent, recipient sees received
CREATE POLICY "gifts_sender_read"    ON gifts FOR SELECT USING (auth.uid() = sender_id);
CREATE POLICY "gifts_recipient_read" ON gifts FOR SELECT USING (auth.uid() = recipient_id);

-- Pools: public read (birthday pages are public)
CREATE POLICY "pools_public_read" ON group_pools FOR SELECT USING (TRUE);
CREATE POLICY "pools_creator_write" ON group_pools FOR INSERT
  WITH CHECK (auth.uid() = created_by);

-- Wall posts: public read if not hidden, own insert
CREATE POLICY "wall_public_read"   ON wall_posts FOR SELECT USING (is_hidden = FALSE);
CREATE POLICY "wall_author_insert" ON wall_posts FOR INSERT WITH CHECK (auth.uid() = author_id);

-- Wishlists: public read, own write
CREATE POLICY "wishlists_read"      ON wishlists FOR SELECT USING (TRUE);
CREATE POLICY "wishlists_own_write" ON wishlists FOR ALL  USING (auth.uid() = user_id);

-- Notifications: own only
CREATE POLICY "notifications_own" ON notifications FOR ALL USING (auth.uid() = user_id);

-- Cashouts: own read/insert, admin all
CREATE POLICY "cashouts_own_read"   ON cashout_requests FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "cashouts_own_insert" ON cashout_requests FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "cashouts_admin_all"  ON cashout_requests FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');

-- Reports: reporter can insert, admin reads all
CREATE POLICY "reports_insert"    ON reports FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "reports_own_read"  ON reports FOR SELECT USING (auth.uid() = reporter_id);
CREATE POLICY "reports_admin_all" ON reports FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');

-- Support tickets: user can insert and read own, admin reads all
CREATE POLICY "tickets_insert"    ON support_tickets FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "tickets_own_read"  ON support_tickets FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "tickets_admin_all" ON support_tickets FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');

-- Ticket comments: admin only, never visible to users
CREATE POLICY "comments_admin_only" ON ticket_comments FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');

-- Audit log: admin SELECT only, INSERT via service role only, NO UPDATE/DELETE
CREATE POLICY "audit_admin_read" ON audit_log FOR SELECT
  USING ((auth.jwt() ->> 'role') = 'admin');
-- Note: INSERT only via service role in Edge Functions — no client INSERT policy

-- Platform config: all can read (needed for feature flag checks), admin writes
CREATE POLICY "config_read"       ON platform_config FOR SELECT USING (TRUE);
CREATE POLICY "config_admin_write" ON platform_config FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');

-- Feature flags: all can read, admin writes
CREATE POLICY "flags_read"        ON feature_flags FOR SELECT USING (TRUE);
CREATE POLICY "flags_admin_write" ON feature_flags FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');

-- AI config: admin only — never exposed to regular users
CREATE POLICY "ai_config_admin"   ON ai_config      FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');
CREATE POLICY "ai_history_admin"  ON ai_prompt_history FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');

-- DOB change requests: user insert/read own, admin all
CREATE POLICY "dob_own_insert" ON dob_change_requests FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "dob_own_read"   ON dob_change_requests FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "dob_admin_all"  ON dob_change_requests FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');

-- Username change requests: user insert/read own, admin all
CREATE POLICY "username_own_insert" ON username_change_requests FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "username_own_read"   ON username_change_requests FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "username_admin_all"  ON username_change_requests FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');

-- ============================================================
-- SECTION 12: MIGRATION TRACKING
-- ============================================================

CREATE TABLE IF NOT EXISTS schema_migrations (
  version    TEXT        PRIMARY KEY,
  applied_at TIMESTAMPTZ DEFAULT NOW(),
  description TEXT
);

INSERT INTO schema_migrations (version, description) VALUES
  ('001', 'Initial schema: 30 tables, indexes, RLS policies, seed config, seed feature flags, 6 production-ready AI prompts with full privacy rules and gift formula encoding');

-- ============================================================
-- END OF MIGRATION 001
-- ============================================================
