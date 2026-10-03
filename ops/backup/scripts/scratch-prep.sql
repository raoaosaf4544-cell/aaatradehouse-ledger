-- Prepares the throw-away database for the nightly restore test: the roles named in our grants and row-security
-- rules, and a stand-in for Supabase's auth.uid() (four functions call it).
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create role jarvis_cloud nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as 'select null::uuid';
