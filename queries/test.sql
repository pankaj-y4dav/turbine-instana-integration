with raw as (
    select
        response_body::jsonb as data
    from
        net_http_request
    where
        url = 'https://test-hcp.instana.io/api/application-monitoring/services'
        and request_headers = '{"authorization": "apiToken ${INSTANA_API_KEY}"}'::jsonb
),

services as (
    select
        jsonb_array_elements(data -> 'items') as svc
    from raw
)

select
    svc->>'id' as service_id,
    svc->>'label' as label,
    svc->>'entityType' as entity_type,
    svc->>'healthState' as health_state,
    svc->>'technologies' as technologies
from
    services;
