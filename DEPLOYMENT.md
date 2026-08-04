# PocketKernel production deployment

- Vercel project: `pocketkernel`
- Production API: `https://pocketkernel.vercel.app`
- Health endpoint: `https://pocketkernel.vercel.app/api/health`
- Vercel project ID: `prj_TRI0A2bvhIS7Maz31j3IKGeghXDn`

The production function is deployed and reports its configuration state through `/api/health`.

Before public OAuth and scheduled execution are enabled, configure the private Vercel environment variables documented in `.env.example` and register the production callback URL with each provider. No credentials are committed to Git or embedded in the IPA.
