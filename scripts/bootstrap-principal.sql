\set ON_ERROR_STOP on

SELECT set_config('notes_bootstrap.role_name', :'app_role', false);
SELECT set_config('notes_bootstrap.object_id', :'app_oid', false);

DO $bootstrap$
DECLARE
    expected_role text := current_setting('notes_bootstrap.role_name');
    expected_oid text := current_setting('notes_bootstrap.object_id');
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = expected_role) THEN
        PERFORM pg_catalog.pgaadauth_create_principal_with_oid(expected_role, expected_oid, 'service', false, false);
    ELSIF NOT EXISTS (
        SELECT FROM pg_catalog.pgaadauth_list_principals(false)
          AS p(role_name, principal_type, object_id, tenant_id, is_mfa, is_admin)
        WHERE p.role_name = expected_role AND lower(p.object_id) = lower(expected_oid)
          AND p.principal_type = 'service' AND p.is_admin = 0
    ) THEN
        RAISE EXCEPTION 'Existing application role does not match the expected non-admin managed identity. Refusing to remap it.';
    END IF;
END
$bootstrap$;
