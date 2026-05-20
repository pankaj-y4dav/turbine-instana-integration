-- =============================================================================
-- instana_native.sql — Native instana_* table queries via steampipe-plugin-instana
--
-- These use the compiled Go plugin (no net_http_request needed).
--
-- Run interactively:
--   docker exec -it steampipe steampipe query
--
-- Run this file:
--   docker exec steampipe bash /home/steampipe/queries/run.sh \
--          /home/steampipe/queries/instana_native.sql
--
-- Required env vars (set in .env):
--   INSTANA_API_TOKEN     your Instana API token
--   INSTANA_ENDPOINT_URL  https://your-tenant.instana.io
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. MON-7 CCF — Smart Alert configurations (primary control evidence)
-- ---------------------------------------------------------------------------
select
  id,
  name,
  last_updated,
  invalid,
  integration_ids,
  alert_channel_names
from
  instana_alert
order by
  name;


-- ---------------------------------------------------------------------------
-- 2. MON-7 CCF — Alerts referencing notification channels
-- ---------------------------------------------------------------------------
select
  id,
  name,
  alert_channel_names,
  integration_ids,
  last_updated
from
  instana_alert
where
  invalid = false
order by
  name;


-- ---------------------------------------------------------------------------
-- 3. Alert channels — notification destinations
-- ---------------------------------------------------------------------------
select
  id,
  name,
  kind
from
  instana_alert_channel
order by
  kind, name;


-- ---------------------------------------------------------------------------
-- 4. Application perspectives
-- ---------------------------------------------------------------------------
select
  id,
  label,
  scope,
  boundary_scope
from
  instana_application
order by
  label;


-- ---------------------------------------------------------------------------
-- 5. Infrastructure hosts
-- ---------------------------------------------------------------------------
select
  snapshot_id,
  host_name,
  host,
  created_at,
  last_change
from
  instana_host
order by
  host_name;


-- ---------------------------------------------------------------------------
-- 6. Service Level Indicators
-- ---------------------------------------------------------------------------
select
  id,
  name,
  sli_type,
  metric_threshold,
  metric_name,
  metric_aggregation
from
  instana_sli
order by
  metric_threshold desc;


-- ---------------------------------------------------------------------------
-- 7. Open events in the last hour (default window)
-- ---------------------------------------------------------------------------
select
  event_type,
  severity,
  state,
  entity_name,
  problem,
  start
from
  instana_event
where
  state = 'open'
order by
  severity desc,
  start desc;


-- ---------------------------------------------------------------------------
-- 8. Teams
-- ---------------------------------------------------------------------------
select
  id,
  tag,
  info ->> 'description' as description
from
  instana_team
order by
  tag;


-- ---------------------------------------------------------------------------
-- 9. Users and their login info
-- ---------------------------------------------------------------------------
select
  id,
  email,
  full_name,
  group_count,
  last_logged_in,
  tfa_enabled
from
  instana_user
order by
  email;


-- ---------------------------------------------------------------------------
-- 10. Website monitoring configurations
-- ---------------------------------------------------------------------------
select
  id,
  name,
  app_name,
  tags
from
  instana_website_monitoring
order by
  name;
