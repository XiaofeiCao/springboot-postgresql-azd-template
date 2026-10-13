\set ON_ERROR_STOP on

GRANT CONNECT ON DATABASE :"app_database" TO :"app_role";
CREATE SCHEMA IF NOT EXISTS notes;
GRANT USAGE, CREATE ON SCHEMA notes TO :"app_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA notes TO :"app_role";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA notes TO :"app_role";
ALTER DEFAULT PRIVILEGES IN SCHEMA notes GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"app_role";
ALTER DEFAULT PRIVILEGES IN SCHEMA notes GRANT USAGE, SELECT ON SEQUENCES TO :"app_role";

-- Objects created by the application also need to be writable by the local developer.
GRANT :"app_role" TO :"developer_role";
ALTER ROLE :"app_role" IN DATABASE :"app_database" SET search_path = notes, public;
ALTER ROLE :"developer_role" IN DATABASE :"app_database" SET search_path = notes, public;
