-- Migration: 001 - Schema Setup
-- Description: Verify APP schema is ready
-- Note: This script runs as APP_USER (comercial) in XEPDB1 automatically

-- The user 'APP' is already created by the container with APP_USER/APP_USER_PASSWORD
-- This script just validates the setup and prepares for table creation

-- Verify we can query the schema
SELECT 'Schema APP is ready!' AS status FROM dual;

-- Show current user and database
SELECT
    USER AS current_user,
    SYS_CONTEXT ('USERENV', 'CON_NAME') AS database_name,
    SYS_CONTEXT ('USERENV', 'DB_NAME') AS instance_name
FROM dual;
/