# Set up the AI helper (free)

1. Get a Gemini key: go to https://aistudio.google.com, sign in, click "Get API key".
2. Make a free Cloudflare account at https://dash.cloudflare.com.
3. In Cloudflare: Workers & Pages > Create > Create Worker. Name it `muse-ai`, click Deploy,
   then "Edit code". Delete the sample code, paste in `index.js` from this folder, click Deploy.
4. In the Worker's Settings > Variables and Secrets, add a **Secret** named `GEMINI_API_KEY`
   and paste your key. Deploy again.
5. (Recommended) Add a plain variable `ALLOWED_ORIGIN` with your site address,
   e.g. `https://YOUR_USERNAME.github.io`, so other websites can't use your Worker from a browser.
6. Copy the Worker address (looks like `https://muse-ai.YOURNAME.workers.dev`) and paste it
   into `aiEndpoint` near the top of `lib/main.dart`. Commit the change.

Menu names in Cloudflare change from time to time, so they may look slightly different.

## Updating the Worker
When `index.js` changes (for example to add wardrobe scanning), open your Worker in Cloudflare,
click "Edit code", replace everything with the new `index.js`, and click Deploy.
Your secret and address stay the same.
