-- Ensure the postgres role exists and has the correct permissions
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        CREATE ROLE postgres WITH SUPERUSER CREATEDB CREATEROLE LOGIN PASSWORD '${POSTGRES_PASSWORD}';
    END IF;
    
    -- Ensure supabase_admin role exists
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
        CREATE ROLE supabase_admin WITH SUPERUSER CREATEDB CREATEROLE LOGIN PASSWORD '${POSTGRES_PASSWORD}';
    END IF;
    
    -- Grant necessary permissions
    GRANT ALL PRIVILEGES ON DATABASE postgres TO supabase_admin;
    GRANT ALL PRIVILEGES ON SCHEMA public TO supabase_admin;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO supabase_admin;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO supabase_admin;
    
    -- Allow supabase_admin to create extensions
    ALTER ROLE supabase_admin CREATEEXT;
END
$$;
