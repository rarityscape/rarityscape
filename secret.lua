-- Signing key for the rarity API (see sign.lua). Must match one of the backend's SIGNING_KEYS;
-- the local docker-compose.yml and production both use this one. Not a real secret: anyone
-- can read it here. It only keeps out casual requests. Give each release that changes it a
-- new version.
return { version = "v1", key = "dev-signing-key" }
