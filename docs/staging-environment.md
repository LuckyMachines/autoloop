# Staging Environment

The staging environment mirrors production but uses separate worker keys and can be torn down without affecting production.

## Architecture

Same as production:
- 3 worker instances on Railway
- 1 dashboard instance on Railway
- All pointing to Sepolia testnet

## Setup

Run from the AUTOLOOP_STUFF root:
```bash
./setup-staging.sh
```

This will:
1. Create a Railway project
2. Generate 3 worker keypairs (saved to `autoloop-worker/.env.staging-keys`)
3. Print next steps for manual Railway configuration

## Differences from Production

| Aspect | Production | Staging |
|--------|-----------|---------|
| Worker keys | `.env.worker-keys` | `.env.staging-keys` |
| Railway project | autoloop-production | autoloop-staging |
| Worker URLs | `*-production.up.railway.app` | `*-staging.up.railway.app` |

## Teardown

```bash
# Remove Railway staging project
railway delete --yes

# Remove staging keys
rm autoloop-worker/.env.staging-keys
```
