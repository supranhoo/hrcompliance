# Deployment

**Status: nothing deployed. No Supabase, Cloudflare or Google project has been provisioned (no credentials/authorisation supplied).**

## Target
Dev / UAT / Prod each get: a Supabase project, a Cloudflare Pages project, a Google OAuth client, a Drive root folder.
Frontend is a static Vite build (`apps/web/dist`), host-agnostic.

## Release flow
Dev → automated validation (`npm run validate`, CI) → internal test → UAT → release review → prod migration (`supabase db push` reviewed) → prod deploy → smoke test → verification.
Production deployment requires explicit authorisation from BFCL; migrations are never hand-applied to production.

## Environment variables
See `.env.example`. Browser gets only `VITE_*`. Service-role, Google client secret and Gmail credentials live in Supabase function secrets / CI secrets.

## Rollback
Each migration header carries rollback guidance. Data-bearing migrations (from Phase 5) must ship a tested down-script before UAT.
