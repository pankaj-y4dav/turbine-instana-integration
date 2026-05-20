-- =============================================================================
-- instana_query.sql — Instana REST API queries via net_http_request
-- Mirrors all tables in steampipe-plugin-instana (Python plugin reference)
--
-- Run (from host):
--   docker exec steampipe bash /home/steampipe/queries/run.sh \
--          /home/steampipe/queries/instana_query.sql
--
-- Required env vars in .env:
--   INSTANA_BASE_URL   e.g.  test-hcp.instana.io  (no https://)
--   INSTANA_API_KEY    your Instana API token
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. instana_alert — Smart Alert configurations (MON-7 CCF primary table)
-- ---------------------------------------------------------------------------
with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url            = 'https://${INSTANA_BASE_URL}/api/alerts'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),
items as (
    -- response is either {"items":[...]} or a bare array
    select
        case
            when jsonb_typeof(data) = 'array' then jsonb_array_elements(data)
            else jsonb_array_elements(data->'items')
        end as alert
    from raw
)
select
    alert->>'id'                                      as id,
    alert->>'name'                                    as name,
    alert->>'severity'                                as severity,
    (alert->>'enabled')::boolean                      as enabled,
    alert->'threshold'->>'operator'                   as threshold_operator,
    alert->'threshold'->>'value'                      as threshold_value,
    (alert->'timeThreshold'->>'timeWindow')::bigint   as time_threshold_ms,
    alert->'alertChannelIds'                          as alert_channel_ids,
    alert->>'description'                             as description,
    to_timestamp(
        (alert->>'createdAt')::bigint / 1000
    )                                                 as created_at,
    to_timestamp(
        (alert->>'modifiedAt')::bigint / 1000
    )                                                 as modified_at
from
    items
order by
    severity, name;


-- ---------------------------------------------------------------------------
-- 2. instana_alert — Enabled critical alerts only (MON-7 CCF evidence)
-- ---------------------------------------------------------------------------
with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url            = 'https://${INSTANA_BASE_URL}/api/alerts'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),
items as (
    select
        case
            when jsonb_typeof(data) = 'array' then jsonb_array_elements(data)
            else jsonb_array_elements(data->'items')
        end as alert
    from raw
)
select
    alert->>'id'                     as id,
    alert->>'name'                   as name,
    alert->'threshold'->>'operator'  as threshold_operator,
    alert->'threshold'->>'value'     as threshold_value,
    jsonb_array_length(
        coalesce(alert->'alertChannelIds', '[]'::jsonb)
    )                                as channel_count
from
    items
where
    alert->>'severity' = 'critical'
    and (alert->>'enabled')::boolean = true
order by
    name;


-- ---------------------------------------------------------------------------
-- 3. instana_alert — Alerts with NO notification channel (coverage gap)
-- ---------------------------------------------------------------------------
with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url            = 'https://${INSTANA_BASE_URL}/api/alerts'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),
items as (
    select
        case
            when jsonb_typeof(data) = 'array' then jsonb_array_elements(data)
            else jsonb_array_elements(data->'items')
        end as alert
    from raw
)
select
    alert->>'id'       as id,
    alert->>'name'     as name,
    alert->>'severity' as severity,
    (alert->>'enabled')::boolean as enabled
from
    items
where
    jsonb_array_length(
        coalesce(alert->'alertChannelIds', '[]'::jsonb)
    ) = 0
order by
    severity, name;


-- ---------------------------------------------------------------------------
-- 4. instana_alert_channel — All alerting channels
-- ---------------------------------------------------------------------------
with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url            = 'https://${INSTANA_BASE_URL}/api/alerting-channels'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),
items as (
    select
        case
            when jsonb_typeof(data) = 'array' then jsonb_array_elements(data)
            else jsonb_array_elements(data->'items')
        end as ch
    from raw
)
select
    ch->>'id'                                          as id,
    ch->>'name'                                        as name,
    ch->>'kind'                                        as kind,
    coalesce(ch->>'webhookUrl', ch->>'url')            as webhook_url,
    coalesce(
        ch->>'integrationKey',
        ch->>'serviceIntegrationKey',
        ch->>'apiKey'
    )                                                  as integration_key,
    ch->'emails'                                       as emails
from
    items
order by
    kind, name;


-- ---------------------------------------------------------------------------
-- 5. instana_application — Application perspectives
-- ---------------------------------------------------------------------------
with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url            = 'https://${INSTANA_BASE_URL}/api/application-monitoring/applications'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),
items as (
    select
        case
            when jsonb_typeof(data) = 'array' then jsonb_array_elements(data)
            else jsonb_array_elements(data->'items')
        end as app
    from raw
)
select
    app->>'id'            as id,
    coalesce(
        app->>'label',
        app->>'name'
    )                     as label,
    app->>'scope'         as scope,
    app->>'boundaryScope' as boundary_scope
from
    items
order by
    label;


-- ---------------------------------------------------------------------------
-- 6. instana_event — Recent events (default: now-1h to now)
-- ---------------------------------------------------------------------------
with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url = 'https://${INSTANA_BASE_URL}/api/events?windowSize=3600000'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),
items as (
    select
        case
            when jsonb_typeof(data) = 'array' then jsonb_array_elements(data)
            else jsonb_array_elements(data->'items')
        end as ev
    from raw
)
select
    ev->>'id'                                              as id,
    ev->>'title'                                           as title,
    coalesce(ev->>'type', ev->>'eventType')                as event_type,
    (ev->>'severity')::int                                 as severity,
    to_timestamp((ev->>'start')::bigint / 1000)            as start_time,
    to_timestamp((ev->>'end')::bigint / 1000)              as end_time,
    (ev->>'duration')::bigint                              as duration_ms,
    coalesce(
        ev->'entity'->>'name',
        ev->'entityInfo'->>'name'
    )                                                      as entity_name
from
    items
order by
    start_time desc;


-- ---------------------------------------------------------------------------
-- 7. instana_host — Infrastructure hosts
-- ---------------------------------------------------------------------------
with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url            = 'https://${INSTANA_BASE_URL}/api/infrastructure-monitoring/snapshots?plugin=host'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),
items as (
    select
        case
            when jsonb_typeof(data) = 'array' then jsonb_array_elements(data)
            else jsonb_array_elements(data->'items')
        end as host
    from raw
)
select
    host->>'snapshotId'                            as snapshot_id,
    coalesce(
        host->>'label',
        host->'data'->>'hostName'
    )                                              as host_name,
    host->'data'->>'osName'                        as os_name,
    host->'data'->>'osVersion'                     as os_version,
    host->'data'->>'agentVersion'                  as agent_version,
    (host->'data'->>'cpuCores')::int               as cpu_cores
from
    items
order by
    host_name;


-- ---------------------------------------------------------------------------
-- 8. instana_user — Platform users
-- ---------------------------------------------------------------------------
with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url            = 'https://${INSTANA_BASE_URL}/api/settings/users'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),
items as (
    select
        case
            when jsonb_typeof(data) = 'array' then jsonb_array_elements(data)
            else jsonb_array_elements(data->'items')
        end as usr
    from raw
)
select
    coalesce(usr->>'id', usr->>'userId')           as id,
    usr->>'email'                                  as email,
    trim(
        coalesce(usr->>'firstName','') || ' ' ||
        coalesce(usr->>'lastName','')
    )                                              as full_name,
    usr->>'role'                                   as role
from
    items
order by
    email;


-- ---------------------------------------------------------------------------
-- 9. instana_team — Teams / groups
-- ---------------------------------------------------------------------------
with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url            = 'https://${INSTANA_BASE_URL}/api/settings/teams'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),
items as (
    select
        case
            when jsonb_typeof(data) = 'array' then jsonb_array_elements(data)
            else jsonb_array_elements(data->'items')
        end as team
    from raw
)
select
    team->>'id'                                        as id,
    team->>'name'                                      as name,
    jsonb_array_length(
        coalesce(team->'members', '[]'::jsonb)
    )                                                  as member_count,
    team->'members'                                    as members
from
    items
order by
    member_count desc;


-- ---------------------------------------------------------------------------
-- 10. instana_sli — Service Level Indicators / Objectives
-- ---------------------------------------------------------------------------
with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url            = 'https://${INSTANA_BASE_URL}/api/slos'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),
items as (
    select
        case
            when jsonb_typeof(data) = 'array' then jsonb_array_elements(data)
            else jsonb_array_elements(data->'items')
        end as sli
    from raw
)
select
    sli->>'id'                                                    as id,
    sli->>'name'                                                  as name,
    coalesce(sli->>'sliType', sli->>'type')                      as sli_type,
    (coalesce(sli->>'targetPercentage', sli->>'target'))::float  as target_percentage,
    sli->'metricConfiguration'->>'metricName'                    as metric_name
from
    items
order by
    target_percentage desc;
